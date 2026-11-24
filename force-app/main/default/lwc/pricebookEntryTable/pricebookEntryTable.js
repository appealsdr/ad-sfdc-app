import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import getEntries from "@salesforce/apex/PricebookEntryTableController.getEntries";
import getAvailableProducts from "@salesforce/apex/PricebookEntryTableController.getAvailableProducts";
import addProducts from "@salesforce/apex/PricebookEntryTableController.addProducts";
import saveEntries from "@salesforce/apex/PricebookEntryTableController.saveEntries";
import deleteEntry from "@salesforce/apex/PricebookEntryTableController.deleteEntry";

export default class PricebookEntryTable extends LightningElement {
  @api recordId;
  _fieldSetName = "";

  @api
  get fieldSetName() {
    return this._fieldSetName;
  }

  set fieldSetName(value) {
    this._fieldSetName = value || "";
  }

  columns = [];
  fields = [];
  rows = [];
  filteredRows = [];
  searchTerm = "";
  warning;
  errorMessage;
  isLoading = true;
  isEditing = false;
  isSaving = false;
  editRows = [];
  paymentTypeOptions = [];
  isAddOpen = false;
  isLoadingProducts = false;
  isAddingProducts = false;
  availableProducts = [];
  selectedProductIds = [];
  canCreateEntries = false;
  canUpdateEntries = false;
  canDeleteEntries = false;
  isDeleting = false;
  wiredResult;

  availableProductColumns = [
    {
      label: "Product",
      fieldName: "productUrl",
      type: "url",
      typeAttributes: {
        label: { fieldName: "productName" },
        target: "_self"
      }
    },
    { label: "Product Code", fieldName: "productCode", type: "text" },
    {
      label: "Standard Price",
      fieldName: "standardPrice",
      type: "currency"
    }
  ];

  @wire(getEntries, { pricebookId: "$recordId", fieldSetName: "$fieldSetName" })
  wiredEntries(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.canCreateEntries = Boolean(data.canCreateEntries);
      this.canUpdateEntries = Boolean(data.canUpdateEntries);
      this.canDeleteEntries = Boolean(data.canDeleteEntries);
      this.fields = data.fields || [];
      this.columns = this.buildColumns(this.fields);
      this.rows = (data.rows || []).map((row) => this.flattenRow(row));
      this.warning = data.rowLimitReached
        ? this.joinMessages(
            data.warning,
            "Only the first 1,000 entries are displayed."
          )
        : data.warning;
      this.paymentTypeOptions = (data.paymentTypes || []).map((value) => ({
        label: value,
        value
      }));
      this.errorMessage = undefined;
      this.applySearch();
      this.isLoading = false;
    } else if (error) {
      this.rows = [];
      this.filteredRows = [];
      this.errorMessage = this.reduceError(error);
      this.isLoading = false;
    }
  }

  get totalCount() {
    return this.rows.length;
  }

  get visibleCount() {
    return this.filteredRows.length;
  }

  get hasRows() {
    return this.filteredRows.length > 0;
  }

  get isLoaded() {
    return !this.isLoading;
  }

  get hasAvailableProducts() {
    return this.availableProducts.length > 0;
  }

  get addProductsDisabled() {
    return this.isAddingProducts || this.selectedProductIds.length === 0;
  }

  get addButtonDisabled() {
    return this.isEditing || !this.canCreateEntries;
  }

  get editButtonDisabled() {
    return this.isLoading || !this.canUpdateEntries;
  }

  buildColumns(fields) {
    const fieldColumns = fields.map((field) =>
      field.apiName === "Product2Id"
        ? {
            label: field.label,
            fieldName: "ProductUrl",
            type: "url",
            sortable: true,
            typeAttributes: {
              label: { fieldName: "Product2Id" },
              target: "_self"
            }
          }
        : {
            label: field.label,
            fieldName: field.apiName,
            type: this.datatableType(field.dataType),
            sortable: true,
            wrapText: field.dataType === "textarea"
          }
    );
    if (this.canDeleteEntries) {
      fieldColumns.push({
        label: "Actions",
        type: "button-icon",
        fixedWidth: 56,
        typeAttributes: {
          iconName: "utility:delete",
          name: "delete",
          title: "Delete",
          alternativeText: "Delete Price Book Entry",
          variant: "border-filled"
        }
      });
    }
    return fieldColumns;
  }

  flattenRow(row) {
    return {
      Id: row.id,
      ProductUrl: row.productId
        ? `/lightning/r/Product2/${row.productId}/view`
        : undefined,
      ...(row.values || {})
    };
  }

  datatableType(dataType) {
    const types = {
      boolean: "boolean",
      currency: "currency",
      date: "date-local",
      datetime: "date",
      double: "number",
      email: "email",
      integer: "number",
      long: "number",
      percent: "percent",
      phone: "phone",
      url: "url"
    };
    return types[dataType] || "text";
  }

  handleSearch(event) {
    this.searchTerm = event.target.value || "";
    this.applySearch();
  }

  applySearch() {
    const term = this.searchTerm.trim().toLowerCase();
    if (!term) {
      this.filteredRows = [...this.rows];
      return;
    }
    const fieldNames = this.fields.map((field) => field.apiName);
    this.filteredRows = this.rows.filter((row) =>
      fieldNames.some((fieldName) =>
        String(row[fieldName] ?? "")
          .toLowerCase()
          .includes(term)
      )
    );
  }

  handleEdit() {
    if (!this.canUpdateEntries) {
      this.toast(
        "Insufficient access",
        "You do not have permission to modify Price Book Entries.",
        "error"
      );
      return;
    }
    this.searchTerm = "";
    this.applySearch();
    this.editRows = this.rows.map((row) => ({
      ...row,
      depositRequired: row.Payment_type__c === "Deposit"
    }));
    this.isEditing = true;
  }

  handleCancelEdit() {
    this.isEditing = false;
    this.editRows = [];
  }

  handleEditChange(event) {
    const id = event.currentTarget.dataset.id;
    const field = event.currentTarget.dataset.field;
    let value =
      field === "IsActive"
        ? event.target.checked
        : (event.detail?.value ?? event.target.value);
    if (field === "UnitPrice" || field === "Deposit__c") {
      value = value === "" || value === null ? null : Number(value);
    }
    this.editRows = this.editRows.map((row) => {
      if (row.Id !== id) return row;
      const changed = { ...row, [field]: value };
      changed.depositRequired = changed.Payment_type__c === "Deposit";
      return changed;
    });
  }

  async handleSaveEntries() {
    if (!this.validateEditRows()) {
      this.toast(
        "Complete required information",
        "Review the highlighted Price Book Entry fields before saving.",
        "error"
      );
      return;
    }
    this.isSaving = true;
    try {
      await saveEntries({
        pricebookId: this.recordId,
        updates: this.editRows.map((row) => ({
          entryId: row.Id,
          unitPrice: row.UnitPrice,
          active: row.IsActive,
          deposit: row.Deposit__c,
          paymentType: row.Payment_type__c || null
        }))
      });
      await refreshApex(this.wiredResult);
      this.isEditing = false;
      this.editRows = [];
      this.toast(
        "Price Book Entries updated",
        "The pricing table was saved successfully.",
        "success"
      );
    } catch (error) {
      this.toast(
        "Unable to update Price Book Entries",
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  async handleOpenAddProducts() {
    if (!this.canCreateEntries) {
      this.toast(
        "Insufficient access",
        "You do not have permission to add Price Book Entries.",
        "error"
      );
      return;
    }
    this.isAddOpen = true;
    this.isLoadingProducts = true;
    this.availableProducts = [];
    this.selectedProductIds = [];
    try {
      const products = await getAvailableProducts({
        pricebookId: this.recordId
      });
      this.availableProducts = products.map((product) => ({
        ...product,
        productUrl: `/lightning/r/Product2/${product.productId}/view`
      }));
    } catch (error) {
      this.toast("Unable to load Products", this.reduceError(error), "error");
      this.isAddOpen = false;
    } finally {
      this.isLoadingProducts = false;
    }
  }

  handleCloseAddProducts() {
    this.isAddOpen = false;
    this.availableProducts = [];
    this.selectedProductIds = [];
  }

  handleProductSelection(event) {
    this.selectedProductIds = event.detail.selectedRows.map(
      (row) => row.productId
    );
  }

  async handleAddProducts() {
    this.isAddingProducts = true;
    try {
      await addProducts({
        pricebookId: this.recordId,
        productIds: this.selectedProductIds
      });
      const addedCount = this.selectedProductIds.length;
      await refreshApex(this.wiredResult);
      this.handleCloseAddProducts();
      this.toast(
        "Products added",
        `${addedCount} Product${addedCount === 1 ? "" : "s"} added to this Price Book.`,
        "success"
      );
    } catch (error) {
      this.toast("Unable to add Products", this.reduceError(error), "error");
    } finally {
      this.isAddingProducts = false;
    }
  }

  async handleRowAction(event) {
    if (event.detail.action.name !== "delete" || this.isDeleting) {
      return;
    }
    if (!this.canDeleteEntries) {
      this.toast(
        "Insufficient access",
        "You do not have permission to delete Price Book Entries.",
        "error"
      );
      return;
    }
    const row = event.detail.row;
    const confirmed = await LightningConfirm.open({
      label: "Delete Price Book Entry",
      message: `Delete ${row.Product2Id} from this Price Book?`,
      theme: "warning"
    });
    if (!confirmed) {
      return;
    }
    this.isDeleting = true;
    try {
      await deleteEntry({
        pricebookId: this.recordId,
        entryId: row.Id
      });
      await refreshApex(this.wiredResult);
      this.toast(
        "Price Book Entry deleted",
        `${row.Product2Id} was removed from this Price Book.`,
        "success"
      );
    } catch (error) {
      this.toast(
        "Unable to delete Price Book Entry",
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isDeleting = false;
    }
  }

  validateEditRows() {
    return [...this.template.querySelectorAll(".edit-input")].reduce(
      (valid, input) => input.reportValidity() && valid,
      true
    );
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  joinMessages(first, second) {
    return first ? `${first} ${second}` : second;
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((item) => item.message).join(", ");
    }
    return (
      error?.body?.message ||
      error?.message ||
      "Unable to load Price Book Entries."
    );
  }
}
