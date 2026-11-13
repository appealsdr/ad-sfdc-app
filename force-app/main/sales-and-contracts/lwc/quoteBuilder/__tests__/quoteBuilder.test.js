import { createElement } from "lwc";
import QuoteBuilder from "c/quoteBuilder";
import LightningConfirm from "lightning/confirm";
import getContext from "@salesforce/apex/QuoteBuilderController.getContext";
import setPricebook from "@salesforce/apex/QuoteBuilderController.setPricebook";
import saveQuote from "@salesforce/apex/QuoteBuilderController.saveQuote";
import generatePdf from "@salesforce/apex/QuoteBuilderController.generatePdf";
import renderEmailDraft from "@salesforce/apex/QuoteBuilderController.renderEmailDraft";
import sendQuote from "@salesforce/apex/QuoteBuilderController.sendQuote";
import syncQuoteToOpportunity from "@salesforce/apex/QuoteBuilderController.syncQuoteToOpportunity";

jest.mock("lightning/confirm", () => ({ open: jest.fn() }), { virtual: true });
jest.mock(
  "@salesforce/apex/QuoteBuilderController.getContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuoteBuilderController.setPricebook",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuoteBuilderController.saveQuote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuoteBuilderController.generatePdf",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuoteBuilderController.renderEmailDraft",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuoteBuilderController.sendQuote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuoteBuilderController.syncQuoteToOpportunity",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const OPPORTUNITY_ID = "006000000000001AAA";
const QUOTE_ID = "0Q0000000000001AAA";
const ENTRY_ID = "01u000000000001AAA";
const PRICEBOOK_ID = "01s000000000001AAA";
const OTHER_PRICEBOOK_ID = "01s000000000002AAA";
const PDF_ID = "0QD000000000001AAA";
const TEMPLATE_ID = "00X000000000001AAA";
const FROM_ADDRESS_ID = "0D2000000000001AAA";

const quoteLine = {
  lineId: "0QL000000000001AAA",
  pricebookEntryId: ENTRY_ID,
  name: "Listing reinstatement",
  family: "Appeals",
  listPrice: 500,
  quantity: 2,
  discountPct: 10,
  description: "ASIN B0TEST",
  totalPrice: 900
};

const quote = (overrides = {}) => ({
  quoteId: QUOTE_ID,
  name: "Acme appeal – Proposal v1",
  quoteNumber: "00000001",
  status: "Draft",
  expirationDate: "2026-11-25",
  totalPrice: 900,
  notes: "Initial proposal",
  pricebookId: PRICEBOOK_ID,
  pricebookName: "Services",
  recipientEmail: "buyer@example.com",
  createdDate: "2026-11-11T12:00:00.000Z",
  lastModifiedDate: "2026-11-11T12:00:00.000Z",
  pdfId: null,
  isSynced: false,
  lines: [quoteLine],
  ...overrides
});

const context = (overrides = {}) => ({
  opportunityId: OPPORTUNITY_ID,
  opportunityName: "Acme appeal",
  accountName: "Acme",
  stageName: "Meeting Booked",
  pricebookId: PRICEBOOK_ID,
  pricebookName: "Services",
  syncedQuoteId: null,
  maxDiscount: 15,
  canOverrideDiscount: false,
  catalog: [
    {
      pricebookEntryId: ENTRY_ID,
      productId: "01t000000000001AAA",
      name: "Listing reinstatement",
      code: "LISTING",
      family: "Appeals",
      description: "Reinstate a listing",
      listPrice: 500
    }
  ],
  quotes: [quote()],
  pricebooks: [
    {
      id: PRICEBOOK_ID,
      name: "Services",
      description: "Core services",
      productCount: 1,
      isCurrent: true
    }
  ],
  emailTemplates: [
    {
      id: TEMPLATE_ID,
      name: "Quote delivery",
      subject: "Your Appeals Doctor quote",
      folderName: "Sales"
    }
  ],
  fromAddresses: [
    {
      id: FROM_ADDRESS_ID,
      label: "Appeals Doctor <quotes@example.com>",
      address: "quotes@example.com"
    }
  ],
  recipientContacts: [
    {
      id: "003000000000001AAA",
      name: "Account Buyer",
      email: "account.buyer@example.com",
      title: "Head of Operations"
    }
  ],
  ...overrides
});

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(initialContext = context()) {
  getContext.mockResolvedValue(initialContext);
  renderEmailDraft.mockResolvedValue({
    subject: "Your Appeals Doctor quote",
    htmlBody: "<p>Please review your quote.</p>"
  });
  const element = createElement("c-quote-builder", { is: QuoteBuilder });
  element.recordId = OPPORTUNITY_ID;
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const buttonByText = (element, label) =>
  [...element.shadowRoot.querySelectorAll("button")].find(
    (button) => button.textContent.trim() === label
  );

describe("c-quote-builder quote-first workspace", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("shows a quote timeline with products and actions", async () => {
    const element = await render();

    expect(element.shadowRoot.textContent).toContain("1 quote");
    expect(element.shadowRoot.textContent).toContain(
      "Acme appeal – Proposal v1"
    );
    expect(element.shadowRoot.textContent).toContain("Listing reinstatement");
    expect(buttonByText(element, "Generate PDF")).toBeTruthy();
    expect(buttonByText(element, "Send quote")).toBeTruthy();
    expect(buttonByText(element, "Sync to Opportunity")).toBeTruthy();
  });

  it("creates a quote directly from products in the editor", async () => {
    saveQuote.mockResolvedValue(quote());
    getContext.mockResolvedValue(context());
    const element = await render(context({ quotes: [] }));

    buttonByText(element, "+ New quote").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".modal_medium")).toBeTruthy();
    expect(
      element.shadowRoot
        .querySelector('[role="dialog"]')
        .getAttribute("aria-modal")
    ).toBe("true");
    element.shadowRoot.querySelector("button[data-id]").click();
    await flushPromises();
    buttonByText(element, "Save quote").click();
    await flushPromises();

    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        opportunityId: OPPORTUNITY_ID,
        quoteId: undefined,
        lines: [
          {
            pricebookEntryId: ENTRY_ID,
            quantity: 1,
            discountPct: 0,
            unitPrice: 500,
            depositAmount: null,
            termMonths: null,
            description: ""
          }
        ]
      })
    );
  });

  it("edits the selected quote and its quote lines", async () => {
    saveQuote.mockResolvedValue(quote());
    getContext.mockResolvedValue(context());
    const element = await render();

    buttonByText(element, "Edit").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".modal_medium")).toBeTruthy();
    expect(element.shadowRoot.textContent).toContain(
      "Edit Acme appeal – Proposal v1"
    );
    buttonByText(element, "Save quote").click();
    await flushPromises();

    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        opportunityId: OPPORTUNITY_ID,
        quoteId: QUOTE_ID,
        notes: "Initial proposal",
        lines: [
          {
            pricebookEntryId: ENTRY_ID,
            quantity: 2,
            discountPct: 10,
            unitPrice: 500,
            depositAmount: null,
            termMonths: null,
            description: "ASIN B0TEST"
          }
        ]
      })
    );
  });

  it("generates a PDF when the quote does not have one", async () => {
    generatePdf.mockResolvedValue(PDF_ID);
    getContext.mockResolvedValue(
      context({ quotes: [quote({ pdfId: PDF_ID })] })
    );
    const element = await render();

    buttonByText(element, "Generate PDF").click();
    await flushPromises();

    expect(generatePdf).toHaveBeenCalledWith({ quoteId: QUOTE_ID });
    expect(element.shadowRoot.querySelector(".pdf-modal")).toBeTruthy();
    expect(
      element.shadowRoot.querySelector(".pdf-frame").getAttribute("src")
    ).toBe(`/apex/QuoteBuilderPdf?id=${QUOTE_ID}`);
  });

  it("views an existing PDF in a medium modal without regenerating it", async () => {
    const element = await render(
      context({ quotes: [quote({ pdfId: PDF_ID })] })
    );

    buttonByText(element, "View PDF").click();
    await flushPromises();

    expect(generatePdf).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector(".pdf-modal .modal_medium")
    ).toBeTruthy();
    expect(
      element.shadowRoot.querySelector(".pdf-frame").getAttribute("src")
    ).toBe(`/apex/QuoteBuilderPdf?id=${QUOTE_ID}`);
  });

  it("shows loading feedback while preparing the quote email", async () => {
    let resolveDraft;
    const element = await render();
    renderEmailDraft.mockReturnValue(
      new Promise((resolve) => {
        resolveDraft = resolve;
      })
    );

    buttonByText(element, "Send quote").click();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".send-loading")).toBeTruthy();
    expect(element.shadowRoot.textContent).toContain("Preparing email…");

    resolveDraft({
      subject: "Prepared quote",
      htmlBody: "<p>Prepared quote body.</p>"
    });
    await flushPromises();

    expect(element.shadowRoot.querySelector(".send-loading")).toBeFalsy();
  });

  it("shows sending feedback until the quote email finishes", async () => {
    let resolveSend;
    sendQuote.mockReturnValue(
      new Promise((resolve) => {
        resolveSend = resolve;
      })
    );
    getContext.mockResolvedValue(context());
    const element = await render();

    buttonByText(element, "Send quote").click();
    await flushPromises();
    buttonByText(element, "Send email").click();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".send-loading")).toBeTruthy();
    expect(element.shadowRoot.textContent).toContain("Sending quote email…");
    expect(buttonByText(element, "Sending…")).toBeTruthy();

    resolveSend(quote({ status: "Presented", pdfId: PDF_ID }));
    await flushPromises();

    expect(element.shadowRoot.querySelector(".send-modal")).toBeFalsy();
  });

  it("sends the quote to an edited email with a selected template", async () => {
    sendQuote.mockResolvedValue(quote({ status: "Presented", pdfId: PDF_ID }));
    getContext.mockResolvedValue(context());
    const element = await render();

    buttonByText(element, "Send quote").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".send-modal")).toBeTruthy();

    element.shadowRoot
      .querySelector(".recipient-lookup lightning-pill")
      .dispatchEvent(new CustomEvent("remove"));
    await flushPromises();

    const sendInputs = [
      ...element.shadowRoot.querySelectorAll(".send-modal lightning-input")
    ];
    const emailInput = sendInputs.find(
      (input) => input.label === "Recipient email or contact"
    );
    emailInput.value = "end.user@example.com";
    emailInput.dispatchEvent(new CustomEvent("input"));
    emailInput.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    await flushPromises();
    emailInput.value = "billing@example.com";
    emailInput.dispatchEvent(new CustomEvent("input"));
    emailInput.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    await flushPromises();
    buttonByText(element, "Cc").click();
    await flushPromises();
    const ccInput = [
      ...element.shadowRoot.querySelectorAll(".send-modal lightning-input")
    ].find((input) => input.label === "CC");
    ccInput.value = "manager@example.com";
    ccInput.dispatchEvent(new CustomEvent("change"));
    const sendPickers = [
      ...element.shadowRoot.querySelectorAll(".send-modal lightning-combobox")
    ];
    const templatePicker = sendPickers.find(
      (picker) => picker.label === "Email template"
    );
    templatePicker.dispatchEvent(
      new CustomEvent("change", { detail: { value: TEMPLATE_ID } })
    );
    await flushPromises();
    const subjectInput = sendInputs.find((input) => input.label === "Subject");
    subjectInput.value = "Updated quote subject";
    subjectInput.dispatchEvent(new CustomEvent("change"));
    const fromPicker = sendPickers.find(
      (picker) => picker.label === "From address"
    );
    fromPicker.dispatchEvent(
      new CustomEvent("change", { detail: { value: FROM_ADDRESS_ID } })
    );
    const bodyEditor = element.shadowRoot.querySelector(
      ".send-modal lightning-input-rich-text"
    );
    bodyEditor.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "<p>Updated HTML quote body.</p>" }
      })
    );
    buttonByText(element, "Send email").click();
    await flushPromises();

    expect(renderEmailDraft).toHaveBeenLastCalledWith({
      quoteId: QUOTE_ID,
      templateId: TEMPLATE_ID,
      recipientEmail: "end.user@example.com"
    });
    expect(sendQuote).toHaveBeenCalledWith({
      quoteId: QUOTE_ID,
      recipientEmail: "end.user@example.com; billing@example.com",
      ccEmails: "manager@example.com",
      templateId: TEMPLATE_ID,
      fromAddressId: FROM_ADDRESS_ID,
      subject: "Updated quote subject",
      htmlBody: "<p>Updated HTML quote body.</p>"
    });
    expect(element.shadowRoot.querySelector(".send-modal")).toBeFalsy();
  });

  it("selects an email from a Contact on the related Account", async () => {
    sendQuote.mockResolvedValue(quote({ status: "Presented", pdfId: PDF_ID }));
    getContext.mockResolvedValue(context());
    const element = await render(
      context({ quotes: [quote({ recipientEmail: "" })] })
    );

    buttonByText(element, "Send quote").click();
    await flushPromises();
    const recipientInput = [
      ...element.shadowRoot.querySelectorAll(".send-modal lightning-input")
    ].find((input) => input.label === "Recipient email or contact");
    recipientInput.dispatchEvent(new CustomEvent("focus"));
    await flushPromises();
    element.shadowRoot.querySelector(".recipient-lookup__option").click();
    await flushPromises();
    buttonByText(element, "Send email").click();
    await flushPromises();

    expect(sendQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        recipientEmail: "account.buyer@example.com"
      })
    );
  });

  it("commits a manually entered email as a removable recipient pill", async () => {
    const element = await render(
      context({ quotes: [quote({ recipientEmail: "" })] })
    );

    buttonByText(element, "Send quote").click();
    await flushPromises();
    const recipientInput = [
      ...element.shadowRoot.querySelectorAll(".send-modal lightning-input")
    ].find((input) => input.label === "Recipient email or contact");
    recipientInput.value = "manual.recipient@example.com";
    recipientInput.dispatchEvent(new CustomEvent("input"));
    recipientInput.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter" })
    );
    recipientInput.value = "second.recipient@example.com";
    recipientInput.dispatchEvent(new CustomEvent("input"));
    recipientInput.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter" })
    );
    await flushPromises();

    const recipientPills = [
      ...element.shadowRoot.querySelectorAll(".recipient-lookup lightning-pill")
    ];
    expect(recipientPills).toHaveLength(2);
    expect(recipientPills[0].label).toBe("manual.recipient@example.com");
    expect(recipientPills[1].label).toBe("second.recipient@example.com");
    expect(recipientInput.required).toBeFalsy();
    recipientPills[0].dispatchEvent(
      new CustomEvent("remove", {
        detail: { name: "manual.recipient@example.com" }
      })
    );
    await flushPromises();
    expect(
      element.shadowRoot.querySelectorAll(".recipient-lookup lightning-pill")
    ).toHaveLength(1);
  });

  it("syncs only the selected quote to Opportunity products", async () => {
    LightningConfirm.open.mockResolvedValue(true);
    syncQuoteToOpportunity.mockResolvedValue(
      context({ syncedQuoteId: QUOTE_ID, quotes: [quote({ isSynced: true })] })
    );
    const element = await render();

    buttonByText(element, "Sync to Opportunity").click();
    await flushPromises();

    expect(syncQuoteToOpportunity).toHaveBeenCalledWith({
      opportunityId: OPPORTUNITY_ID,
      quoteId: QUOTE_ID
    });
  });

  it("asks for a price book only when a new quote needs one", async () => {
    const noPricebook = context({
      pricebookId: null,
      pricebookName: null,
      catalog: [],
      quotes: []
    });
    setPricebook.mockResolvedValue(context({ quotes: [] }));
    const element = await render(noPricebook);

    buttonByText(element, "+ New quote").click();
    await flushPromises();
    element.shadowRoot.querySelector(".pb").click();
    await flushPromises();
    buttonByText(element, "Use this price book").click();
    await flushPromises();

    expect(setPricebook).toHaveBeenCalledWith({
      opportunityId: OPPORTUNITY_ID,
      pricebookId: PRICEBOOK_ID,
      confirmProductRemoval: false
    });
    expect(LightningConfirm.open).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain("New quote");
  });

  it("changes the price book after confirmation while preserving quote details", async () => {
    const initial = context({
      pricebooks: [
        { id: PRICEBOOK_ID, name: "Services", productCount: 1 },
        { id: OTHER_PRICEBOOK_ID, name: "White Gloves", productCount: 1 }
      ]
    });
    setPricebook.mockResolvedValue(
      context({
        pricebookId: OTHER_PRICEBOOK_ID,
        pricebookName: "White Gloves"
      })
    );
    LightningConfirm.open.mockResolvedValue(true);
    const element = await render(initial);
    buttonByText(element, "Edit").click();
    await flushPromises();
    buttonByText(element, "Change price book").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(`[data-id="${OTHER_PRICEBOOK_ID}"]`)
      .click();
    await flushPromises();
    buttonByText(element, "Use this price book").click();
    await flushPromises();

    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({
        label: "Change price book",
        message: expect.stringContaining(
          "removes the current Opportunity products"
        )
      })
    );
    expect(setPricebook).toHaveBeenCalledWith({
      opportunityId: OPPORTUNITY_ID,
      pricebookId: OTHER_PRICEBOOK_ID,
      confirmProductRemoval: true
    });
    expect(element.shadowRoot.querySelectorAll(".line")).toHaveLength(0);
    expect(element.shadowRoot.querySelector(".chip").textContent).toContain(
      "White Gloves"
    );
    expect(element.shadowRoot.querySelector("lightning-textarea").value).toBe(
      "Initial proposal"
    );
    expect(
      [...element.shadowRoot.querySelectorAll("lightning-input")].find(
        (input) => input.label === "Expiration date"
      ).value
    ).toBe("2026-11-25");
  });

  it("keeps drafted products when a price book change is declined or cancelled", async () => {
    const element = await render(
      context({
        pricebooks: [
          { id: PRICEBOOK_ID, name: "Services", productCount: 1 },
          { id: OTHER_PRICEBOOK_ID, name: "White Gloves", productCount: 1 }
        ]
      })
    );
    LightningConfirm.open.mockResolvedValue(false);
    buttonByText(element, "Edit").click();
    await flushPromises();
    buttonByText(element, "Change price book").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(`[data-id="${OTHER_PRICEBOOK_ID}"]`)
      .click();
    await flushPromises();
    buttonByText(element, "Use this price book").click();
    await flushPromises();
    element.shadowRoot
      .querySelector('[aria-label="Close price book selection"]')
      .click();
    await flushPromises();

    expect(setPricebook).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelectorAll(".line")).toHaveLength(1);
    expect(
      element.shadowRoot.querySelector('[aria-label="Quantity"]').value
    ).toBe("2");
    expect(element.shadowRoot.querySelector(".chip").textContent).toContain(
      "Services"
    );
  });

  it("confirms removal of existing Opportunity products and synchronization even for an empty draft", async () => {
    const element = await render(
      context({
        syncedQuoteId: QUOTE_ID,
        opportunityProductCount: 2,
        quotes: [quote({ isSynced: true })],
        pricebooks: [
          { id: PRICEBOOK_ID, name: "Services", productCount: 1 },
          { id: OTHER_PRICEBOOK_ID, name: "White Gloves", productCount: 1 }
        ]
      })
    );
    setPricebook.mockResolvedValue(
      context({
        pricebookId: OTHER_PRICEBOOK_ID,
        pricebookName: "White Gloves",
        syncedQuoteId: null,
        opportunityProductCount: 0
      })
    );
    let resolveConfirmation;
    LightningConfirm.open.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveConfirmation = resolve;
        })
    );
    buttonByText(element, "+ New quote").click();
    await flushPromises();
    expect(element.shadowRoot.querySelectorAll(".line")).toHaveLength(0);
    buttonByText(element, "Change price book").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(`[data-id="${OTHER_PRICEBOOK_ID}"]`)
      .click();
    await flushPromises();
    const usePricebook = buttonByText(element, "Use this price book");
    usePricebook.click();
    usePricebook.click();
    await flushPromises();

    expect(LightningConfirm.open).toHaveBeenCalledTimes(1);
    expect(LightningConfirm.open.mock.calls[0][0].message).toContain(
      "current Opportunity products"
    );
    expect(LightningConfirm.open.mock.calls[0][0].message).toContain(
      "stops any quote synchronization"
    );
    expect(LightningConfirm.open.mock.calls[0][0].message).toContain(
      "Saved quotes will remain"
    );
    expect(setPricebook).not.toHaveBeenCalled();

    resolveConfirmation(true);
    await flushPromises();
    expect(setPricebook).toHaveBeenCalledTimes(1);
    expect(setPricebook).toHaveBeenCalledWith({
      opportunityId: OPPORTUNITY_ID,
      pricebookId: OTHER_PRICEBOOK_ID,
      confirmProductRemoval: true
    });
    expect(element.shadowRoot.querySelector(".chip").textContent).toContain(
      "White Gloves"
    );
  });

  it("does not change existing Opportunity products when the empty-draft confirmation is declined", async () => {
    const element = await render(
      context({
        syncedQuoteId: QUOTE_ID,
        opportunityProductCount: 2,
        pricebooks: [
          { id: PRICEBOOK_ID, name: "Services", productCount: 1 },
          { id: OTHER_PRICEBOOK_ID, name: "White Gloves", productCount: 1 }
        ]
      })
    );
    LightningConfirm.open.mockResolvedValue(false);
    buttonByText(element, "+ New quote").click();
    await flushPromises();
    buttonByText(element, "Change price book").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(`[data-id="${OTHER_PRICEBOOK_ID}"]`)
      .click();
    await flushPromises();
    buttonByText(element, "Use this price book").click();
    await flushPromises();

    expect(LightningConfirm.open).toHaveBeenCalledTimes(1);
    expect(setPricebook).not.toHaveBeenCalled();
    expect(buttonByText(element, "Use this price book").disabled).toBe(false);
    element.shadowRoot
      .querySelector('[aria-label="Close price book selection"]')
      .click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".chip").textContent).toContain(
      "Services"
    );
  });

  it("reselects the current price book without product-removal confirmation or clearing its draft", async () => {
    const element = await render(
      context({ syncedQuoteId: QUOTE_ID, opportunityProductCount: 2 })
    );
    setPricebook.mockResolvedValue(
      context({ syncedQuoteId: QUOTE_ID, opportunityProductCount: 2 })
    );
    buttonByText(element, "Edit").click();
    await flushPromises();
    buttonByText(element, "Change price book").click();
    await flushPromises();
    buttonByText(element, "Use this price book").click();
    await flushPromises();

    expect(LightningConfirm.open).not.toHaveBeenCalled();
    expect(setPricebook).toHaveBeenCalledWith({
      opportunityId: OPPORTUNITY_ID,
      pricebookId: PRICEBOOK_ID,
      confirmProductRemoval: false
    });
    expect(element.shadowRoot.querySelectorAll(".line")).toHaveLength(1);
    expect(
      element.shadowRoot.querySelector('[aria-label="Quantity"]').value
    ).toBe("2");
  });

  it("preserves the draft and selected price book when a confirmed change fails", async () => {
    const element = await render(
      context({
        pricebooks: [
          { id: PRICEBOOK_ID, name: "Services", productCount: 1 },
          { id: OTHER_PRICEBOOK_ID, name: "White Gloves", productCount: 1 }
        ]
      })
    );
    LightningConfirm.open.mockResolvedValue(true);
    setPricebook.mockRejectedValue({
      body: { message: "The selected price book is no longer active." }
    });
    buttonByText(element, "Edit").click();
    await flushPromises();
    buttonByText(element, "Change price book").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(`[data-id="${OTHER_PRICEBOOK_ID}"]`)
      .click();
    await flushPromises();
    buttonByText(element, "Use this price book").click();
    await flushPromises();

    expect(
      element.shadowRoot
        .querySelector(`[data-id="${OTHER_PRICEBOOK_ID}"]`)
        .getAttribute("aria-checked")
    ).toBe("true");
    expect(buttonByText(element, "Use this price book").disabled).toBe(false);
    element.shadowRoot
      .querySelector('[aria-label="Close price book selection"]')
      .click();
    await flushPromises();
    expect(element.shadowRoot.querySelectorAll(".line")).toHaveLength(1);
    expect(
      element.shadowRoot.querySelector('[aria-label="Quantity"]').value
    ).toBe("2");
    expect(element.shadowRoot.querySelector("lightning-textarea").value).toBe(
      "Initial proposal"
    );
    expect(element.shadowRoot.querySelector(".chip").textContent).toContain(
      "Services"
    );
  });

  it("calculates and saves an overridden unit price while retaining original list price", async () => {
    saveQuote.mockResolvedValue(quote());
    const element = await render(context({ canOverrideDiscount: false }));
    buttonByText(element, "Edit").click();
    await flushPromises();
    const priceInput = element.shadowRoot.querySelector(
      '[aria-label="Unit price"]'
    );
    priceInput.value = "450";
    priceInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(
        ".line__original lightning-formatted-number"
      ).value
    ).toBe(500);
    expect(
      element.shadowRoot.querySelector(
        ".line__total lightning-formatted-number"
      ).value
    ).toBe(810);
    buttonByText(element, "Save quote").click();
    await flushPromises();
    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        lines: [
          expect.objectContaining({
            unitPrice: 450,
            discountPct: 10,
            quantity: 2
          })
        ]
      })
    );
  });

  it("allows a reduced unit price without an approval warning or save block", async () => {
    saveQuote.mockResolvedValue(quote());
    const element = await render(
      context({
        quotes: [quote({ lines: [{ ...quoteLine, discountPct: 0 }] })]
      })
    );
    buttonByText(element, "Edit").click();
    await flushPromises();
    const priceInput = element.shadowRoot.querySelector(
      '[aria-label="Unit price"]'
    );
    priceInput.value = "300";
    priceInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    expect(buttonByText(element, "Save quote").disabled).toBe(false);
    expect(element.shadowRoot.querySelector(".warning")).toBeNull();
    expect(element.shadowRoot.querySelector(".line_warn")).toBeNull();
    buttonByText(element, "Save quote").click();
    await flushPromises();
    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        lines: [expect.objectContaining({ unitPrice: 300, discountPct: 0 })]
      })
    );
  });

  it("applies manager approval only to the explicit discount percentage", async () => {
    const element = await render(
      context({
        quotes: [
          quote({ lines: [{ ...quoteLine, unitPrice: 300, discountPct: 15 }] })
        ]
      })
    );
    buttonByText(element, "Edit").click();
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(false);
    expect(element.shadowRoot.querySelector(".warning")).toBeNull();

    const discount = element.shadowRoot.querySelector(
      '[aria-label="Discount percent"]'
    );
    discount.value = "16";
    discount.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(true);
    expect(element.shadowRoot.querySelector(".warning").textContent).toContain(
      "Discounts above 15%"
    );
    expect(element.shadowRoot.textContent).not.toContain(
      "Price reductions above"
    );
    expect(saveQuote).not.toHaveBeenCalled();
  });

  it("copies the price book deposit per unit onto a new quote product", async () => {
    saveQuote.mockResolvedValue(quote());
    const initial = context({ quotes: [] });
    initial.catalog[0].depositAmount = 125;
    const element = await render(initial);
    buttonByText(element, "+ New quote").click();
    await flushPromises();
    element.shadowRoot.querySelector(`button[data-id="${ENTRY_ID}"]`).click();
    await flushPromises();
    const deposit = element.shadowRoot.querySelector(
      '[aria-label="Deposit per unit"]'
    );
    expect(deposit.value).toBe("125");
    const quantity = element.shadowRoot.querySelector(
      '[aria-label="Quantity"]'
    );
    quantity.value = "3";
    quantity.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(deposit.value).toBe("125");
    expect(
      element.shadowRoot.querySelector(
        ".line__total lightning-formatted-number"
      ).value
    ).toBe(1500);
    buttonByText(element, "Save quote").click();
    await flushPromises();
    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        lines: [expect.objectContaining({ depositAmount: 125, quantity: 3 })]
      })
    );
    expect(initial.catalog[0].depositAmount).toBe(125);
  });

  it("shows configured deposits beneath catalogue prices", async () => {
    const withDeposit = context({ quotes: [] });
    withDeposit.catalog[0].depositAmount = 125;
    const element = await render(withDeposit);
    buttonByText(element, "+ New quote").click();
    await flushPromises();

    const deposit = element.shadowRoot.querySelector(".product__deposit");
    expect(deposit.textContent).toContain("Deposit");
    expect(deposit.querySelector("lightning-formatted-number").value).toBe(125);

    const withoutDeposit = context({ quotes: [] });
    withoutDeposit.catalog[0].depositAmount = 0;
    const secondElement = await render(withoutDeposit);
    buttonByText(secondElement, "+ New quote").click();
    await flushPromises();
    expect(
      secondElement.shadowRoot.querySelector(".product__deposit")
    ).toBeNull();
  });

  it("retains and displays the saved product deposit when the catalogue deposit differs", async () => {
    saveQuote.mockResolvedValue(quote());
    const initial = context({
      quotes: [quote({ lines: [{ ...quoteLine, depositAmount: 80 }] })]
    });
    initial.catalog[0].depositAmount = 125;
    const element = await render(initial);
    expect(
      element.shadowRoot.querySelector(
        ".line__deposit-summary lightning-formatted-number"
      ).value
    ).toBe(80);
    buttonByText(element, "Edit").click();
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[aria-label="Deposit per unit"]').value
    ).toBe("80");
    buttonByText(element, "Save quote").click();
    await flushPromises();
    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        lines: [expect.objectContaining({ depositAmount: 80 })]
      })
    );
  });

  it("preserves an explicit zero deposit instead of replacing it with a default", async () => {
    saveQuote.mockResolvedValue(quote());
    const element = await render(
      context({
        quotes: [quote({ lines: [{ ...quoteLine, depositAmount: 0 }] })]
      })
    );
    expect(
      element.shadowRoot.querySelector(
        ".line__deposit-summary lightning-formatted-number"
      ).value
    ).toBe(0);
    buttonByText(element, "Edit").click();
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[aria-label="Deposit per unit"]').value
    ).toBe("0");
    buttonByText(element, "Save quote").click();
    await flushPromises();
    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        lines: [expect.objectContaining({ depositAmount: 0 })]
      })
    );
  });

  it("rejects negative deposits and sends blank deposits as a price book default request", async () => {
    saveQuote.mockResolvedValue(quote());
    const element = await render();
    buttonByText(element, "Edit").click();
    await flushPromises();
    const deposit = element.shadowRoot.querySelector(
      '[aria-label="Deposit per unit"]'
    );
    expect(deposit.placeholder).toBe("Price book default");
    expect(deposit.title).toContain("enter 0 for no deposit");
    deposit.value = "-1";
    deposit.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(true);
    buttonByText(element, "Save quote").click();
    await flushPromises();
    expect(saveQuote).not.toHaveBeenCalled();
    deposit.value = "";
    deposit.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(false);
    buttonByText(element, "Save quote").click();
    await flushPromises();
    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        lines: [expect.objectContaining({ depositAmount: null })]
      })
    );
  });

  it("requires a recurring quote term and saves inherited and product-specific terms", async () => {
    saveQuote.mockResolvedValue(quote());
    const recurringEntry = "01u000000000002AAA";
    const initial = context({
      quotes: [],
      catalog: [
        {
          pricebookEntryId: ENTRY_ID,
          name: "Monthly care",
          listPrice: 500,
          isRecurring: true
        },
        {
          pricebookEntryId: recurringEntry,
          name: "Monthly support",
          listPrice: 100,
          isRecurring: true
        }
      ]
    });
    const element = await render(initial);
    buttonByText(element, "+ New quote").click();
    await flushPromises();
    element.shadowRoot.querySelector(`button[data-id="${ENTRY_ID}"]`).click();
    element.shadowRoot
      .querySelector(`button[data-id="${recurringEntry}"]`)
      .click();
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(true);

    const quoteTerm = element.shadowRoot.querySelector(".quote-term");
    quoteTerm.value = "12";
    quoteTerm.dispatchEvent(new CustomEvent("change"));
    const lineTerms = element.shadowRoot.querySelectorAll(
      '[aria-label="Product recurring term (months)"]'
    );
    lineTerms[1].value = "6";
    lineTerms[1].dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(false);
    buttonByText(element, "Save quote").click();
    await flushPromises();

    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        termMonths: 12,
        lines: [
          expect.objectContaining({
            pricebookEntryId: ENTRY_ID,
            termMonths: null
          }),
          expect.objectContaining({
            pricebookEntryId: recurringEntry,
            termMonths: 6
          })
        ]
      })
    );
  });

  it("displays saved recurring terms on the quote and each recurring product", async () => {
    const element = await render(
      context({
        quotes: [
          quote({
            termMonths: 12,
            lines: [{ ...quoteLine, isRecurring: true, termMonths: 6 }]
          })
        ]
      })
    );
    expect(element.shadowRoot.textContent).toContain(
      "Recurring term: 12 months"
    );
    expect(element.shadowRoot.textContent).toContain("Recurring · 6 months");
  });

  it("requires an explicit price book choice for a quote from a different catalogue", async () => {
    const element = await render(
      context({
        quotes: [
          quote({
            pricebookId: OTHER_PRICEBOOK_ID,
            pricebookName: "Previous catalogue"
          })
        ]
      })
    );
    buttonByText(element, "Edit").click();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".chip").textContent).toContain(
      "Previous catalogue"
    );
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Select Change price book");
    expect(buttonByText(element, "+ Add").disabled).toBe(true);
    expect(buttonByText(element, "Save quote").disabled).toBe(true);

    setPricebook.mockResolvedValue(context());
    LightningConfirm.open.mockResolvedValue(true);
    buttonByText(element, "Change price book").click();
    await flushPromises();
    buttonByText(element, "Use this price book").click();
    await flushPromises();

    expect(LightningConfirm.open).toHaveBeenCalled();
    expect(setPricebook).toHaveBeenCalledWith({
      opportunityId: OPPORTUNITY_ID,
      pricebookId: PRICEBOOK_ID,
      confirmProductRemoval: false
    });
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll(".line")).toHaveLength(0);
    expect(buttonByText(element, "+ Add").disabled).toBe(false);
  });

  it("rejects invalid prices and fractional or excessive recurring terms", async () => {
    const element = await render(
      context({
        quotes: [
          quote({
            termMonths: 12,
            lines: [{ ...quoteLine, isRecurring: true, termMonths: null }]
          })
        ]
      })
    );
    buttonByText(element, "Edit").click();
    await flushPromises();
    const price = element.shadowRoot.querySelector('[aria-label="Unit price"]');
    price.value = "-1";
    price.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(true);
    price.value = "500";
    price.dispatchEvent(new CustomEvent("change"));
    const quoteTerm = element.shadowRoot.querySelector(".quote-term");
    quoteTerm.value = "1.5";
    quoteTerm.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(true);
    quoteTerm.value = "12";
    quoteTerm.dispatchEvent(new CustomEvent("change"));
    const lineTerm = element.shadowRoot.querySelector(
      '[aria-label="Product recurring term (months)"]'
    );
    lineTerm.value = "1201";
    lineTerm.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(true);
    lineTerm.value = "";
    lineTerm.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(buttonByText(element, "Save quote").disabled).toBe(false);
    expect(saveQuote).not.toHaveBeenCalled();
  });

  it("keeps inherited terms linked to the quote after reopening while preserving overrides", async () => {
    saveQuote.mockResolvedValue(quote());
    const explicitEntry = "01u000000000002AAA";
    const element = await render(
      context({
        quotes: [
          quote({
            termMonths: 12,
            lines: [
              {
                ...quoteLine,
                isRecurring: true,
                termMonths: 12,
                inheritsQuoteTerm: true
              },
              {
                ...quoteLine,
                lineId: "0QL000000000002AAA",
                pricebookEntryId: explicitEntry,
                name: "Custom term service",
                isRecurring: true,
                termMonths: 6,
                inheritsQuoteTerm: false
              }
            ]
          })
        ]
      })
    );
    buttonByText(element, "Edit").click();
    await flushPromises();
    const lineTerms = element.shadowRoot.querySelectorAll(
      '[aria-label="Product recurring term (months)"]'
    );
    expect(lineTerms[0].value).toBe("");
    expect(lineTerms[1].value).toBe("6");
    const quoteTerm = element.shadowRoot.querySelector(".quote-term");
    quoteTerm.value = "24";
    quoteTerm.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    expect(
      element.shadowRoot.querySelectorAll(".line__term .muted")[0].textContent
    ).toContain("24 months");
    expect(
      element.shadowRoot.querySelectorAll(".line__term .muted")[1].textContent
    ).toContain("6 months");
    buttonByText(element, "Save quote").click();
    await flushPromises();
    expect(saveQuote).toHaveBeenCalledWith(
      expect.objectContaining({
        termMonths: 24,
        lines: [
          expect.objectContaining({
            pricebookEntryId: ENTRY_ID,
            termMonths: null
          }),
          expect.objectContaining({
            pricebookEntryId: explicitEntry,
            termMonths: 6
          })
        ]
      })
    );
  });

  it("sums rounded line amounts so the displayed quote total matches its line totals", async () => {
    const smallLine = {
      ...quoteLine,
      unitPrice: 0.05,
      listPrice: 0.05,
      quantity: 1,
      discountPct: 10,
      totalPrice: 0.05
    };
    const element = await render(
      context({
        quotes: [
          quote({
            totalPrice: 0.1,
            lines: [
              smallLine,
              {
                ...smallLine,
                lineId: "0QL000000000002AAA",
                pricebookEntryId: "01u000000000002AAA"
              }
            ]
          })
        ]
      })
    );
    buttonByText(element, "Edit").click();
    await flushPromises();

    const lineAmounts = [
      ...element.shadowRoot.querySelectorAll(
        ".line__total lightning-formatted-number"
      )
    ].map((amount) => amount.value);
    expect(lineAmounts).toEqual([0.05, 0.05]);
    const total = element.shadowRoot.querySelector(
      ".totals__grand lightning-formatted-number"
    ).value;
    expect(total).toBe(0.1);
    expect(total).toBe(lineAmounts.reduce((sum, amount) => sum + amount, 0));
  });
});
