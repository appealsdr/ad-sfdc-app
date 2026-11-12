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

  it("sends the quote to an edited email with a selected template", async () => {
    sendQuote.mockResolvedValue(quote({ status: "Presented", pdfId: PDF_ID }));
    getContext.mockResolvedValue(context());
    const element = await render();

    buttonByText(element, "Send quote").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".send-modal")).toBeTruthy();

    const sendInputs = [
      ...element.shadowRoot.querySelectorAll(".send-modal lightning-input")
    ];
    const emailInput = sendInputs.find(
      (input) => input.label === "Recipient email"
    );
    emailInput.value = "end.user@example.com";
    emailInput.dispatchEvent(new CustomEvent("change"));
    const ccInput = sendInputs.find((input) => input.label === "CC");
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
      templateId: TEMPLATE_ID
    });
    expect(sendQuote).toHaveBeenCalledWith({
      quoteId: QUOTE_ID,
      recipientEmail: "end.user@example.com",
      ccEmails: "manager@example.com",
      templateId: TEMPLATE_ID,
      fromAddressId: FROM_ADDRESS_ID,
      subject: "Updated quote subject",
      htmlBody: "<p>Updated HTML quote body.</p>"
    });
    expect(element.shadowRoot.querySelector(".send-modal")).toBeFalsy();
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
      pricebookId: PRICEBOOK_ID
    });
    expect(element.shadowRoot.textContent).toContain("New quote");
  });
});
