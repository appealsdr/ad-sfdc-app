import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
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

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    this._recordId = value;
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
    return this.loading || this.savingPricebooks || !this.pricebooks.length;
  }

  get requirementSaveDisabled() {
    return this.loading || this.savingRequirements;
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
    this.pricebooks = (data?.pricebooks || []).map((row) => ({
      ...row,
      inputsDisabled: !row.selected
    }));
    this.templates = (data?.templates || []).map((row) => ({ ...row }));
    this.requirements = (data?.requirements || []).map((row) => ({
      ...row,
      key: row.id || `new-${this.nextKey++}`,
      templateId: row.templateId || ""
    }));
    this.paymentTypeOptions = (data?.paymentTypes || []).map((value) => ({
      label: value,
      value
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
    if (!this.validate(".pricebook-input")) return;
    this.savingPricebooks = true;
    try {
      const data = await savePricebooks({
        productId: this.productId,
        rows: this.pricebooks.map((row) => ({
          pricebookId: row.pricebookId,
          selected: row.selected,
          unitPrice: row.unitPrice,
          deposit: row.deposit,
          paymentType: row.paymentType
        }))
      });
      this.applySetup(data);
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

  handleAddRequirement() {
    this.requirements = [
      ...this.requirements,
      {
        key: `new-${this.nextKey++}`,
        id: null,
        name: "",
        templateId: "",
        shortDescription: "",
        acceptedFormat: "",
        instructions: "",
        active: true
      }
    ];
  }

  handleRequirementChange(event) {
    const key = event.currentTarget.dataset.key;
    const field = event.currentTarget.dataset.field;
    const value =
      field === "active"
        ? event.target.checked
        : (event.detail?.value ?? event.target.value);
    this.requirements = this.requirements.map((row) =>
      row.key === key ? { ...row, [field]: value } : row
    );
  }

  handleTemplateChange(event) {
    const key = event.currentTarget.dataset.key;
    const templateId = event.detail.value;
    const template = this.templates.find((row) => row.id === templateId);
    this.requirements = this.requirements.map((row) => {
      if (row.key !== key) return row;
      if (!template) return { ...row, templateId: "" };
      return {
        ...row,
        templateId,
        name: template.name,
        shortDescription: template.shortDescription || "",
        acceptedFormat: template.acceptedFormat || "",
        instructions: template.instructions || ""
      };
    });
  }

  handleRemoveRequirement(event) {
    const key = event.currentTarget.dataset.key;
    this.requirements = this.requirements.filter((row) => row.key !== key);
  }

  async handleSaveRequirements() {
    if (!this.validate(".requirement-input")) return;
    this.savingRequirements = true;
    try {
      const data = await saveRequirements({
        productId: this.productId,
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
      this.applySetup(data);
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
