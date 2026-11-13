import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import { NavigationMixin } from "lightning/navigation";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getContext from "@salesforce/apex/QuoteBuilderController.getContext";
import setPricebook from "@salesforce/apex/QuoteBuilderController.setPricebook";
import saveQuote from "@salesforce/apex/QuoteBuilderController.saveQuote";
import generatePdf from "@salesforce/apex/QuoteBuilderController.generatePdf";
import renderEmailDraft from "@salesforce/apex/QuoteBuilderController.renderEmailDraft";
import sendQuote from "@salesforce/apex/QuoteBuilderController.sendQuote";
import syncQuoteToOpportunity from "@salesforce/apex/QuoteBuilderController.syncQuoteToOpportunity";

const ALL = "__all__";
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const roundCurrency = (value) =>
  Math.round((value + Number.EPSILON) * 100) / 100;
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
  pdfModalOpen = false;
  pdfLoading = false;
  pdfUrl;
  pdfError;
  sendModalOpen = false;
  sendingQuoteId;
  sendRecipients = [];
  recipientSearch = "";
  recipientMenuOpen = false;
  showCc = false;
  sendCc = "";
  sendSubject = "";
  sendHtmlBody = "";
  selectedEmailTemplateId = "";
  selectedFromAddressId = "";
  emailDraftLoading = false;
  sendInProgress = false;
  pendingNewQuote = false;
  selectedPricebookId;
  editingQuoteId;
  editorTitle = "New quote";
  editorPricebookId;
  editorPricebookName;
  expirationDate;
  notes = "";
  termMonths;
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
      sendDisabled: this.busy,
      lines: (quote.lines || []).map((line) => ({
        ...line,
        hasDeposit: line.depositAmount != null,
        termLabel:
          line.isRecurring && line.termMonths
            ? `Recurring · ${line.termMonths} months`
            : ""
      })),
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
        hasDeposit: Number(item.depositAmount) > 0,
        rowClass: quantities.has(item.pricebookEntryId)
          ? "product product_selected"
          : "product",
        addDisabled: this.pricebookMismatch
      }));
  }

  get catalogEmpty() {
    return this.catalogView.length === 0;
  }

  get cartView() {
    return this.cart.map((line) => {
      const gross = roundCurrency(line.unitPrice * line.quantity);
      const net = roundCurrency(gross * (1 - line.discountPct / 100));
      const overLimit = line.discountPct > this.maxDiscount;
      return {
        ...line,
        gross,
        net,
        effectiveTermMonths: line.termMonths || this.termMonths,
        overLimit,
        needsApproval: overLimit && !this.context?.canOverrideDiscount,
        lineClass: overLimit ? "line line_warn" : "line"
      };
    });
  }

  get hasLines() {
    return this.cart.length > 0;
  }

  get hasRecurringLines() {
    return this.cart.some((line) => line.isRecurring);
  }

  get invalidTerms() {
    const validTerm = (value) =>
      Number.isInteger(Number(value)) &&
      Number(value) >= 1 &&
      Number(value) <= 1200;
    return (
      this.hasRecurringLines &&
      (!validTerm(this.termMonths) ||
        this.cart.some(
          (line) =>
            line.isRecurring &&
            line.termMonths != null &&
            !validTerm(line.termMonths)
        ))
    );
  }

  get invalidPrices() {
    return this.cart.some(
      (line) => !Number.isFinite(line.unitPrice) || line.unitPrice < 0
    );
  }

  get invalidDeposits() {
    return this.cart.some(
      (line) =>
        line.depositAmount != null &&
        (!Number.isFinite(line.depositAmount) || line.depositAmount < 0)
    );
  }

  get pricebookMismatch() {
    return (
      this.editorPricebookId &&
      this.editorPricebookId !== this.context?.pricebookId
    );
  }

  get totals() {
    const lines = this.cartView;
    const subtotal = roundCurrency(
      lines.reduce((sum, line) => sum + line.gross, 0)
    );
    const total = roundCurrency(lines.reduce((sum, line) => sum + line.net, 0));
    return {
      subtotal,
      discount: roundCurrency(subtotal - total),
      total,
      count: lines.length
    };
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

  get saveDisabled() {
    return (
      this.busy ||
      !this.hasLines ||
      this.blockedByApproval ||
      this.invalidTerms ||
      this.invalidPrices ||
      this.invalidDeposits ||
      this.pricebookMismatch
    );
  }

  get emailTemplateOptions() {
    return [
      { label: "Appeals Doctor quote email (default)", value: "" },
      ...(this.context?.emailTemplates || []).map((template) => ({
        label: template.folderName
          ? `${template.folderName} — ${template.name}`
          : template.name,
        value: template.id,
        description: template.subject
      }))
    ];
  }

  get sendActionDisabled() {
    return (
      this.busy ||
      this.emailDraftLoading ||
      this.sendRecipients.length === 0 ||
      !this.sendSubject.trim() ||
      !this.sendHtmlBody.trim()
    );
  }

  get showSendLoading() {
    return this.emailDraftLoading || this.sendInProgress;
  }

  get sendLoadingLabel() {
    return this.sendInProgress ? "Sending quote email…" : "Preparing email…";
  }

  get sendActionLabel() {
    return this.sendInProgress ? "Sending…" : "Send email";
  }

  get recipientPills() {
    return this.sendRecipients.map((recipient) => ({
      ...recipient,
      label: recipient.contactId
        ? `${recipient.name} <${recipient.email}>`
        : recipient.email
    }));
  }

  get recipientEmailsValue() {
    return this.sendRecipients.map((recipient) => recipient.email).join("; ");
  }

  get recipientContactMatches() {
    const term = (this.recipientSearch || "").trim().toLowerCase();
    return (this.context?.recipientContacts || [])
      .filter(
        (contact) =>
          !this.sendRecipients.some(
            (recipient) =>
              recipient.email.toLowerCase() === contact.email.toLowerCase()
          )
      )
      .filter((contact) => {
        if (!term) return true;
        return [contact.name, contact.email, contact.title]
          .filter(Boolean)
          .some((value) => value.toLowerCase().includes(term));
      })
      .slice(0, 8)
      .map((contact) => ({
        ...contact,
        detail: [contact.title, contact.email].filter(Boolean).join(" · ")
      }));
  }

  get showRecipientContactMenu() {
    return this.recipientMenuOpen;
  }

  get hasRecipientContactMatches() {
    return this.recipientContactMatches.length > 0;
  }

  get fromAddressOptions() {
    return [
      { label: "Current user / Salesforce default", value: "" },
      ...(this.context?.fromAddresses || []).map((address) => ({
        label: address.label,
        value: address.id,
        description: address.address
      }))
    ];
  }

  get sendAttachmentName() {
    const quote = this.findQuote(this.sendingQuoteId);
    return `${quote?.quoteNumber || "Quote"}.pdf`;
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
    this.editorPricebookId = quote?.pricebookId || this.context?.pricebookId;
    this.editorPricebookName =
      quote?.pricebookName || this.context?.pricebookName;
    this.expirationDate = quote?.expirationDate || this.defaultExpirationDate();
    this.notes = quote?.notes || "";
    this.termMonths = quote?.termMonths || null;
    this.cart = (quote?.lines || []).map((line) => ({
      key: `line-${++keySequence}`,
      pricebookEntryId: line.pricebookEntryId,
      name: line.name,
      family: line.family,
      listPrice: Number(line.listPrice) || 0,
      unitPrice: Number(line.unitPrice ?? line.listPrice) || 0,
      depositAmount:
        line.depositAmount == null ? null : Number(line.depositAmount),
      isRecurring: Boolean(line.isRecurring),
      termMonths: line.inheritsQuoteTerm ? null : line.termMonths || null,
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
    if (this.pricebookMismatch) return;
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
        unitPrice: Number(item.listPrice) || 0,
        depositAmount:
          item.depositAmount == null ? null : Number(item.depositAmount),
        isRecurring: Boolean(item.isRecurring),
        termMonths: null,
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

  handleUnitPrice(event) {
    const value = event.target.value;
    this.updateLine(event.target.dataset.key, {
      unitPrice: value === "" ? NaN : Number(value)
    });
  }

  handleQuoteTerm(event) {
    this.termMonths =
      event.target.value === "" ? null : Number(event.target.value);
  }

  handleDeposit(event) {
    this.updateLine(event.target.dataset.key, {
      depositAmount:
        event.target.value === "" ? null : Number(event.target.value)
    });
  }

  handleLineTerm(event) {
    this.updateLine(event.target.dataset.key, {
      termMonths: event.target.value === "" ? null : Number(event.target.value)
    });
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
    if (this.busy || event.currentTarget.dataset.disabled === "true") return;
    this.selectedPricebookId = event.currentTarget.dataset.id;
  }

  handleChangePricebook() {
    this.selectedPricebookId = this.context.pricebookId;
    this.choosingPricebook = true;
  }

  handleCancelPricebook() {
    if (this.busy) return;
    this.choosingPricebook = false;
    this.pendingNewQuote = false;
    this.selectedPricebookId = undefined;
  }

  async handleSetPricebook() {
    if (!this.selectedPricebookId || this.busy) return;
    const pricebookId = this.selectedPricebookId;
    const changingOpportunityBook = pricebookId !== this.context?.pricebookId;
    const changingEditorBook =
      this.editorOpen && pricebookId !== this.editorPricebookId;
    const changingBook = changingOpportunityBook || changingEditorBook;
    const needsConfirmation =
      (Boolean(this.context?.pricebookId) && changingOpportunityBook) ||
      changingEditorBook;
    await this.run(async () => {
      if (needsConfirmation) {
        const confirmed = await LightningConfirm.open({
          label: "Change price book",
          message: changingOpportunityBook
            ? "Changing the price book removes the current Opportunity products and the products in this quote draft, and stops any quote synchronization. Saved quotes will remain. Your quote notes, expiration date, and recurring term will be kept. Continue?"
            : "Using the Opportunity's current price book removes the products in this quote draft. Existing Opportunity products and saved quotes will remain. Your quote notes, expiration date, and recurring term will be kept. Continue?",
          theme: "warning"
        });
        if (!confirmed) return;
      }
      this.applyContext(
        await setPricebook({
          opportunityId: this.recordId,
          pricebookId,
          confirmProductRemoval: changingOpportunityBook && needsConfirmation
        })
      );
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      this.choosingPricebook = false;
      this.selectedPricebookId = undefined;
      const shouldOpen = this.pendingNewQuote;
      this.pendingNewQuote = false;
      if (changingBook && this.editorOpen) {
        this.cart = [];
        this.search = "";
        this.family = ALL;
      }
      if (this.editorOpen) {
        this.editorPricebookId = this.context.pricebookId;
        this.editorPricebookName = this.context.pricebookName;
      }
      if (shouldOpen) this.openEditor();
      this.toast("success", "Price book selected", this.context.pricebookName);
    });
  }

  async handleSaveQuote() {
    if (this.saveDisabled) return;
    const inputs = [
      ...this.template.querySelectorAll(
        ".quote-editor input, .quote-editor lightning-input"
      )
    ];
    if (!inputs.every((input) => input.reportValidity?.() !== false)) return;
    await this.run(async () => {
      const lines = this.cart.map((line) => ({
        pricebookEntryId: line.pricebookEntryId,
        quantity: line.quantity,
        discountPct: line.discountPct,
        unitPrice: line.unitPrice,
        depositAmount: line.depositAmount,
        termMonths: line.isRecurring ? line.termMonths : null,
        description: line.description
      }));
      const quote = await saveQuote({
        opportunityId: this.recordId,
        quoteId: this.editingQuoteId,
        expirationDate: this.expirationDate,
        notes: this.notes,
        termMonths: this.hasRecurringLines ? this.termMonths : null,
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
    this.pdfModalOpen = true;
    this.pdfError = undefined;
    if (quote.pdfId) {
      this.pdfUrl = this.pdfPreviewUrl(quote.quoteId);
      return;
    }
    this.pdfLoading = true;
    try {
      await generatePdf({ quoteId: quote.quoteId });
      this.applyContext(await getContext({ opportunityId: this.recordId }));
      this.pdfUrl = this.pdfPreviewUrl(quote.quoteId);
    } catch (error) {
      this.pdfError = this.message(error);
      this.toast("error", "PDF could not be generated", this.pdfError);
    } finally {
      this.pdfLoading = false;
    }
  }

  handleClosePdf() {
    this.pdfModalOpen = false;
    this.pdfLoading = false;
    this.pdfUrl = undefined;
    this.pdfError = undefined;
  }

  async handleSendQuote(event) {
    const quote = this.findQuote(event.currentTarget.dataset.id);
    this.sendingQuoteId = quote.quoteId;
    this.sendRecipients = [];
    this.recipientSearch = "";
    const matchingContact = (this.context?.recipientContacts || []).find(
      (contact) =>
        (contact.email || "").toLowerCase() ===
        (quote.recipientEmail || "").toLowerCase()
    );
    if (quote.recipientEmail) {
      this.addRecipient(
        quote.recipientEmail,
        matchingContact?.name,
        matchingContact?.id
      );
    }
    this.recipientMenuOpen = false;
    this.showCc = false;
    this.sendCc = "";
    this.selectedEmailTemplateId = "";
    this.selectedFromAddressId = "";
    this.sendModalOpen = true;
    await this.loadEmailDraft();
  }

  handleSendEmailChange(event) {
    this.recipientSearch = event.target.value || "";
    this.recipientMenuOpen = true;
    event.target.setCustomValidity?.("");
  }

  handleRecipientKeyDown(event) {
    if (event.key !== "Enter") return;
    event.preventDefault();
    const email = (event.target.value || this.recipientSearch || "").trim();
    if (!EMAIL_PATTERN.test(email)) {
      event.target.setCustomValidity?.("Enter a valid email address.");
      event.target.reportValidity?.();
      return;
    }
    event.target.setCustomValidity?.("");
    this.addRecipient(email);
    this.recipientSearch = "";
    event.target.value = "";
    this.recipientMenuOpen = false;
    Promise.resolve().then(() => {
      const input = this.template.querySelector(".recipient-lookup__input");
      if (input) input.value = "";
    });
  }

  handleRecipientFocus() {
    this.recipientMenuOpen = true;
  }

  handleSelectRecipient(event) {
    const contact = (this.context?.recipientContacts || []).find(
      (item) => item.id === event.currentTarget.dataset.id
    );
    if (!contact) return;
    this.addRecipient(contact.email, contact.name, contact.id);
    this.recipientSearch = "";
    this.recipientMenuOpen = false;
  }

  handleRemoveRecipient(event) {
    const key = event.detail?.name || event.target.name;
    this.sendRecipients = this.sendRecipients.filter(
      (recipient) => recipient.key !== key
    );
    this.recipientMenuOpen = true;
  }

  addRecipient(email, name, contactId) {
    const normalized = email.trim().toLowerCase();
    if (
      this.sendRecipients.some(
        (recipient) => recipient.email.toLowerCase() === normalized
      )
    ) {
      return;
    }
    this.sendRecipients = [
      ...this.sendRecipients,
      {
        key: contactId || normalized,
        email: email.trim(),
        name: name || email.trim(),
        contactId: contactId || null
      }
    ];
  }

  handleSendCcChange(event) {
    this.sendCc = event.target.value || "";
  }

  handleToggleCc() {
    this.showCc = !this.showCc;
    if (!this.showCc) this.sendCc = "";
  }

  async handleEmailTemplateChange(event) {
    this.selectedEmailTemplateId = event.detail.value || "";
    await this.loadEmailDraft();
  }

  handleFromAddressChange(event) {
    this.selectedFromAddressId = event.detail.value || "";
  }

  handleSendSubjectChange(event) {
    this.sendSubject = event.target.value || "";
  }

  handleSendBodyChange(event) {
    this.sendHtmlBody = event.detail?.value || event.target.value || "";
  }

  async loadEmailDraft() {
    this.emailDraftLoading = true;
    try {
      const draft = await renderEmailDraft({
        quoteId: this.sendingQuoteId,
        templateId: this.selectedEmailTemplateId || null,
        recipientEmail: this.sendRecipients[0]?.email || null
      });
      this.sendSubject = draft.subject || "";
      this.sendHtmlBody = draft.htmlBody || "";
    } catch (error) {
      this.toast(
        "error",
        "Email template could not be loaded",
        this.message(error)
      );
    } finally {
      this.emailDraftLoading = false;
    }
  }

  handleCloseSend() {
    if (this.busy) return;
    this.resetSendModal();
  }

  resetSendModal() {
    this.sendModalOpen = false;
    this.sendingQuoteId = undefined;
    this.sendRecipients = [];
    this.recipientSearch = "";
    this.recipientMenuOpen = false;
    this.showCc = false;
    this.sendCc = "";
    this.sendSubject = "";
    this.sendHtmlBody = "";
    this.selectedEmailTemplateId = "";
    this.selectedFromAddressId = "";
    this.emailDraftLoading = false;
  }

  async handleConfirmSend() {
    const quote = this.findQuote(this.sendingQuoteId);
    const recipients = this.recipientEmailsValue;
    this.sendInProgress = true;
    try {
      await this.run(async () => {
        await sendQuote({
          quoteId: quote.quoteId,
          recipientEmail: recipients,
          ccEmails: this.sendCc.trim(),
          templateId: this.selectedEmailTemplateId || null,
          fromAddressId: this.selectedFromAddressId || null,
          subject: this.sendSubject.trim(),
          htmlBody: this.sendHtmlBody
        });
        this.applyContext(await getContext({ opportunityId: this.recordId }));
        this.resetSendModal();
        this.toast(
          "success",
          "Quote sent",
          `Sent to ${recipients} and logged on the Opportunity.`
        );
      });
    } finally {
      this.sendInProgress = false;
    }
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

  pdfPreviewUrl(quoteId) {
    return `/apex/QuoteBuilderPdf?id=${quoteId}`;
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
