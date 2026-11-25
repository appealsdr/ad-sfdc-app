import { createElement } from "lwc";
import ProductSetup from "c/productSetup";
import getSetup from "@salesforce/apex/ProductSetupController.getSetup";
import savePricebooks from "@salesforce/apex/ProductSetupController.savePricebooks";
import saveRequirements from "@salesforce/apex/ProductSetupController.saveRequirements";
import { getPicklistValues } from "lightning/uiObjectInfoApi";

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

async function mount(overrides) {
  getSetup.mockResolvedValue(setup(overrides));
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
    expect(
      [...element.shadowRoot.querySelectorAll("lightning-tab")].map(
        (tab) => tab.label
      )
    ).toEqual(["Price Books", "Onboarding Configuration"]);
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
    getPicklistValues.emit({
      values: [
        { label: "PDF", value: "PDF" },
        { label: "PNG", value: "PNG" }
      ]
    });
    button(element, "Add Document").click();
    await flushPromises();
    const dialog = element.shadowRoot.querySelector('[role="dialog"]');
    const template = element.shadowRoot.querySelector(
      ".document-dialog lightning-combobox"
    );
    template.dispatchEvent(
      new CustomEvent("change", { detail: { value: TEMPLATE_ID } })
    );
    await flushPromises();
    const name = element.shadowRoot.querySelector(
      '.document-dialog lightning-input[data-field="name"]'
    );
    expect(name.value).toBe("Invoice");
    const formats = dialog.querySelector("lightning-dual-listbox");
    expect(formats.value).toEqual(["PDF"]);
    expect(formats.options.map((option) => option.value)).toEqual([
      "PDF",
      "PNG"
    ]);
    formats.dispatchEvent(
      new CustomEvent("change", { detail: { value: ["PDF", "PNG"] } })
    );
    element.shadowRoot
      .querySelectorAll(".requirement-input")
      .forEach((input) => {
        input.reportValidity = jest.fn().mockReturnValue(true);
      });
    button(element, "Apply Document").click();
    await flushPromises();
    expect(saveRequirements).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
    expect(element.shadowRoot.querySelector("ul").textContent).toContain(
      "Invoice"
    );
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
          acceptedFormat: "PDF;PNG",
          active: true
        })
      ]
    });
  });

  it("discards the document draft when the dialog is canceled", async () => {
    const element = await mount();
    button(element, "Add Document").click();
    await flushPromises();
    button(element, "Cancel").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
    expect(element.shadowRoot.textContent).toContain(
      "No required documents configured"
    );
    expect(saveRequirements).not.toHaveBeenCalled();
  });

  it("requires all document inputs except template and allows an inactive document", async () => {
    const element = await mount();
    button(element, "Add Document").click();
    await flushPromises();
    const dialog = element.shadowRoot.querySelector('[role="dialog"]');
    expect(
      dialog.querySelector(".slds-modal__content").firstElementChild.label
    ).toBe("Active");
    expect(dialog.querySelector("lightning-combobox").required).toBeFalsy();
    for (const field of [
      "name",
      "shortDescription",
      "acceptedFormat",
      "instructions"
    ]) {
      expect(dialog.querySelector(`[data-field="${field}"]`).required).toBe(
        true
      );
    }
    const change = (field, value) =>
      dialog
        .querySelector(`[data-field="${field}"]`)
        .dispatchEvent(new CustomEvent("change", { detail: { value } }));
    dialog.querySelectorAll(".requirement-input").forEach((input) => {
      input.reportValidity = jest.fn().mockReturnValue(true);
    });
    change("name", "Proof");
    change("shortDescription", "Customer proof");
    change("acceptedFormat", ["PDF"]);
    change("instructions", "<p>&nbsp;<br></p>");
    const active = dialog.querySelector('[data-field="active"]');
    active.checked = false;
    active.dispatchEvent(new CustomEvent("change"));
    button(element, "Apply Document").click();
    await flushPromises();
    expect(dialog.textContent).toContain("Enter client instructions.");
    change("instructions", "<p>Upload proof.</p>");
    button(element, "Apply Document").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
    expect(element.shadowRoot.querySelector("ul").textContent).toContain(
      "Inactive"
    );
  });

  it("clones a document into a new draft and discards it through the close icon", async () => {
    const original = {
      id: "a20000000000001AAA",
      name: "Invoice",
      templateId: TEMPLATE_ID,
      shortDescription: "Latest invoice",
      acceptedFormat: "PDF;PNG",
      instructions: "Upload an invoice.",
      active: true
    };
    const element = await mount({ requirements: [original] });
    const clone = element.shadowRoot.querySelector(
      'lightning-button-icon[title="Clone required document"]'
    );
    clone.click();
    await flushPromises();
    let dialog = element.shadowRoot.querySelector('[role="dialog"]');
    expect(dialog.getAttribute("aria-label")).toBe("Clone Required Document");
    expect(dialog.querySelector('[data-field="name"]').value).toBe(
      original.name
    );
    expect(dialog.querySelector("lightning-dual-listbox").value).toEqual([
      "PDF",
      "PNG"
    ]);
    dialog
      .querySelector('lightning-button-icon[title="Close required document"]')
      .click();
    await flushPromises();
    expect(element.shadowRoot.querySelector("ul").children).toHaveLength(1);
    expect(saveRequirements).not.toHaveBeenCalled();

    clone.click();
    await flushPromises();
    dialog = element.shadowRoot.querySelector('[role="dialog"]');
    dialog.querySelectorAll(".requirement-input").forEach((input) => {
      input.reportValidity = jest.fn().mockReturnValue(true);
    });
    button(element, "Apply Document").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector("ul").children).toHaveLength(2);
    saveRequirements.mockResolvedValue(setup());
    button(element, "Save Documents").click();
    await flushPromises();
    expect(saveRequirements.mock.calls[0][0].rows).toEqual([
      expect.objectContaining(original),
      expect.objectContaining({ ...original, id: null })
    ]);
  });
});
