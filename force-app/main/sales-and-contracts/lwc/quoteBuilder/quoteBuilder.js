import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import { NavigationMixin } from "lightning/navigation";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getContext from "@salesforce/apex/QuoteBuilderController.getContext";
import setPricebook from "@salesforce/apex/QuoteBuilderController.setPricebook";
import saveQuote from "@salesforce/apex/QuoteBuilderController.saveQuote";
import generatePdf from "@salesforce/apex/QuoteBuilderController.generatePdf";
import sendQuote from "@salesforce/apex/QuoteBuilderController.sendQuote";
import syncQuoteToOpportunity from "@salesforce/apex/QuoteBuilderController.syncQuoteToOpportunity";

const ALL = "__all__";
let keySequence = 0;

export default class QuoteBuilder extends NavigationMixin(LightningElement) {
  @api recordId;
  @api cardTitle = "Quotes";
  // Retained because Salesforce blocks removing a design property while the component is in use.
  @api quoteTemplateId;

  context;
  loading = true;
  busy = false;
  error;
  editorOpen = false;
  choosingPricebook = false;
  pendingNewQuote = false;
  selectedPricebookId;
  editingQuoteId;
  editorTitle = "New quote";
  expirationDate;
  notes = "";
  cart = [];
  search = "";
  family = ALL;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.applyContext(await getContext({ opportunityId: this.recordId }));
    } catch (error) {
      this.error = this.message(error);
    } finally {
      this.loading = false;
    }
  }

  applyContext(context) {
    this.context = context;
    this.error = undefined;
  }

  get hasQuotes() {
    return (this.context?.quotes || []).length > 0;
  }

  get quoteCards() {
    return (this.context?.quotes || []).map((quote, index) => ({
      ...quote,
      sequence: (this.context.quotes || []).length - index,
      lineCount: (quote.lines || []).length,
      hasLines: (quote.lines || []).length > 0,
      pdfLabel: quote.pdfId ? "View PDF" : "Generate PDF",
      syncLabel: quote.isSynced
        ? "Synced to Opportunity"
        : "Sync to Opportunity",
      syncDisabled: this.busy || quote.isSynced,
      sendDisabled: this.busy || !quote.recipientEmail,
      statusClass: `status status_${(quote.status || "draft").toLowerCase().replaceAll(" ", "-")}`
    }));
  }

  get quoteCountLabel() {
    const count = (this.context?.quotes || []).length;
    return `${count} quote${count === 1 ? "" : "s"}`;
  }

  get pricebookCards() {
    return (this.context?.pricebooks || []).map((pricebook) => {
      const selected = pricebook.id === this.selectedPricebookId;
      return {
        ...pricebook,
        selected,
        disabled: !pricebook.productCount,
        ariaChecked: selected ? "true" : "false",
        className: `pb${selected ? " pb_selected" : ""}${!pricebook.productCount ? " pb_empty" : ""}`,
        countLabel: `${pricebook.productCount || 0} product${pricebook.productCount === 1 ? "" : "s"}`,
        descriptionLabel: pricebook.description || "No description"
      };
    });
  }

  get pickDisabled() {
    return this.busy || !this.selectedPricebookId;
  }

  get familyPills() {
    const families = new Set();
    (this.context?.catalog || []).forEach((item) =>
      families.add(item.family || "Other")
    );
    return [
      { value: ALL, label: "All" },
      ...[...families].map((value) => ({ value, label: value }))
    ].map((pill) => ({
      ...pill,
      className: pill.value === this.family ? "pill pill_active" : "pill",
      pressed: pill.value === this.family ? "true" : "false"
    }));
  }

  get catalogView() {
    const term = this.search.trim().toLowerCase();
    const quantities = new Map(
      this.cart.map((line) => [line.pricebookEntryId, line.quantity])
    );
    return (this.context?.catalog || [])
      .filter(
        (item) =>
          this.family === ALL || (item.family || "Other") === this.family
      )
      .filter(
        (item) =>
          !term ||
          (item.name || "").toLowerCase().includes(term) ||
          (item.code || "").toLowerCase().includes(term) ||
          (item.description || "").toLowerCase().includes(term)
      )
      .map((item) => ({
        ...item,
        familyLabel: item.family || "Other",
        rowClass: quantities.has(item.pricebookEntryId)
          ? "product product_selected"
          : "product"
      }));
  }

  get catalogEmpty() {
    return this.catalogView.length === 0;
  }

  get cartView() {
    return this.cart.map((line) => {
      const gross = line.listPrice * line.quantity;
      const net = gross * (1 - line.discountPct / 100);
      const overLimit = line.discountPct > this.maxDiscount;
      return {
        ...line,
        gross,
        net,
        overLimit,
        needsApproval: overLimit && !this.context?.canOverrideDiscount,
        lineClass: overLimit ? "line line_warn" : "line"
      };
    });
  }

  get hasLines() {
    return this.cart.length > 0;
  }

  get totals() {
    const lines = this.cartView;
    const subtotal = lines.reduce((sum, line) => sum + line.gross, 0);
    const total = lines.reduce((sum, line) => sum + line.net, 0);
    return { subtotal, discount: subtotal - total, total, count: lines.length };
  }

  get maxDiscount() {
    return Number(this.context?.maxDiscount) || 0;
  }

  get blockedByApproval() {
    return this.cartView.some((line) => line.needsApproval);
  }

  get hasCartLines() {
    return this.cart.length > 0;
  }

  get totals() {
    const lines = this.cartView;
    const subtotal = lines.reduce((sum, line) => sum + line.gross, 0);
    const total = lines.reduce((sum, line) => sum + line.net, 0);
    return { subtotal, discount: subtotal - total, total };
  }

  get saveDisabled() {
    return this.busy || !this.hasLines || this.blockedByApproval;
  }

  handleNewQuote() {
    if (!this.context?.pricebookId) {
      this.pendingNewQuote = true;
      this.choosingPricebook = true;
      return;
    }
    this.openEditor();
  }

  handleEditQuote(event) {
    const quote = this.findQuote(event.currentTarget.dataset.id);
    this.openEditor(quote);
  }

  openEditor(quote) {
    this.editingQuoteId = quote?.quoteId;
    this.editorTitle = quote ? `Edit ${quote.name}` : "New quote";
    this.expirationDate = quote?.expirationDate || this.defaultExpirationDate();
    this.notes = quote?.notes || "";
    this.cart = (quote?.lines || []).map((line) => ({
      key: `line-${++keySequence}`,
      pricebookEntryId: line.pricebookEntryId,
      name: line.name,
      family: line.family,
      listPrice: Number(line.listPrice) || 0,
      quantity: Number(line.quantity) || 1,
      discountPct: Number(line.discountPct) || 0,
      description: line.description || ""
    }));
    this.search = "";
    this.family = ALL;
    this.editorOpen = true;
  }

  handleCancelEditor() {
    this.editorOpen = false;
    this.editingQuoteId = undefined;
    this.cart = [];
  }

  handleSearch(event) {
    this.search = event.target.value || "";
  }

  handleFamily(event) {
    this.family = event.currentTarget.dataset.family;
  }

  handleAdd(event) {
    const id = event.currentTarget.dataset.id;
    const existing = this.cart.find((line) => line.pricebookEntryId === id);
    if (existing) {
      this.cart = this.cart.map((line) =>
        line === existing ? { ...line, quantity: line.quantity + 1 } : line
      );
      return;
    }
    const item = this.context.catalog.find(
      (catalogItem) => catalogItem.pricebookEntryId === id
    );
    this.cart = [
      ...this.cart,
      {
        key: `line-${++keySequence}`,
        pricebookEntryId: item.pricebookEntryId,
        name: item.name,
        family: item.family,
        listPrice: Number(item.listPrice) || 0,
        quantity: 1,
        discountPct: 0,
        description: ""
      }
    ];
  }

  updateLine(key, patch) {
    this.cart = this.cart.map((line) =>
      line.key === key ? { ...line, ...patch } : line
    );
  }

  handleQty(event) {
    const quantity = Math.max(
      1,
      Math.min(9999, Math.round(Number(event.target.value) || 1))
    );
    this.updateLine(event.target.dataset.key, { quantity });
  }

  handleStep(event) {
    const { key, step } = event.currentTarget.dataset;
    const line = this.cart.find((item) => item.key === key);
    this.updateLine(key, {
      quantity: Math.max(1, line.quantity + Number(step))
    });
  }

  handleDiscount(event) {
    const discountPct = Math.max(
      0,
      Math.min(100, Number(event.target.value) || 0)
    );
    this.updateLine(event.target.dataset.key, { discountPct });
  }

  handleNote(event) {
    this.updateLine(event.target.dataset.key, {
      description: event.target.value || ""
    });
  }

  handleRemove(event) {
    const key = event.currentTarget.dataset.key;
    this.cart = this.cart.filter((line) => line.key !== key);
  }

  handleExpiration(event) {
    this.expirationDate = event.target.value;
  }

  handleNotes(event) {
    this.notes = event.target.value || "";
  }

  handlePricebookPick(event) {
    if (event.currentTarget.dataset.disabled === "true") return;
    this.selectedPricebookId = event.currentTarget.dataset.id;
  }

  handleCancelPricebook() {
    this.choosingPricebook = false;
    this.pendingNewQuote = false;
    this.selectedPricebookId = undefined;
  }

  async handleSetPricebook() {
    if (!this.selectedPricebookId) return;
    await this.run(async () => {
      this.applyContext(
        await setPricebook({
          opportunityId: this.recordId,
          pricebookId: this.selectedPricebookId
        })
      );
      this.choosingPricebook = false;
      this.selectedPricebookId = undefined;
      const shouldOpen = this.pendingNewQuote;
      this.pendingNewQuote = false;
      if (shouldOpen) this.openEditor();
      this.toast("success", "Price book selected", this.context.pricebookName);
    });
  }

  async handleSaveQuote() {
    await this.run(async () => {
      const lines = this.cart.map((line) => ({
        pricebookEntryId: line.pricebookEntryId,
        quantity: line.quantity,
        discountPct: line.discountPct,
        description: line.description
      }));
      const quote = await saveQuote({
        opportunityId: this.recordId,
        quoteId: this.editingQuoteId,
        expirationDate: this.expirationDate,
        notes: this.notes,
        lines
      });
      this.applyContext(await getContext({ opportunityId: this.recordId }));
      this.handleCancelEditor();
      this.toast(
        "success",
        "Quote saved",
        `${quote.name} now has ${lines.length} product(s).`
      );
    });
  }

  async handleViewPdf(event) {
    const quote = this.findQuote(event.currentTarget.dataset.id);
    if (quote.pdfId) {
      this.openPdf(quote.pdfId);
      return;
    }
    await this.run(async () => {
      const pdfId = await generatePdf({ quoteId: quote.quoteId });
      this.applyContext(await getContext({ opportunityId: this.recordId }));
      this.openPdf(pdfId);
    });
  }

  async handleSendQuote(event) {
    const quote = this.findQuote(event.currentTarget.dataset.id);
    const confirmed = await LightningConfirm.open({
      label: "Send quote",
      message: `Send ${quote.name} as a PDF to ${quote.recipientEmail}?`,
      theme: "info"
    });
    if (!confirmed) return;
    await this.run(async () => {
      await sendQuote({ quoteId: quote.quoteId });
      this.applyContext(await getContext({ opportunityId: this.recordId }));
      this.toast("success", "Quote sent", `Sent to ${quote.recipientEmail}.`);
    });
  }

  async handleSyncQuote(event) {
    const quote = this.findQuote(event.currentTarget.dataset.id);
    const confirmed = await LightningConfirm.open({
      label: "Sync to Opportunity",
      message: `Replace the Opportunity products with the products from ${quote.name}?`,
      theme: "warning"
    });
    if (!confirmed) return;
    await this.run(async () => {
      this.applyContext(
        await syncQuoteToOpportunity({
          opportunityId: this.recordId,
          quoteId: quote.quoteId
        })
      );
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      this.toast(
        "success",
        "Quote synced",
        "Opportunity products and amount now match this quote."
      );
    });
  }

  handleOpenQuote(event) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        objectApiName: "Quote",
        actionName: "view"
      }
    });
  }

  openPdf(pdfId) {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: `/servlet/servlet.FileDownload?file=${pdfId}` }
    });
  }

  findQuote(quoteId) {
    return (this.context?.quotes || []).find(
      (quote) => quote.quoteId === quoteId
    );
  }

  defaultExpirationDate() {
    return new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10);
  }

  async run(callback) {
    this.busy = true;
    try {
      await callback();
    } catch (error) {
      this.toast("error", "Something went wrong", this.message(error));
    } finally {
      this.busy = false;
    }
  }

  toast(variant, title, message) {
    this.dispatchEvent(new ShowToastEvent({ variant, title, message }));
  }

  message(error) {
    if (Array.isArray(error?.body))
      return error.body.map((item) => item.message).join(", ");
    return error?.body?.message || error?.message || "Unknown error";
  }
}
