import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import REQUIRED_FILE from "@salesforce/schema/Required_File__c";
import ACCEPTED_FORMAT from "@salesforce/schema/Required_File__c.Accepted_Format__c";
import getSetup from "@salesforce/apex/ProductSetupController.getSetup";
import savePricebooks from "@salesforce/apex/ProductSetupController.savePricebooks";
import saveRequirements from "@salesforce/apex/ProductSetupController.saveRequirements";

function messageFrom(error) {
  return (
    error?.body?.message || error?.message || "An unexpected error occurred."
  );
}

export default class ProductSetup extends LightningElement {
  _recordId;
  createdProductId;
  pricebooks = [];
  templates = [];
  requirements = [];
  paymentTypeOptions = [];
  loading = false;
  savingPricebooks = false;
  savingRequirements = false;
  error;
  nextKey = 0;
  documentDraft;
  documentDialogMode;
  documentDialogTrigger;
  showInstructionError = false;

  @wire(getObjectInfo, { objectApiName: REQUIRED_FILE })
  requiredFileInfo;

  @wire(getPicklistValues, {
    recordTypeId: "$requiredFileInfo.data.defaultRecordTypeId",
    fieldApiName: ACCEPTED_FORMAT
  })
  acceptedFormats;

  get formatOptions() {
    const options = this.acceptedFormats?.data?.values || [];
    const existingValues = (this.documentDraft?.acceptedFormat || "")
      .split(";")
      .filter(Boolean);
    return [
      ...options,
      ...existingValues
        .filter((value) => !options.some((option) => option.value === value))
        .map((value) => ({ label: value, value }))
    ];
  }

  get selectedFormats() {
    return (this.documentDraft?.acceptedFormat || "")
      .split(";")
      .filter(Boolean);
  }

  get documentDialogTitle() {
    return `${this.documentDialogMode} Required Document`;
  }

  get instructionsValid() {
    return !this.showInstructionError;
  }

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (value === this._recordId) return;
    this._recordId = value;
    this.documentDraft = undefined;
    if (value) this.loadSetup();
  }

  get productId() {
    return this.recordId || this.createdProductId;
  }

  get showProductCreator() {
    return !this.productId;
  }

  get showSetup() {
    return Boolean(this.productId);
  }

  get templateOptions() {
    return [
      { label: "No template — configure manually", value: "" },
      ...this.templates.map((template) => ({
        label: `${template.name}${template.active ? "" : " (inactive)"}`,
        value: template.id
      }))
    ];
  }

  get hasRequirements() {
    return this.requirements.length > 0;
  }

  get pricebookSaveDisabled() {
    return (
      this.loading ||
      this.savingPricebooks ||
      Boolean(this.error) ||
      !this.pricebooks.length
    );
  }

  get pricebookGroups() {
    const groups = [
      {
        key: "assigned",
        label: "Assigned price books",
        rows: this.pricebooks.filter((row) => row.selected)
      },
      {
        key: "available",
        label: "Available active price books",
        rows: this.pricebooks.filter((row) => !row.selected)
      }
    ];
    return groups.filter((group) => group.rows.length);
  }

  get requirementSaveDisabled() {
    return this.loading || this.savingRequirements || Boolean(this.error);
  }

  async loadSetup() {
    const productId = this.productId;
    if (!productId) return;
    this.loading = true;
    this.error = undefined;
    try {
      const data = await getSetup({ productId });
      if (productId !== this.productId) return;
      this.applySetup(data);
    } catch (error) {
      if (productId === this.productId) this.error = messageFrom(error);
    } finally {
      if (productId === this.productId) this.loading = false;
    }
  }

  applySetup(data) {
    this.applyPricing(data);
    this.applyDocuments(data);
  }

  applyPricing(data) {
    this.pricebooks = (data?.pricebooks || []).map((row) => ({
      ...row,
      inputsDisabled: !row.selected
    }));
    this.paymentTypeOptions = (data?.paymentTypes || []).map((value) => ({
      label: value,
      value
    }));
  }

  applyDocuments(data) {
    this.templates = (data?.templates || []).map((row) => ({ ...row }));
    this.requirements = (data?.requirements || []).map((row) => ({
      ...row,
      key: row.id || `new-${this.nextKey++}`,
      templateId: row.templateId || ""
    }));
  }

  handleProductCreated(event) {
    this.createdProductId = event.detail.id;
    this.toast(
      "Product created",
      "Continue with price books, documents, and onboarding fields.",
      "success"
    );
    this.loadSetup();
  }

  handleProductError(event) {
    this.toast(
      "Unable to create product",
      event.detail?.message || "Review the product fields.",
      "error"
    );
  }

  handlePricebookChange(event) {
    const id = event.currentTarget.dataset.id;
    const field = event.currentTarget.dataset.field;
    let value = event.target.checked;
    if (field !== "selected") {
      value = event.detail?.value ?? event.target.value;
      if (field === "unitPrice" || field === "deposit") {
        value = value === "" || value === null ? null : Number(value);
      }
    }
    this.pricebooks = this.pricebooks.map((row) => {
      if (row.pricebookId !== id) return row;
      const changed = { ...row, [field]: value };
      if (field === "selected") changed.inputsDisabled = !value;
      return changed;
    });
  }

  async handleSavePricebooks() {
    if (!this.validate(".pricebook-input")) {
      this.toast(
        "Complete required information",
        "Review the highlighted price book fields before saving.",
        "error"
      );
      return;
    }
    this.savingPricebooks = true;
    const productId = this.productId;
    try {
      const data = await savePricebooks({
        productId,
        rows: this.pricebooks.map((row) => ({
          pricebookId: row.pricebookId,
          selected: row.selected,
          unitPrice: row.unitPrice,
          deposit: row.deposit,
          paymentType: row.paymentType
        }))
      });
      if (productId !== this.productId) return;
      this.applyPricing(data);
      this.toast(
        "Price books saved",
        "Product pricing is ready for quoting.",
        "success"
      );
    } catch (error) {
      this.toast("Unable to save price books", messageFrom(error), "error");
    } finally {
      this.savingPricebooks = false;
    }
  }

  handleAddRequirement(event) {
    this.openDocumentDialog(
      {
        id: null,
        name: "",
        templateId: "",
        shortDescription: "",
        acceptedFormat: "",
        instructions: "",
        active: true
      },
      "Add",
      event.currentTarget
    );
  }

  handleEditRequirement(event) {
    const row = this.requirements.find(
      ({ key }) => key === event.currentTarget.dataset.key
    );
    if (row) this.openDocumentDialog({ ...row }, "Edit", event.currentTarget);
  }

  handleCloneRequirement(event) {
    const row = this.requirements.find(
      ({ key }) => key === event.currentTarget.dataset.key
    );
    if (!row) return;
    this.openDocumentDialog(
      {
        id: null,
        name: row.name,
        templateId: row.templateId,
        shortDescription: row.shortDescription,
        acceptedFormat: row.acceptedFormat,
        instructions: row.instructions,
        active: row.active
      },
      "Clone",
      event.currentTarget
    );
  }

  openDocumentDialog(draft, mode, trigger) {
    this.documentDialogMode = mode;
    this.documentDialogTrigger = trigger;
    this.showInstructionError = false;
    this.documentDraft = draft;
    Promise.resolve().then(() =>
      this.template.querySelector(".document-dialog")?.focus()
    );
  }

  handleCloseDocument() {
    const trigger = this.documentDialogTrigger;
    this.documentDialogTrigger = undefined;
    this.documentDraft = undefined;
    Promise.resolve().then(() => trigger?.focus());
  }

  handleDocumentKeyDown(event) {
    if (event.key === "Escape" && !event.defaultPrevented) {
      event.stopPropagation();
      this.handleCloseDocument();
    }
  }

  handleApplyDocument() {
    const draft = {
      ...this.documentDraft,
      name: this.documentDraft.name?.trim(),
      shortDescription: this.documentDraft.shortDescription?.trim()
    };
    const instructions = (draft.instructions || "")
      .replace(/<[^>]*>/g, "")
      .replace(/&nbsp;|&#0*160;|&#x0*a0;/gi, " ")
      .replace(/[\u200B-\u200D\uFEFF]/g, "")
      .trim();
    this.showInstructionError = !instructions;
    if (!this.validate(".requirement-input") || this.showInstructionError)
      return;
    if (
      !draft.name ||
      !draft.shortDescription ||
      !this.selectedFormats.length
    ) {
      this.toast(
        "Complete required information",
        "Enter a document name and short description, and select at least one accepted format.",
        "error"
      );
      return;
    }
    this.requirements = draft.key
      ? this.requirements.map((row) => (row.key === draft.key ? draft : row))
      : [...this.requirements, { ...draft, key: `new-${this.nextKey++}` }];
    this.handleCloseDocument();
  }

  handleRequirementChange(event) {
    const field = event.currentTarget.dataset.field;
    const value =
      field === "active"
        ? event.target.checked
        : field === "acceptedFormat"
          ? event.detail.value.join(";")
          : (event.detail?.value ?? event.target.value);
    this.documentDraft = { ...this.documentDraft, [field]: value };
    if (field === "instructions") this.showInstructionError = false;
  }

  handleTemplateChange(event) {
    this.showInstructionError = false;
    const templateId = event.detail.value;
    const template = this.templates.find((row) => row.id === templateId);
    this.documentDraft = template
      ? {
          ...this.documentDraft,
          templateId,
          name: template.name,
          shortDescription: template.shortDescription || "",
          acceptedFormat: template.acceptedFormat || "",
          instructions: template.instructions || ""
        }
      : { ...this.documentDraft, templateId: "" };
  }

  handleRemoveRequirement(event) {
    const key = event.currentTarget.dataset.key;
    this.requirements = this.requirements.filter((row) => row.key !== key);
  }

  async handleSaveRequirements() {
    if (this.requirementSaveDisabled || this.documentDraft) return;
    this.savingRequirements = true;
    const productId = this.productId;
    try {
      const data = await saveRequirements({
        productId,
        rows: this.requirements.map((row) => ({
          id: row.id,
          name: row.name,
          templateId: row.templateId || null,
          shortDescription: row.shortDescription,
          acceptedFormat: row.acceptedFormat,
          instructions: row.instructions,
          active: row.active
        }))
      });
      if (productId !== this.productId) return;
      this.applyDocuments(data);
      this.toast(
        "Required documents saved",
        "New Cases for this product will receive this checklist.",
        "success"
      );
    } catch (error) {
      this.toast(
        "Unable to save required documents",
        messageFrom(error),
        "error"
      );
    } finally {
      this.savingRequirements = false;
    }
  }

  validate(selector) {
    return [...this.template.querySelectorAll(selector)].reduce(
      (valid, input) => input.reportValidity() && valid,
      true
    );
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
