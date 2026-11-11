import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getContext from "@salesforce/apex/QuoteBuilderController.getContext";
import setPricebook from "@salesforce/apex/QuoteBuilderController.setPricebook";
import saveLines from "@salesforce/apex/QuoteBuilderController.saveLines";
import createQuote from "@salesforce/apex/QuoteBuilderController.createQuote";
import generatePdf from "@salesforce/apex/QuoteBuilderController.generatePdf";

const ALL = "__all__";
const VALIDITY_OPTIONS = [
  { label: "7 days", value: "7" },
  { label: "14 days", value: "14" },
  { label: "30 days", value: "30" }
];

let keySeq = 0;

export default class QuoteBuilder extends NavigationMixin(LightningElement) {
  @api recordId;
  /** Quote Template Id (Setup → Quote Templates). Blank = create the Quote without a PDF. */
  @api quoteTemplateId;
  @api cardTitle = "Quote builder";

  context;
  cart = [];
  search = "";
  family = ALL;
  validDays = "14";
  notes = "";
  selectedPricebookId;
  choosingPricebook = false;
  loading = true;
  busy = false;
  dirty = false;
  error;
  validityOptions = VALIDITY_OPTIONS;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.applyContext(await getContext({ opportunityId: this.recordId }));
    } catch (e) {
      this.error = this.message(e);
    } finally {
      this.loading = false;
    }
  }

  applyContext(ctx) {
    this.context = ctx;
    this.error = undefined;
    this.dirty = false;
    this.cart = (ctx.lines || []).map((l) => ({
      key: `k${++keySeq}`,
      pricebookEntryId: l.pricebookEntryId,
      name: l.name,
      family: l.family,
      listPrice: Number(l.listPrice) || 0,
      quantity: Number(l.quantity) || 1,
      discountPct: Number(l.discountPct) || 0,
      description: l.description || ""
    }));
  }

  // ------------------------------------------------------------ view state

  get hasPricebook() {
    return !!this.context?.pricebookId;
  }

  get needsPricebook() {
    return !!this.context && !this.context.pricebookId;
  }

  /** Price book screen: shown when none is set, or when the user asked to change it. */
  get showPricebookPicker() {
    return this.needsPricebook || this.choosingPricebook;
  }

  /** Salesforce only allows a switch while the Opportunity has no saved products. */
  get canChangePricebook() {
    return (
      this.hasPricebook &&
      (this.context.lines || []).length === 0 &&
      this.cart.length === 0
    );
  }

  get pricebookCards() {
    const picked = this.selectedPricebookId;
    return (this.context?.pricebooks || []).map((p) => {
      const selected = p.id === picked;
      const empty = !p.productCount;
      return {
        ...p,
        selected,
        ariaChecked: selected ? "true" : "false",
        disabled: empty,
        countLabel: empty
          ? "No active products"
          : `${p.productCount} product${p.productCount === 1 ? "" : "s"}`,
        descriptionLabel: p.description || "No description",
        className: [
          "pb",
          selected ? "pb_selected" : "",
          empty ? "pb_empty" : ""
        ]
          .join(" ")
          .trim()
      };
    });
  }

  get pricebookEmpty() {
    return (this.context?.pricebooks || []).length === 0;
  }

  get pickerTitle() {
    return this.needsPricebook ? "Choose a price book" : "Change price book";
  }

  get pickDisabled() {
    return (
      this.busy ||
      !this.selectedPricebookId ||
      this.selectedPricebookId === this.context?.pricebookId
    );
  }

  get maxDiscount() {
    return Number(this.context?.maxDiscount) || 0;
  }

  get familyPills() {
    const families = new Set();
    (this.context?.catalog || []).forEach((c) =>
      families.add(c.family || "Other")
    );
    const pills = [
      { value: ALL, label: "All" },
      ...[...families].map((f) => ({ value: f, label: f }))
    ];
    return pills.map((p) => ({
      ...p,
      className: p.value === this.family ? "pill pill_active" : "pill",
      pressed: p.value === this.family ? "true" : "false"
    }));
  }

  get catalogView() {
    const term = this.search.trim().toLowerCase();
    const qtyByEntry = new Map(
      this.cart.map((l) => [l.pricebookEntryId, l.quantity])
    );
    return (this.context?.catalog || [])
      .filter(
        (c) => this.family === ALL || (c.family || "Other") === this.family
      )
      .filter(
        (c) =>
          !term ||
          (c.name || "").toLowerCase().includes(term) ||
          (c.code || "").toLowerCase().includes(term) ||
          (c.description || "").toLowerCase().includes(term)
      )
      .map((c) => {
        const inCart = qtyByEntry.get(c.pricebookEntryId);
        return {
          ...c,
          familyLabel: c.family || "Other",
          inCart: !!inCart,
          addLabel: inCart
            ? `Add another (${inCart} in quote)`
            : "Add to quote",
          rowClass: inCart ? "product product_selected" : "product"
        };
      });
  }

  get catalogEmpty() {
    return this.catalogView.length === 0;
  }

  get cartView() {
    return this.cart.map((l) => {
      const gross = l.listPrice * l.quantity;
      const net = gross * (1 - l.discountPct / 100);
      const overLimit = l.discountPct > this.maxDiscount;
      return {
        ...l,
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
    const view = this.cartView;
    const subtotal = view.reduce((s, l) => s + l.gross, 0);
    const total = view.reduce((s, l) => s + l.net, 0);
    return { subtotal, discount: subtotal - total, total, count: view.length };
  }

  get blockedByApproval() {
    return this.cartView.some((l) => l.needsApproval);
  }

  get saveDisabled() {
    return this.busy || !this.dirty || this.blockedByApproval;
  }

  get quoteDisabled() {
    return this.busy || this.dirty || !this.hasLines || this.blockedByApproval;
  }

  get quoteHint() {
    if (!this.hasLines) return "Add products to build a quote.";
    if (this.blockedByApproval)
      return `Discounts above ${this.maxDiscount}% need manager approval.`;
    if (this.dirty) return "Save the lines before creating the quote.";
    return this.quoteTemplateId
      ? "Creates the Quote and its PDF."
      : "Creates the Quote (no PDF template set on this component).";
  }

  get latestQuote() {
    return this.context?.latestQuote;
  }

  // ------------------------------------------------------------ catalogue

  handleSearch(event) {
    this.search = event.target.value || "";
  }

  handleFamily(event) {
    this.family = event.currentTarget.dataset.family;
  }

  handleAdd(event) {
    const id = event.currentTarget.dataset.id;
    const existing = this.cart.find((l) => l.pricebookEntryId === id);
    if (existing) {
      this.cart = this.cart.map((l) =>
        l === existing ? { ...l, quantity: l.quantity + 1 } : l
      );
    } else {
      const c = this.context.catalog.find((x) => x.pricebookEntryId === id);
      this.cart = [
        ...this.cart,
        {
          key: `k${++keySeq}`,
          pricebookEntryId: c.pricebookEntryId,
          name: c.name,
          family: c.family,
          listPrice: Number(c.listPrice) || 0,
          quantity: 1,
          discountPct: 0,
          description: ""
        }
      ];
    }
    this.dirty = true;
  }

  // ------------------------------------------------------------ lines

  updateLine(key, patch) {
    this.cart = this.cart.map((l) => (l.key === key ? { ...l, ...patch } : l));
    this.dirty = true;
  }

  handleQty(event) {
    const value = Math.max(
      1,
      Math.min(9999, Math.round(Number(event.target.value) || 1))
    );
    this.updateLine(event.target.dataset.key, { quantity: value });
  }

  handleStep(event) {
    const { key, step } = event.currentTarget.dataset;
    const line = this.cart.find((l) => l.key === key);
    this.updateLine(key, {
      quantity: Math.max(1, line.quantity + Number(step))
    });
  }

  handleDiscount(event) {
    const value = Math.max(0, Math.min(100, Number(event.target.value) || 0));
    this.updateLine(event.target.dataset.key, { discountPct: value });
  }

  handleNote(event) {
    this.updateLine(event.target.dataset.key, {
      description: event.target.value || ""
    });
  }

  handleRemove(event) {
    const key = event.currentTarget.dataset.key;
    this.cart = this.cart.filter((l) => l.key !== key);
    this.dirty = true;
  }

  handleReset() {
    this.applyContext(this.context);
  }

  // ------------------------------------------------------------ quote options

  handleValidity(event) {
    this.validDays = event.detail.value;
  }

  handleNotes(event) {
    this.notes = event.target.value || "";
  }

  handlePricebookPick(event) {
    const card = event.currentTarget;
    if (card.dataset.disabled === "true") return;
    this.selectedPricebookId = card.dataset.id;
  }

  handleChangePricebook() {
    this.selectedPricebookId = this.context?.pricebookId;
    this.choosingPricebook = true;
  }

  handleCancelPricebook() {
    this.choosingPricebook = false;
    this.selectedPricebookId = undefined;
  }

  // ------------------------------------------------------------ server calls

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
      this.family = ALL;
      this.search = "";
      this.toast(
        "success",
        "Price book set",
        `Products now come from ${this.context.pricebookName}.`
      );
    });
  }

  async handleSave() {
    await this.run(async () => {
      const lines = this.cart.map((l) => ({
        pricebookEntryId: l.pricebookEntryId,
        quantity: l.quantity,
        discountPct: l.discountPct,
        description: l.description
      }));
      this.applyContext(
        await saveLines({ opportunityId: this.recordId, lines })
      );
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      this.toast(
        "success",
        "Products saved",
        `${lines.length} line(s) saved to the Opportunity.`
      );
    });
  }

  async handleCreateQuote() {
    await this.run(async () => {
      const info = await createQuote({
        opportunityId: this.recordId,
        validDays: Number(this.validDays),
        notes: this.notes
      });
      let pdfMessage = "";
      if (this.quoteTemplateId) {
        try {
          await generatePdf({
            quoteId: info.quoteId,
            templateId: this.quoteTemplateId
          });
          pdfMessage = " PDF attached.";
        } catch (e) {
          pdfMessage = ` PDF failed: ${this.message(e)}`;
        }
      }
      this.applyContext(await getContext({ opportunityId: this.recordId }));
      this.notes = "";
      this.toast(
        "success",
        `${info.name} created`,
        `Quote ${info.quoteNumber}.${pdfMessage}`
      );
    });
  }

  handleOpenQuote() {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: this.latestQuote.quoteId,
        objectApiName: "Quote",
        actionName: "view"
      }
    });
  }

  async run(fn) {
    this.busy = true;
    try {
      await fn();
    } catch (e) {
      this.toast("error", "Something went wrong", this.message(e));
    } finally {
      this.busy = false;
    }
  }

  toast(variant, title, message) {
    this.dispatchEvent(new ShowToastEvent({ variant, title, message }));
  }

  message(e) {
    if (Array.isArray(e?.body)) return e.body.map((b) => b.message).join(", ");
    return e?.body?.message || e?.message || "Unknown error";
  }
}
