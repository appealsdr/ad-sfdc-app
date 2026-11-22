import { createElement } from "lwc";
import ProductSetup from "c/productSetup";
import getSetup from "@salesforce/apex/ProductSetupController.getSetup";
import savePricebooks from "@salesforce/apex/ProductSetupController.savePricebooks";
import saveRequirements from "@salesforce/apex/ProductSetupController.saveRequirements";

jest.mock(
  "@salesforce/apex/ProductSetupController.getSetup",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ProductSetupController.savePricebooks",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ProductSetupController.saveRequirements",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const PRODUCT_ID = "01t000000000001AAA";
const STANDARD_ID = "01s000000000001AAA";
const CUSTOM_ID = "01s000000000002AAA";
const TEMPLATE_ID = "a0f000000000001AAA";
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

const setup = (overrides = {}) => ({
  pricebooks: [
    {
      pricebookId: STANDARD_ID,
      pricebookName: "Standard Price Book",
      isStandard: true,
      selected: false,
      unitPrice: null,
      deposit: null,
      paymentType: null
    },
    {
      pricebookId: CUSTOM_ID,
      pricebookName: "Services",
      isStandard: false,
      selected: true,
      unitPrice: 450,
      deposit: 100,
      paymentType: "Full Price"
    }
  ],
  templates: [
    {
      id: TEMPLATE_ID,
      name: "Invoice",
      shortDescription: "Latest invoice",
      acceptedFormat: "PDF",
      instructions: "Upload an invoice.",
      active: true
    }
  ],
  requirements: [],
  paymentTypes: ["Full Price", "Recurring"],
  ...overrides
});

function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (item) => item.label === label
  );
}

async function mount() {
  getSetup.mockResolvedValue(setup());
  const element = createElement("c-product-setup", { is: ProductSetup });
  element.recordId = PRODUCT_ID;
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

describe("c-product-setup", () => {
  beforeEach(() => {
    getSetup.mockReset();
    savePricebooks.mockReset();
    saveRequirements.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.restoreAllMocks();
  });

  it("loads price books, required documents, and the onboarding field editor", async () => {
    const element = await mount();
    const cards = [...element.shadowRoot.querySelectorAll("lightning-card")];
    expect(cards.map((card) => card.title)).toEqual([
      "Price Book Setup",
      "Required Documents"
    ]);
    expect(element.shadowRoot.querySelectorAll(".pricebook-row")).toHaveLength(
      2
    );
    const groups = [...element.shadowRoot.querySelectorAll(".pricebook-group")];
    expect(groups.map((group) => group.textContent)).toEqual([
      expect.stringContaining("Assigned price books"),
      expect.stringContaining("Available active price books")
    ]);
    expect(
      groups[0].querySelector('lightning-input[data-field="selected"]').label
    ).toBe("Services");
    expect(
      groups[1].querySelector('lightning-input[data-field="selected"]').label
    ).toBe("Standard Price Book");
    expect(
      element.shadowRoot.querySelector("c-product-onboarding-config").recordId
    ).toBe(PRODUCT_ID);
    expect(element.shadowRoot.textContent).toContain(
      "No required documents configured"
    );
  });

  it("enables Standard Price Book inputs and saves all pricing rows", async () => {
    const element = await mount();
    const standardCheckbox = element.shadowRoot.querySelector(
      `lightning-input[data-id="${STANDARD_ID}"][data-field="selected"]`
    );
    standardCheckbox.checked = true;
    standardCheckbox.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    const standardPrice = element.shadowRoot.querySelector(
      `lightning-input[data-id="${STANDARD_ID}"][data-field="unitPrice"]`
    );
    expect(standardPrice.disabled).toBe(false);
    standardPrice.value = "500";
    standardPrice.dispatchEvent(new CustomEvent("change"));
    element.shadowRoot.querySelectorAll(".pricebook-input").forEach((input) => {
      input.reportValidity = jest.fn().mockReturnValue(true);
    });
    savePricebooks.mockResolvedValue(setup());
    button(element, "Save Price Books").click();
    await flushPromises();

    expect(savePricebooks).toHaveBeenCalledTimes(1);
    expect(savePricebooks.mock.calls[0][0].productId).toBe(PRODUCT_ID);
    expect(savePricebooks.mock.calls[0][0].rows[0]).toMatchObject({
      pricebookId: STANDARD_ID,
      selected: true,
      unitPrice: 500
    });
  });

  it("shows an error toast and does not save invalid price book fields", async () => {
    const element = await mount();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    element.shadowRoot.querySelectorAll(".pricebook-input").forEach((input) => {
      input.reportValidity = jest.fn().mockReturnValue(false);
    });

    button(element, "Save Price Books").click();
    await flushPromises();

    expect(savePricebooks).not.toHaveBeenCalled();
    expect(toastHandler).toHaveBeenCalledTimes(1);
    expect(toastHandler.mock.calls[0][0].detail).toMatchObject({
      title: "Complete required information",
      message: "Review the highlighted price book fields before saving.",
      variant: "error"
    });
  });

  it("prefills a required document from a template and saves it", async () => {
    const element = await mount();
    button(element, "Add Document").click();
    await flushPromises();
    const template = element.shadowRoot.querySelector(
      ".requirement-row lightning-combobox"
    );
    template.dispatchEvent(
      new CustomEvent("change", { detail: { value: TEMPLATE_ID } })
    );
    await flushPromises();
    const name = element.shadowRoot.querySelector(
      '.requirement-row lightning-input[data-field="name"]'
    );
    expect(name.value).toBe("Invoice");
    element.shadowRoot
      .querySelectorAll(".requirement-input")
      .forEach((input) => {
        input.reportValidity = jest.fn().mockReturnValue(true);
      });
    saveRequirements.mockResolvedValue(
      setup({
        requirements: [
          {
            id: "a20000000000001AAA",
            name: "Invoice",
            templateId: TEMPLATE_ID,
            active: true
          }
        ]
      })
    );
    button(element, "Save Documents").click();
    await flushPromises();

    expect(saveRequirements).toHaveBeenCalledWith({
      productId: PRODUCT_ID,
      rows: [
        expect.objectContaining({
          name: "Invoice",
          templateId: TEMPLATE_ID,
          acceptedFormat: "PDF",
          active: true
        })
      ]
    });
  });
});
