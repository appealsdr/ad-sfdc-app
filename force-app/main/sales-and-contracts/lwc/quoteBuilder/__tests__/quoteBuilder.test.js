import { createElement } from "lwc";
import QuoteBuilder from "c/quoteBuilder";
import getContext from "@salesforce/apex/QuoteBuilderController.getContext";
import setPricebook from "@salesforce/apex/QuoteBuilderController.setPricebook";
import saveLines from "@salesforce/apex/QuoteBuilderController.saveLines";
import createQuote from "@salesforce/apex/QuoteBuilderController.createQuote";

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
  "@salesforce/apex/QuoteBuilderController.saveLines",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuoteBuilderController.createQuote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuoteBuilderController.generatePdf",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const RECORD_ID = "006000000000001AAA";
const ENTRY_ID = "01u000000000001AAA";
const PRICEBOOK_ID = "01s000000000001AAA";

const context = (overrides = {}) => ({
  opportunityId: RECORD_ID,
  opportunityName: "Acme appeal",
  accountName: "Acme",
  stageName: "Meeting Booked",
  pricebookId: PRICEBOOK_ID,
  pricebookName: "Services",
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
  lines: [],
  latestQuote: null,
  quoteCount: 0,
  pricebooks: [
    {
      id: PRICEBOOK_ID,
      name: "Services",
      description: "Core services",
      productCount: 1,
      isCurrent: true
    }
  ],
  ...overrides
});

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(ctx = context()) {
  getContext.mockResolvedValue(ctx);
  const element = createElement("c-quote-builder", { is: QuoteBuilder });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

describe("c-quote-builder", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads the Opportunity catalogue and adds a product", async () => {
    const element = await render();

    expect(getContext).toHaveBeenCalledWith({ opportunityId: RECORD_ID });
    expect(element.shadowRoot.textContent).toContain("Listing reinstatement");

    element.shadowRoot.querySelector("button[data-id]").click();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("1 line(s)");
    expect(
      element.shadowRoot.querySelector(".totals__grand").textContent
    ).toContain("Total");
  });

  it("saves the selected products to the Opportunity", async () => {
    saveLines.mockResolvedValue(
      context({
        lines: [
          {
            pricebookEntryId: ENTRY_ID,
            name: "Listing reinstatement",
            family: "Appeals",
            listPrice: 500,
            quantity: 1,
            discountPct: 0,
            description: ""
          }
        ]
      })
    );
    const element = await render();
    element.shadowRoot.querySelector("button[data-id]").click();
    await flushPromises();

    const saveButton = [...element.shadowRoot.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Save products"
    );
    saveButton.click();
    await flushPromises();

    expect(saveLines).toHaveBeenCalledWith({
      opportunityId: RECORD_ID,
      lines: [
        {
          pricebookEntryId: ENTRY_ID,
          quantity: 1,
          discountPct: 0,
          description: ""
        }
      ]
    });
  });

  it("blocks quote actions when a discount needs approval", async () => {
    const element = await render(
      context({
        lines: [
          {
            pricebookEntryId: ENTRY_ID,
            name: "Listing reinstatement",
            family: "Appeals",
            listPrice: 500,
            quantity: 1,
            discountPct: 25,
            description: ""
          }
        ]
      })
    );

    expect(element.shadowRoot.textContent).toContain("needs manager approval");
    const createButton = [
      ...element.shadowRoot.querySelectorAll("button")
    ].find((button) => button.textContent.trim() === "Create quote");
    expect(createButton.disabled).toBe(true);
  });

  it("sets a price book when the Opportunity has none", async () => {
    const noBook = context({ pricebookId: null, pricebookName: null });
    setPricebook.mockResolvedValue(context());
    const element = await render(noBook);

    element.shadowRoot.querySelector(".pb").click();
    await flushPromises();
    const useButton = [...element.shadowRoot.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Use this price book"
    );
    useButton.click();
    await flushPromises();

    expect(setPricebook).toHaveBeenCalledWith({
      opportunityId: RECORD_ID,
      pricebookId: PRICEBOOK_ID
    });
  });

  it("creates a quote from saved lines", async () => {
    const saved = context({
      lines: [
        {
          pricebookEntryId: ENTRY_ID,
          name: "Listing reinstatement",
          family: "Appeals",
          listPrice: 500,
          quantity: 1,
          discountPct: 0,
          description: ""
        }
      ]
    });
    createQuote.mockResolvedValue({
      quoteId: "0Q0000000000001AAA",
      name: "Acme appeal – Proposal v1",
      quoteNumber: "00000001"
    });
    getContext.mockResolvedValueOnce(saved).mockResolvedValueOnce(saved);
    const element = createElement("c-quote-builder", { is: QuoteBuilder });
    element.recordId = RECORD_ID;
    document.body.appendChild(element);
    await flushPromises();

    const createButton = [
      ...element.shadowRoot.querySelectorAll("button")
    ].find((button) => button.textContent.trim() === "Create quote");
    createButton.click();
    await flushPromises();

    expect(createQuote).toHaveBeenCalledWith({
      opportunityId: RECORD_ID,
      validDays: 14,
      notes: ""
    });
  });
});
