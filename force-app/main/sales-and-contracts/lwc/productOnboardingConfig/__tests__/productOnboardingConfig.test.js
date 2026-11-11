import { createElement } from "lwc";
import ProductOnboardingConfig from "c/productOnboardingConfig";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import {
  getRecord,
  updateRecord,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";

const PRODUCT_ID = "01t000000000001AAA";
const CASE_ID = "500000000000001AAA";
const LAST_MODIFIED = "2026-11-03T20:00:00.000Z";
const CASE_FIELDS = {
  Subject: { apiName: "Subject", label: "Subject" },
  Description: { apiName: "Description", label: "Description" },
  Status: { apiName: "Status", label: "Status" }
};
const SAVED_ROWS = [
  { fieldapiname: "Subject", fieldlabel: "Issue", required: true },
  { fieldapiname: "Description", fieldlabel: "", required: false }
];
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function record(
  value,
  lastModified = LAST_MODIFIED,
  id = PRODUCT_ID,
  objectApiName = "Product2"
) {
  return {
    apiName: objectApiName,
    id,
    fields: {
      [objectApiName === "Case"
        ? "Case_Onboarding__c"
        : "Onboarding_Config__c"]: { value },
      LastModifiedDate: { value: lastModified }
    }
  };
}

function emitObjectInfo({
  objectApiName = "Product2",
  updateable = true,
  fieldUpdateable = true,
  maxLength = 32768
} = {}) {
  const configApiName =
    objectApiName === "Case" ? "Case_Onboarding__c" : "Onboarding_Config__c";
  const hostFields = {
    ...(objectApiName === "Case" ? CASE_FIELDS : {}),
    [configApiName]: {
      apiName: configApiName,
      label: "Onboarding configuration",
      updateable: fieldUpdateable,
      length: maxLength
    }
  };
  if (objectApiName !== "Case") {
    getObjectInfo.emit(
      { apiName: "Case", fields: CASE_FIELDS },
      (config) =>
        (config.objectApiName.objectApiName || config.objectApiName) === "Case"
    );
  }
  getObjectInfo.emit(
    { apiName: objectApiName, updateable, fields: hostFields },
    (config) =>
      (config.objectApiName.objectApiName || config.objectApiName) ===
      objectApiName
  );
}

async function mount({
  rows = SAVED_ROWS,
  rawValue,
  objectApiName = "Product2",
  updateable = true,
  fieldUpdateable = true,
  maxLength = 32768
} = {}) {
  const element = createElement("c-product-onboarding-config", {
    is: ProductOnboardingConfig
  });
  if (objectApiName !== "Product2") element.objectApiName = objectApiName;
  const recordId = objectApiName === "Case" ? CASE_ID : PRODUCT_ID;
  element.recordId = recordId;
  document.body.appendChild(element);
  await flushPromises();
  emitObjectInfo({ objectApiName, updateable, fieldUpdateable, maxLength });
  getRecord.emit(
    record(
      rawValue === undefined ? JSON.stringify(rows) : rawValue,
      LAST_MODIFIED,
      recordId,
      objectApiName
    )
  );
  await flushPromises();
  return element;
}

function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (item) => item.label === label
  );
}

async function click(element, label) {
  button(element, label).click();
  await flushPromises();
}

function editorRows(element) {
  return [...element.shadowRoot.querySelectorAll(".editor-row")];
}

function selectedFields(element) {
  return [...element.shadowRoot.querySelectorAll("lightning-combobox")].map(
    (input) => input.value
  );
}

async function selectField(element, index, value) {
  element.shadowRoot
    .querySelectorAll("lightning-combobox")
    [index].dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await flushPromises();
}

function rowInput(element, rowIndex, type) {
  return [
    ...editorRows(element)[rowIndex].querySelectorAll("lightning-input")
  ].find((input) => input.type === type);
}

function removeFirstRow(element) {
  [...editorRows(element)[0].querySelectorAll("lightning-button-icon")]
    .find((input) => input.iconName === "utility:delete")
    .click();
}

async function changeInput(element, rowIndex, type, value) {
  const input = rowInput(element, rowIndex, type);
  if (type === "checkbox") input.checked = value;
  else input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
  await flushPromises();
}

async function save(element) {
  element.shadowRoot
    .querySelectorAll("lightning-input, lightning-combobox")
    .forEach((input) => {
      input.reportValidity = jest.fn().mockReturnValue(true);
    });
  await click(element, "Save");
}

function savedJson() {
  return JSON.parse(updateRecord.mock.calls[0][0].fields.Onboarding_Config__c);
}

function dragEvent(type, dataTransfer) {
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.defineProperty(event, "dataTransfer", { value: dataTransfer });
  return event;
}

describe("c-product-onboarding-config", () => {
  beforeEach(() => {
    updateRecord.mockReset();
    updateRecord.mockResolvedValue({ id: PRODUCT_ID });
    notifyRecordUpdateAvailable.mockReset();
    notifyRecordUpdateAvailable.mockResolvedValue();
  });

  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.restoreAllMocks();
  });

  it("defaults to a detail card with override labels, Case label fallback, required flags, and an action-slot Edit button", async () => {
    const element = await mount();
    const rows = element.shadowRoot.querySelectorAll(".detail-row");
    expect(element.shadowRoot.querySelector("lightning-card").title).toBe(
      "Case Onboarding Fields"
    );
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("Issue");
    expect(rows[0].textContent).toContain("Subject");
    expect(rows[0].textContent).toContain("Required");
    expect(rows[1].textContent).toContain("Description");
    expect(rows[1].textContent).toContain("Optional");
    expect(button(element, "Edit").disabled).toBe(false);
    expect(button(element, "Edit").parentElement.getAttribute("slot")).toBe(
      "actions"
    );
    expect(element.shadowRoot.querySelector("lightning-combobox")).toBeNull();
    expect(updateRecord).not.toHaveBeenCalled();
  });

  it("switches the card body into an inline editor without opening a modal", async () => {
    const element = await mount();
    await click(element, "Edit");
    expect(editorRows(element)).toHaveLength(2);
    expect(element.shadowRoot.querySelector(".detail-row")).toBeNull();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
    expect(button(element, "Save")).toBeDefined();
    expect(button(element, "Cancel")).toBeDefined();
    expect(button(element, "Add Field")).toBeDefined();
  });

  it("saves exact JSON properties with changed labels, required flags, and the edited order", async () => {
    const element = await mount();
    await click(element, "Edit");
    await changeInput(element, 0, "text", "  Customer issue  ");
    await changeInput(element, 1, "checkbox", true);
    editorRows(element)[0].querySelector('[data-direction="1"]').click();
    await flushPromises();
    await save(element);
    expect(updateRecord).toHaveBeenCalledTimes(1);
    expect(updateRecord.mock.calls[0][0].fields.Id).toBe(PRODUCT_ID);
    expect(savedJson()).toEqual([
      { fieldapiname: "Description", fieldlabel: "", required: true },
      { fieldapiname: "Subject", fieldlabel: "Customer issue", required: true }
    ]);
    expect(button(element, "Edit")).toBeDefined();
    expect(
      element.shadowRoot.querySelector(".detail-row").textContent
    ).toContain("Description");
  });

  it("persists the order produced by dragging a handle onto another row", async () => {
    const element = await mount();
    await click(element, "Edit");
    const rows = editorRows(element);
    const dataTransfer = { setData: jest.fn() };
    rows[0]
      .querySelector(".drag-handle")
      .dispatchEvent(dragEvent("dragstart", dataTransfer));
    const dragOver = dragEvent("dragover", dataTransfer);
    rows[1].dispatchEvent(dragOver);
    expect(dragOver.defaultPrevented).toBe(true);
    expect(dataTransfer.effectAllowed).toBe("move");
    expect(dataTransfer.dropEffect).toBe("move");
    rows[1].dispatchEvent(dragEvent("drop", dataTransfer));
    await flushPromises();
    expect(selectedFields(element)).toEqual(["Description", "Subject"]);
    await save(element);
    expect(savedJson().map((row) => row.fieldapiname)).toEqual([
      "Description",
      "Subject"
    ]);
  });

  it("adds multiple fields, excludes fields selected in other rows, and makes a removed field available again", async () => {
    const element = await mount({ rows: [] });
    await click(element, "Edit");
    await click(element, "Add Field");
    await selectField(element, 0, "Subject");
    await click(element, "Add Field");
    const secondField =
      element.shadowRoot.querySelectorAll("lightning-combobox")[1];
    expect(secondField.options.map((option) => option.value)).toEqual([
      "Description",
      "Status"
    ]);
    await selectField(element, 1, "Description");
    removeFirstRow(element);
    await flushPromises();
    expect(selectedFields(element)).toEqual(["Description"]);
    expect(
      element.shadowRoot
        .querySelector("lightning-combobox")
        .options.map((option) => option.value)
    ).toContain("Subject");
    await save(element);
    expect(savedJson()).toEqual([
      { fieldapiname: "Description", fieldlabel: "", required: false }
    ]);
  });

  it("rejects duplicate selections even when a change event bypasses the filtered picker options", async () => {
    const element = await mount();
    await click(element, "Edit");
    await selectField(element, 1, "Subject");
    await save(element);
    expect(updateRecord).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("different Case field");
    expect(editorRows(element)).toHaveLength(2);
  });

  it("cancels edits and restores the saved detail view without persistence", async () => {
    const element = await mount();
    await click(element, "Edit");
    await changeInput(element, 0, "text", "Discard this draft");
    await click(element, "Add Field");
    await click(element, "Cancel");
    expect(updateRecord).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain("Issue");
    expect(element.shadowRoot.textContent).not.toContain("Discard this draft");
    await click(element, "Edit");
    expect(editorRows(element)).toHaveLength(2);
    expect(rowInput(element, 0, "text").value).toBe("Issue");
  });

  it.each([
    ["malformed JSON", "{broken"],
    ["a non-array value", '{"fieldapiname":"Subject"}'],
    [
      "a required flag with the wrong type",
      '[{"fieldapiname":"Subject","fieldlabel":"Issue","required":"true"}]'
    ],
    ["duplicate saved fields", JSON.stringify([SAVED_ROWS[0], SAVED_ROWS[0]])]
  ])(
    "blocks editing %s to prevent overwriting invalid stored data",
    async (_label, rawValue) => {
      const element = await mount({ rawValue });
      expect(
        element.shadowRoot.querySelector('[role="alert"]').textContent
      ).toContain("saved onboarding configuration is invalid");
      expect(button(element, "Edit").disabled).toBe(true);
      await click(element, "Edit");
      expect(editorRows(element)).toHaveLength(0);
      expect(updateRecord).not.toHaveBeenCalled();
    }
  );

  it.each([
    { updateable: false, fieldUpdateable: true },
    { updateable: true, fieldUpdateable: false }
  ])(
    "shows a read-only configuration when Product or field update access is absent (%j)",
    async (permissions) => {
      const element = await mount(permissions);
      expect(button(element, "Edit").disabled).toBe(true);
      expect(element.shadowRoot.textContent).toContain("read-only access");
      expect(element.shadowRoot.querySelectorAll(".detail-row")).toHaveLength(
        2
      );
      await click(element, "Edit");
      expect(editorRows(element)).toHaveLength(0);
      expect(updateRecord).not.toHaveBeenCalled();
    }
  );

  it("keeps edited values available after a failed save and allows retrying", async () => {
    updateRecord.mockRejectedValueOnce({
      body: { message: "Validation rule rejected the update." }
    });
    const element = await mount();
    await click(element, "Edit");
    await changeInput(element, 0, "text", "Keep this draft");
    await save(element);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Validation rule rejected");
    expect(rowInput(element, 0, "text").value).toBe("Keep this draft");
    expect(button(element, "Save").disabled).toBe(false);
    await save(element);
    expect(updateRecord).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
    expect(element.shadowRoot.textContent).toContain("Keep this draft");
  });

  it("stores an empty array after all configured fields are removed", async () => {
    const element = await mount();
    await click(element, "Edit");
    for (let remaining = 2; remaining > 0; remaining--) {
      removeFirstRow(element);
      await flushPromises();
    }
    await save(element);
    expect(updateRecord.mock.calls[0][0].fields.Onboarding_Config__c).toBe(
      "[]"
    );
    expect(element.shadowRoot.textContent).toContain(
      "No Case fields configured."
    );
  });

  it("loads a blank configuration as an empty list", async () => {
    const element = await mount({ rawValue: null });
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
    expect(element.shadowRoot.textContent).toContain(
      "No Case fields configured."
    );
    await click(element, "Edit");
    await save(element);
    expect(savedJson()).toEqual([]);
  });

  it("displays and preserves a saved Case field that is no longer available", async () => {
    const staleRow = {
      fieldapiname: "Retired_Field__c",
      fieldlabel: "",
      required: true
    };
    const element = await mount({ rows: [staleRow] });
    expect(
      element.shadowRoot.querySelector(".detail-row").textContent
    ).toContain("Retired_Field__c");
    await click(element, "Edit");
    expect(element.shadowRoot.textContent).toContain("will be preserved");
    expect(
      element.shadowRoot.querySelector("lightning-combobox").options
    ).toContainEqual({
      label: "Retired_Field__c (unavailable)",
      value: "Retired_Field__c"
    });
    await save(element);
    expect(savedJson()).toEqual([staleRow]);
  });

  it("uses the timestamp from when editing began even if record data refreshes during editing", async () => {
    const element = await mount();
    await click(element, "Edit");
    await changeInput(element, 0, "text", "My draft");
    getRecord.emit(
      record(JSON.stringify(SAVED_ROWS), "2026-11-03T20:05:00.000Z")
    );
    await flushPromises();
    await save(element);
    expect(updateRecord).toHaveBeenCalledWith(
      expect.objectContaining({
        fields: expect.objectContaining({ Id: PRODUCT_ID })
      }),
      { ifUnmodifiedSince: LAST_MODIFIED }
    );
    expect(savedJson()[0].fieldlabel).toBe("My draft");
  });

  it("reports a concurrent update conflict while preserving unsaved edits", async () => {
    updateRecord.mockRejectedValueOnce({ status: 412 });
    const element = await mount();
    await click(element, "Edit");
    await changeInput(element, 0, "text", "Unsaved local change");
    await save(element);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("changed by another user");
    expect(rowInput(element, 0, "text").value).toBe("Unsaved local change");
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: PRODUCT_ID }
    ]);
  });

  it("refreshes conflicted server data before the user cancels and edits again", async () => {
    const latestDate = "2026-11-03T20:10:00.000Z";
    const serverRows = [
      {
        fieldapiname: "Status",
        fieldlabel: "Latest server label",
        required: false
      }
    ];
    updateRecord.mockRejectedValueOnce({ status: 412 });
    notifyRecordUpdateAvailable.mockImplementationOnce(async () => {
      getRecord.emit(record(JSON.stringify(serverRows), latestDate));
    });
    const element = await mount();
    await click(element, "Edit");
    await changeInput(element, 0, "text", "Local draft");
    await save(element);
    expect(rowInput(element, 0, "text").value).toBe("Local draft");
    await click(element, "Cancel");
    expect(
      element.shadowRoot.querySelector(".detail-row").textContent
    ).toContain("Latest server label");
    await click(element, "Edit");
    await save(element);
    expect(updateRecord.mock.calls[1][1]).toEqual({
      ifUnmodifiedSince: latestDate
    });
    expect(
      JSON.parse(updateRecord.mock.calls[1][0].fields.Onboarding_Config__c)
    ).toEqual(serverRows);
  });

  it("ignores completion of an old save after navigating from Product A to B and back to A", async () => {
    let finishOldSave;
    updateRecord.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finishOldSave = resolve;
        })
    );
    const element = await mount();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    await click(element, "Edit");
    await changeInput(element, 0, "text", "Old in-flight draft");
    await save(element);
    expect(button(element, "Save").disabled).toBe(true);
    expect(button(element, "Cancel").disabled).toBe(true);
    expect(
      element.shadowRoot.querySelector("lightning-combobox").disabled
    ).toBe(true);

    element.recordId = "01t000000000002AAA";
    await flushPromises();
    getRecord.emit(record("[]", LAST_MODIFIED, element.recordId));
    await flushPromises();
    element.recordId = PRODUCT_ID;
    await flushPromises();
    getRecord.emit(record(JSON.stringify(SAVED_ROWS)));
    await flushPromises();
    await click(element, "Edit");
    await changeInput(element, 0, "text", "New current draft");
    finishOldSave({ id: PRODUCT_ID });
    await flushPromises();
    expect(rowInput(element, 0, "text").value).toBe("New current draft");
    expect(button(element, "Save").disabled).toBe(false);
    expect(toastHandler).not.toHaveBeenCalled();
  });

  it("blocks persistence when a base input reports invalid values", async () => {
    const element = await mount();
    await click(element, "Edit");
    element.shadowRoot
      .querySelectorAll("lightning-input, lightning-combobox")
      .forEach((input) => {
        input.reportValidity = jest.fn().mockReturnValue(true);
      });
    element.shadowRoot.querySelector("lightning-combobox").reportValidity = jest
      .fn()
      .mockReturnValue(false);
    await click(element, "Save");
    expect(updateRecord).not.toHaveBeenCalled();
    expect(editorRows(element)).toHaveLength(2);
  });

  it("rejects a configuration that exceeds the Product field storage limit", async () => {
    const element = await mount({ maxLength: 10 });
    await click(element, "Edit");
    await save(element);
    expect(updateRecord).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("field limit of 10 characters");
  });

  describe("Case record pages", () => {
    it("loads and edits Case onboarding without needing Product metadata", async () => {
      const element = await mount({ objectApiName: "Case" });
      const fields = getRecord
        .getLastConfig()
        .fields.map((field) =>
          typeof field === "string"
            ? field
            : `${field.objectApiName}.${field.fieldApiName}`
        );
      expect(fields).toEqual(
        expect.arrayContaining([
          "Case.Case_Onboarding__c",
          "Case.LastModifiedDate"
        ])
      );
      expect(fields).not.toContain("Product2.Onboarding_Config__c");
      expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
      expect(element.shadowRoot.querySelectorAll(".detail-row")).toHaveLength(
        2
      );
      expect(element.shadowRoot.textContent).toContain("Issue");
      expect(button(element, "Edit").disabled).toBe(false);
      await click(element, "Edit");
      expect(editorRows(element)).toHaveLength(2);
    });

    it("saves edits only to Case_Onboarding__c with the Case edit timestamp", async () => {
      const element = await mount({ objectApiName: "Case" });
      await click(element, "Edit");
      await changeInput(element, 0, "text", "  Case-specific issue  ");
      await changeInput(element, 1, "checkbox", true);
      editorRows(element)[0].querySelector('[data-direction="1"]').click();
      getRecord.emit(
        record(
          JSON.stringify(SAVED_ROWS),
          "2026-11-03T20:05:00.000Z",
          CASE_ID,
          "Case"
        )
      );
      await flushPromises();
      await save(element);
      expect(updateRecord).toHaveBeenCalledTimes(1);
      const savedRows = [
        { fieldapiname: "Description", fieldlabel: "", required: true },
        {
          fieldapiname: "Subject",
          fieldlabel: "Case-specific issue",
          required: true
        }
      ];
      expect(updateRecord).toHaveBeenCalledWith(
        {
          fields: {
            Id: CASE_ID,
            Case_Onboarding__c: JSON.stringify(savedRows)
          }
        },
        { ifUnmodifiedSince: LAST_MODIFIED }
      );
      expect(element.shadowRoot.querySelector("lightning-combobox")).toBeNull();
      expect(element.shadowRoot.textContent).toContain("Case-specific issue");
    });

    it.each([
      { updateable: false, fieldUpdateable: true },
      { updateable: true, fieldUpdateable: false }
    ])(
      "blocks editing when Case or Case_Onboarding__c is read-only (%j)",
      async (permissions) => {
        const element = await mount({ objectApiName: "Case", ...permissions });
        expect(button(element, "Edit").disabled).toBe(true);
        expect(element.shadowRoot.textContent).toContain("read-only access");
        expect(element.shadowRoot.querySelectorAll(".detail-row")).toHaveLength(
          2
        );
        await click(element, "Edit");
        expect(editorRows(element)).toHaveLength(0);
        expect(updateRecord).not.toHaveBeenCalled();
      }
    );

    it("checks the Case field storage limit before saving", async () => {
      const element = await mount({ objectApiName: "Case", maxLength: 10 });
      await click(element, "Edit");
      await save(element);
      expect(updateRecord).not.toHaveBeenCalled();
      expect(
        element.shadowRoot.querySelector('[role="alert"]').textContent
      ).toContain("field limit of 10 characters");
    });

    it("identifies Case_Onboarding__c when saved Case JSON is invalid", async () => {
      const element = await mount({
        objectApiName: "Case",
        rawValue: "{broken"
      });
      const message =
        element.shadowRoot.querySelector('[role="alert"]').textContent;
      expect(message).toContain("saved onboarding configuration is invalid");
      expect(message).toContain("Case_Onboarding__c");
      expect(message).not.toContain("Correct Onboarding_Config__c");
      expect(button(element, "Edit").disabled).toBe(true);
      expect(updateRecord).not.toHaveBeenCalled();
    });

    it("refreshes a conflicting Case while retaining the draft, then saves the latest configuration", async () => {
      const latestDate = "2026-11-03T20:10:00.000Z";
      const serverRows = [
        {
          fieldapiname: "Status",
          fieldlabel: "Updated Case setting",
          required: false
        }
      ];
      updateRecord.mockRejectedValueOnce({ status: 412 });
      notifyRecordUpdateAvailable.mockImplementationOnce(async () => {
        getRecord.emit(
          record(JSON.stringify(serverRows), latestDate, CASE_ID, "Case")
        );
      });
      const element = await mount({ objectApiName: "Case" });
      await click(element, "Edit");
      await changeInput(element, 0, "text", "Unsaved Case draft");
      await save(element);
      expect(
        element.shadowRoot.querySelector('[role="alert"]').textContent
      ).toContain("This Case was changed by another user");
      expect(rowInput(element, 0, "text").value).toBe("Unsaved Case draft");
      expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
        { recordId: CASE_ID }
      ]);
      await click(element, "Cancel");
      expect(element.shadowRoot.textContent).toContain("Updated Case setting");
      await click(element, "Edit");
      await save(element);
      expect(updateRecord.mock.calls[1]).toEqual([
        {
          fields: {
            Id: CASE_ID,
            Case_Onboarding__c: JSON.stringify(serverRows)
          }
        },
        { ifUnmodifiedSince: latestDate }
      ]);
    });

    it("uses Case messaging when reloading after a conflict fails", async () => {
      updateRecord.mockRejectedValueOnce({ status: 412 });
      notifyRecordUpdateAvailable.mockRejectedValueOnce({
        body: { message: "Reload unavailable." }
      });
      const element = await mount({ objectApiName: "Case" });
      await click(element, "Edit");
      await save(element);
      expect(
        element.shadowRoot.querySelector('[role="alert"]').textContent
      ).toContain("Unable to reload this Case");
      expect(
        element.shadowRoot.querySelector('[role="alert"]').textContent
      ).toContain("Reload unavailable.");
      expect(editorRows(element)).toHaveLength(2);
    });

    it("resets Product edits on Case navigation and ignores the old Product save completion", async () => {
      let finishOldSave;
      updateRecord.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            finishOldSave = resolve;
          })
      );
      const element = await mount();
      const toastHandler = jest.fn();
      element.addEventListener("lightning__showtoast", toastHandler);
      await click(element, "Edit");
      await changeInput(element, 0, "text", "Old Product draft");
      await save(element);

      element.objectApiName = "Case";
      element.recordId = CASE_ID;
      await flushPromises();
      expect(editorRows(element)).toHaveLength(0);
      expect(button(element, "Edit").disabled).toBe(true);
      emitObjectInfo({ objectApiName: "Case" });
      getRecord.emit(
        record(JSON.stringify(SAVED_ROWS), LAST_MODIFIED, CASE_ID, "Case")
      );
      await flushPromises();
      await click(element, "Edit");
      await changeInput(element, 0, "text", "New Case draft");
      finishOldSave({ id: PRODUCT_ID });
      await flushPromises();
      expect(rowInput(element, 0, "text").value).toBe("New Case draft");
      expect(button(element, "Save").disabled).toBe(false);
      expect(toastHandler).not.toHaveBeenCalled();
      await save(element);
      expect(updateRecord.mock.calls[1][0].fields.Id).toBe(CASE_ID);
      expect(
        JSON.parse(updateRecord.mock.calls[1][0].fields.Case_Onboarding__c)[0]
          .fieldlabel
      ).toBe("New Case draft");
    });
  });
});
