import { LightningElement, api, wire } from "lwc";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import {
  getRecord,
  getFieldValue,
  updateRecord,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import CASE_OBJECT from "@salesforce/schema/Case";
import PRODUCT_CONFIG_FIELD from "@salesforce/schema/Product2.Onboarding_Config__c";
import PRODUCT_LAST_MODIFIED_FIELD from "@salesforce/schema/Product2.LastModifiedDate";
import CASE_CONFIG_FIELD from "@salesforce/schema/Case.Case_Onboarding__c";
import CASE_LAST_MODIFIED_FIELD from "@salesforce/schema/Case.LastModifiedDate";

const RECORD_CONFIGS = {
  Product2: {
    configApiName: "Onboarding_Config__c",
    configField: PRODUCT_CONFIG_FIELD,
    lastModifiedField: PRODUCT_LAST_MODIFIED_FIELD,
    fields: [PRODUCT_CONFIG_FIELD, PRODUCT_LAST_MODIFIED_FIELD],
    label: "Product"
  },
  Case: {
    configApiName: "Case_Onboarding__c",
    configField: CASE_CONFIG_FIELD,
    lastModifiedField: CASE_LAST_MODIFIED_FIELD,
    fields: [CASE_CONFIG_FIELD, CASE_LAST_MODIFIED_FIELD],
    label: "Case"
  }
};

function errorMessage(error) {
  const messages = [
    ...(Array.isArray(error?.body) ? error.body : []),
    ...(error?.body?.output?.errors || []),
    ...Object.values(error?.body?.output?.fieldErrors || {}).flat()
  ].map((item) => item.message);
  return (
    messages.filter(Boolean).join(" ") ||
    error?.body?.message ||
    error?.message ||
    "An unexpected error occurred."
  );
}

function parseConfig(value) {
  if (!value || !value.trim()) {
    return [];
  }
  const rows = JSON.parse(value);
  if (!Array.isArray(rows)) {
    throw new Error("Expected an array of Case field settings.");
  }
  const seen = new Set();
  return rows.map((row) => {
    if (
      !row ||
      typeof row.fieldapiname !== "string" ||
      !row.fieldapiname.trim() ||
      typeof row.fieldlabel !== "string" ||
      typeof row.required !== "boolean"
    ) {
      throw new Error(
        "Each entry must contain fieldapiname, fieldlabel, and a boolean required value."
      );
    }
    const apiName = row.fieldapiname.trim();
    if (seen.has(apiName.toLowerCase())) {
      throw new Error(`The field ${apiName} is configured more than once.`);
    }
    seen.add(apiName.toLowerCase());
    return {
      fieldapiname: apiName,
      fieldlabel: row.fieldlabel,
      required: row.required
    };
  });
}

export default class ProductOnboardingConfig extends LightningElement {
  _recordId;
  _objectApiName = "Product2";
  recordVersion = 0;
  savedRows = [];
  draftRows = [];
  caseFields = {};
  recordInfo;
  recordLoaded = false;
  caseInfoLoaded = false;
  isEditing = false;
  isSaving = false;
  recordError;
  caseInfoError;
  recordInfoError;
  configError;
  saveError;
  lastModifiedDate;
  editLastModifiedDate;
  draggedKey;
  nextKey = 0;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (value !== this._recordId) {
      this._recordId = value;
      this.resetRecordState();
    }
  }

  @api
  get objectApiName() {
    return this._objectApiName;
  }

  set objectApiName(value) {
    const objectApiName = value || "Product2";
    if (objectApiName !== this._objectApiName) {
      this._objectApiName = objectApiName;
      this.recordInfo = undefined;
      this.recordInfoError = undefined;
      this.resetRecordState();
    }
  }

  resetRecordState() {
    this.recordVersion++;
    this.savedRows = [];
    this.draftRows = [];
    this.recordLoaded = false;
    this.recordError = undefined;
    this.configError = undefined;
    this.saveError = undefined;
    this.lastModifiedDate = undefined;
    this.editLastModifiedDate = undefined;
    this.isEditing = false;
    this.isSaving = false;
    this.draggedKey = undefined;
  }

  get recordConfig() {
    return RECORD_CONFIGS[this.objectApiName];
  }

  get recordFields() {
    return this.recordConfig?.fields;
  }

  @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
  wiredCaseInfo({ data, error }) {
    if (data) {
      this.caseFields = data.fields;
      this.caseInfoLoaded = true;
      this.caseInfoError = undefined;
    } else if (error) {
      this.caseFields = {};
      this.caseInfoLoaded = false;
      this.caseInfoError = `Unable to load Case fields. ${errorMessage(error)}`;
    }
  }

  @wire(getObjectInfo, { objectApiName: "$objectApiName" })
  wiredRecordInfo({ data, error }) {
    if (data && data.apiName === this.objectApiName) {
      this.recordInfo = data;
      this.recordInfoError = undefined;
    } else if (error) {
      this.recordInfo = undefined;
      this.recordInfoError = `Unable to load ${this.recordConfig?.label || "record"} permissions. ${errorMessage(error)}`;
    }
  }

  @wire(getRecord, {
    recordId: "$recordId",
    fields: "$recordFields"
  })
  wiredRecord({ data, error }) {
    if (
      data &&
      data.id === this.recordId &&
      data.apiName === this.objectApiName
    ) {
      this.recordLoaded = true;
      this.recordError = undefined;
      this.lastModifiedDate = getFieldValue(
        data,
        this.recordConfig.lastModifiedField
      );
      try {
        this.savedRows = parseConfig(
          getFieldValue(data, this.recordConfig.configField)
        );
        this.configError = undefined;
      } catch (parseError) {
        this.savedRows = [];
        this.configError = `The saved onboarding configuration is invalid. ${parseError.message} Correct ${this.recordConfig.configApiName} before editing here.`;
      }
    } else if (error) {
      this.recordLoaded = false;
      this.savedRows = [];
      this.recordError = `Unable to load the onboarding configuration. ${errorMessage(error)}`;
    }
  }

  get error() {
    if (!this.recordConfig) {
      return "Onboarding configuration is only available for Product and Case records.";
    }
    return (
      this.recordError ||
      this.configError ||
      this.caseInfoError ||
      this.recordInfoError ||
      this.saveError
    );
  }

  get isLoading() {
    return (
      this.recordId &&
      !this.error &&
      (!this.recordLoaded || !this.caseInfoLoaded || !this.recordInfo)
    );
  }

  get showReadOnlyNotice() {
    return this.recordInfo && !this.canUpdate && !this.error;
  }

  get canUpdate() {
    return Boolean(
      this.recordInfo?.updateable &&
      this.recordInfo.fields[this.recordConfig?.configApiName]?.updateable
    );
  }

  get editDisabled() {
    return (
      !this.recordLoaded ||
      !this.caseInfoLoaded ||
      !this.canUpdate ||
      Boolean(this.error)
    );
  }

  get saveDisabled() {
    return (
      this.isSaving ||
      !this.recordLoaded ||
      !this.caseInfoLoaded ||
      !this.canUpdate ||
      Boolean(this.configError || this.recordError)
    );
  }

  get addDisabled() {
    return (
      this.isSaving ||
      !this.fieldOptions.some(
        (option) =>
          !this.draftRows.some((row) => row.fieldapiname === option.value)
      )
    );
  }

  get canDrag() {
    return !this.isSaving;
  }

  get fieldOptions() {
    return Object.values(this.caseFields)
      .map((field) => ({
        label: `${field.label} (${field.apiName})`,
        value: field.apiName
      }))
      .sort((left, right) => left.label.localeCompare(right.label));
  }

  get displayRows() {
    return this.savedRows.map((row) => ({
      ...row,
      label:
        row.fieldlabel ||
        this.caseFields[row.fieldapiname]?.label ||
        row.fieldapiname,
      requiredLabel: row.required ? "Required" : "Optional"
    }));
  }

  get editorRows() {
    const options = this.fieldOptions;
    const selected = new Set(this.draftRows.map((row) => row.fieldapiname));
    return this.draftRows.map((row, index) => {
      const available =
        !row.fieldapiname || Boolean(this.caseFields[row.fieldapiname]);
      let rowOptions = options.filter(
        (option) =>
          option.value === row.fieldapiname || !selected.has(option.value)
      );
      if (!available) {
        rowOptions = [
          {
            label: `${row.fieldapiname} (unavailable)`,
            value: row.fieldapiname
          },
          ...rowOptions
        ];
      }
      return {
        ...row,
        position: index + 1,
        options: rowOptions,
        defaultLabel:
          this.caseFields[row.fieldapiname]?.label ||
          "Use the Case field label",
        unavailable: !available,
        moveUpDisabled: this.isSaving || index === 0,
        moveDownDisabled: this.isSaving || index === this.draftRows.length - 1,
        moveUpLabel: `Move field ${index + 1} up`,
        moveDownLabel: `Move field ${index + 1} down`,
        removeLabel: `Remove field ${index + 1}`
      };
    });
  }

  get hasSavedRows() {
    return this.savedRows.length > 0;
  }

  get hasDraftRows() {
    return this.draftRows.length > 0;
  }

  get showEmptySaved() {
    return !this.configError;
  }

  handleEdit() {
    if (this.editDisabled) return;
    this.draftRows = this.savedRows.map((row) => ({
      ...row,
      key: String(this.nextKey++)
    }));
    this.editLastModifiedDate = this.lastModifiedDate;
    this.saveError = undefined;
    this.isEditing = true;
  }

  handleCancel() {
    if (this.isSaving) return;
    this.isEditing = false;
    this.draftRows = [];
    this.saveError = undefined;
    this.draggedKey = undefined;
  }

  handleAdd() {
    if (this.addDisabled) return;
    this.draftRows = [
      ...this.draftRows,
      {
        key: String(this.nextKey++),
        fieldapiname: "",
        fieldlabel: "",
        required: false
      }
    ];
  }

  handleFieldChange(event) {
    this.updateRow(event.currentTarget.dataset.key, {
      fieldapiname: event.detail.value
    });
  }

  handleLabelChange(event) {
    this.updateRow(event.currentTarget.dataset.key, {
      fieldlabel: event.target.value
    });
  }

  handleRequiredChange(event) {
    this.updateRow(event.currentTarget.dataset.key, {
      required: event.target.checked
    });
  }

  updateRow(key, changes) {
    if (this.isSaving) return;
    this.draftRows = this.draftRows.map((row) =>
      row.key === key ? { ...row, ...changes } : row
    );
    this.saveError = undefined;
  }

  handleRemove(event) {
    if (this.isSaving) return;
    this.draftRows = this.draftRows.filter(
      (row) => row.key !== event.currentTarget.dataset.key
    );
    this.saveError = undefined;
  }

  handleMove(event) {
    const index = this.draftRows.findIndex(
      (row) => row.key === event.currentTarget.dataset.key
    );
    this.moveRow(index, index + Number(event.currentTarget.dataset.direction));
  }

  moveRow(from, to) {
    if (
      this.isSaving ||
      from < 0 ||
      to < 0 ||
      to >= this.draftRows.length ||
      from === to
    )
      return;
    const rows = [...this.draftRows];
    const [row] = rows.splice(from, 1);
    rows.splice(to, 0, row);
    this.draftRows = rows;
  }

  handleDragStart(event) {
    if (this.isSaving) return;
    this.draggedKey = event.currentTarget.dataset.key;
    event.dataTransfer.setData("text/plain", this.draggedKey);
    event.dataTransfer.effectAllowed = "move";
  }

  handleDragOver(event) {
    if (this.draggedKey && !this.isSaving) {
      event.preventDefault();
      event.dataTransfer.dropEffect = "move";
    }
  }

  handleDrop(event) {
    if (!this.draggedKey || this.isSaving) return;
    event.preventDefault();
    this.moveRow(
      this.draftRows.findIndex((row) => row.key === this.draggedKey),
      this.draftRows.findIndex(
        (row) => row.key === event.currentTarget.dataset.key
      )
    );
    this.draggedKey = undefined;
  }

  handleDragEnd() {
    this.draggedKey = undefined;
  }

  async handleSave() {
    if (this.saveDisabled) return;
    this.saveError = undefined;
    const inputs = [
      ...this.template.querySelectorAll("lightning-combobox, lightning-input")
    ];
    if (!inputs.reduce((valid, input) => input.reportValidity() && valid, true))
      return;
    const seen = new Set();
    const rows = [];
    for (const row of this.draftRows) {
      if (!row.fieldapiname || seen.has(row.fieldapiname.toLowerCase())) {
        this.saveError = "Select a different Case field for every row.";
        return;
      }
      if (
        !this.caseFields[row.fieldapiname] &&
        !this.savedRows.some((saved) => saved.fieldapiname === row.fieldapiname)
      ) {
        this.saveError = "Select an available Case field for every new row.";
        return;
      }
      seen.add(row.fieldapiname.toLowerCase());
      rows.push({
        fieldapiname: row.fieldapiname,
        fieldlabel: row.fieldlabel.trim(),
        required: row.required
      });
    }
    const json = JSON.stringify(rows);
    const configApiName = this.recordConfig.configApiName;
    const maxLength = this.recordInfo.fields[configApiName].length;
    if (maxLength && json.length > maxLength) {
      this.saveError = `The configuration exceeds the field limit of ${maxLength} characters. Remove fields or shorten override labels.`;
      return;
    }
    const recordId = this.recordId;
    const recordLabel = this.recordConfig.label;
    const recordVersion = this.recordVersion;
    this.isSaving = true;
    try {
      await updateRecord(
        { fields: { Id: recordId, [configApiName]: json } },
        { ifUnmodifiedSince: this.editLastModifiedDate }
      );
      if (this.recordVersion !== recordVersion) return;
      this.savedRows = rows;
      this.isEditing = false;
      this.draftRows = [];
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Saved",
          message: "Onboarding configuration saved.",
          variant: "success"
        })
      );
    } catch (error) {
      if (this.recordVersion === recordVersion) {
        this.saveError =
          error.status === 412
            ? `This ${recordLabel} was changed by another user. Cancel to view the latest configuration, then edit again.`
            : `Unable to save the onboarding configuration. ${errorMessage(error)}`;
        if (error.status === 412) {
          try {
            await notifyRecordUpdateAvailable([{ recordId }]);
          } catch (refreshError) {
            if (this.recordVersion === recordVersion) {
              this.saveError = `Unable to reload this ${recordLabel}. Cancel and refresh the page before editing again. ${errorMessage(refreshError)}`;
            }
          }
        }
      }
    } finally {
      if (this.recordVersion === recordVersion) this.isSaving = false;
    }
  }
}
