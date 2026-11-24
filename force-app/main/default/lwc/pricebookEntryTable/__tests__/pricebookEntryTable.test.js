import { createElement } from "lwc";
import PricebookEntryTable from "c/pricebookEntryTable";
import { refreshApex } from "@salesforce/apex";
import LightningConfirm from "lightning/confirm";
import getEntries from "@salesforce/apex/PricebookEntryTableController.getEntries";
import getAvailableProducts from "@salesforce/apex/PricebookEntryTableController.getAvailableProducts";
import addProducts from "@salesforce/apex/PricebookEntryTableController.addProducts";
import saveEntries from "@salesforce/apex/PricebookEntryTableController.saveEntries";
import deleteEntry from "@salesforce/apex/PricebookEntryTableController.deleteEntry";

jest.mock("lightning/confirm", () => ({ open: jest.fn() }), { virtual: true });

jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});

jest.mock(
  "@salesforce/apex/PricebookEntryTableController.getEntries",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PricebookEntryTableController.getAvailableProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PricebookEntryTableController.addProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PricebookEntryTableController.saveEntries",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PricebookEntryTableController.deleteEntry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const PRICEBOOK_ID = "01s000000000001AAA";
const ENTRY_ID = "01u000000000001AAA";
const PRODUCT_ID = "01t000000000001AAA";
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (item) => item.label === label
  );
}

function emitEntries() {
  getEntries.emit({
    fields: [
      {
        apiName: "Product2Id",
        label: "Product ID",
        dataType: "reference",
        editable: false
      },
      {
        apiName: "UnitPrice",
        label: "List Price",
        dataType: "currency",
        editable: true
      },
      {
        apiName: "IsActive",
        label: "Active",
        dataType: "boolean",
        editable: true
      },
      {
        apiName: "Deposit__c",
        label: "Deposit",
        dataType: "currency",
        editable: true
      },
      {
        apiName: "Payment_type__c",
        label: "Payment Type",
        dataType: "picklist",
        editable: true
      }
    ],
    rows: [
      {
        id: ENTRY_ID,
        productId: PRODUCT_ID,
        values: {
          Product2Id: "Appeal Service",
          UnitPrice: 220,
          IsActive: true,
          Deposit__c: 50,
          Payment_type__c: "Deposit"
        }
      }
    ],
    paymentTypes: ["Deposit", "Recurring"],
    canCreateEntries: true,
    canUpdateEntries: true,
    canDeleteEntries: true,
    rowLimitReached: false
  });
}

async function mount() {
  const element = createElement("c-pricebook-entry-table", {
    is: PricebookEntryTable
  });
  element.recordId = PRICEBOOK_ID;
  element.fieldSetName = undefined;
  document.body.appendChild(element);
  await flushPromises();
  emitEntries();
  await flushPromises();
  return element;
}

describe("c-pricebook-entry-table", () => {
  beforeEach(() => {
    getAvailableProducts.mockReset();
    addProducts.mockReset();
    saveEntries.mockReset();
    deleteEntry.mockReset();
    LightningConfirm.open.mockReset();
    refreshApex.mockReset();
    refreshApex.mockResolvedValue();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("loads with the default fields when no field set is configured", async () => {
    const element = createElement("c-pricebook-entry-table", {
      is: PricebookEntryTable
    });
    element.recordId = PRICEBOOK_ID;
    element.fieldSetName = undefined;
    document.body.appendChild(element);
    await flushPromises();

    expect(getEntries.getLastConfig()).toEqual({
      pricebookId: PRICEBOOK_ID,
      fieldSetName: ""
    });

    emitEntries();
    await flushPromises();

    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data[0]).toMatchObject({
      Id: ENTRY_ID,
      ProductUrl: `/lightning/r/Product2/${PRODUCT_ID}/view`,
      Product2Id: "Appeal Service",
      UnitPrice: 220,
      Deposit__c: 50,
      Payment_type__c: "Deposit"
    });
    expect(table.columns.map((column) => column.label)).toEqual([
      "Product ID",
      "List Price",
      "Active",
      "Deposit",
      "Payment Type",
      "Actions"
    ]);
    expect(table.columns[0]).toMatchObject({
      fieldName: "ProductUrl",
      type: "url"
    });
  });

  it("edits and saves the full pricing table", async () => {
    const element = await mount();
    button(element, "Edit").click();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".edit-table")).not.toBeNull();
    element.shadowRoot.querySelectorAll(".edit-input").forEach((input) => {
      input.reportValidity = jest.fn().mockReturnValue(true);
    });
    const price = element.shadowRoot.querySelector(
      'lightning-input[data-field="UnitPrice"]'
    );
    price.value = "300";
    price.dispatchEvent(new CustomEvent("change"));
    saveEntries.mockResolvedValue();
    button(element, "Save").click();
    await flushPromises();

    expect(saveEntries).toHaveBeenCalledWith({
      pricebookId: PRICEBOOK_ID,
      updates: [
        {
          entryId: ENTRY_ID,
          unitPrice: 300,
          active: true,
          deposit: 50,
          paymentType: "Deposit"
        }
      ]
    });
    expect(element.shadowRoot.querySelector(".edit-table")).toBeNull();
  });

  it("adds selected Products from the card action", async () => {
    getAvailableProducts.mockResolvedValue([
      {
        productId: PRODUCT_ID,
        productName: "New Service",
        productCode: "NEW-001",
        standardPrice: 125
      }
    ]);
    addProducts.mockResolvedValue();
    const element = await mount();

    button(element, "Add Products").click();
    await flushPromises();
    const selectionTable = [
      ...element.shadowRoot.querySelectorAll("lightning-datatable")
    ].find((table) => table.keyField === "productId");
    expect(selectionTable.data[0].productUrl).toBe(
      `/lightning/r/Product2/${PRODUCT_ID}/view`
    );
    selectionTable.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: { selectedRows: [{ productId: PRODUCT_ID }] }
      })
    );
    await flushPromises();
    button(element, "Add Selected").click();
    await flushPromises();

    expect(addProducts).toHaveBeenCalledWith({
      pricebookId: PRICEBOOK_ID,
      productIds: [PRODUCT_ID]
    });
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
  });

  it("requires Payment Type and conditionally requires Deposit", async () => {
    const element = await mount();
    button(element, "Edit").click();
    await flushPromises();

    const paymentType = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="Payment_type__c"]'
    );
    const deposit = element.shadowRoot.querySelector(
      'lightning-input[data-field="Deposit__c"]'
    );
    expect(paymentType.required).toBe(true);
    expect(deposit.required).toBe(true);

    paymentType.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Full Price" } })
    );
    await flushPromises();
    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="Deposit__c"]'
      ).required
    ).toBe(false);
  });

  it("confirms before deleting a Price Book Entry", async () => {
    LightningConfirm.open.mockResolvedValue(true);
    deleteEntry.mockResolvedValue();
    const element = await mount();
    const table = element.shadowRoot.querySelector("lightning-datatable");

    table.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: {
          action: { name: "delete" },
          row: { Id: ENTRY_ID, Product2Id: "Appeal Service" }
        }
      })
    );
    await flushPromises();

    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({
        label: "Delete Price Book Entry",
        theme: "warning"
      })
    );
    expect(deleteEntry).toHaveBeenCalledWith({
      pricebookId: PRICEBOOK_ID,
      entryId: ENTRY_ID
    });
  });

  it("hides mutation actions without Price Book Entry permissions", async () => {
    const element = createElement("c-pricebook-entry-table", {
      is: PricebookEntryTable
    });
    element.recordId = PRICEBOOK_ID;
    document.body.appendChild(element);
    getEntries.emit({
      fields: [],
      rows: [],
      paymentTypes: [],
      canCreateEntries: false,
      canUpdateEntries: false,
      canDeleteEntries: false
    });
    await flushPromises();

    expect(button(element, "Add Products").disabled).toBe(true);
    expect(button(element, "Edit").disabled).toBe(true);
  });
});
