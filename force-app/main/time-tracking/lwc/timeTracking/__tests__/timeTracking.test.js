import { createElement } from "lwc";
import TimeTracking from "c/timeTracking";
import { refreshApex } from "@salesforce/apex";
import getTimeTrackingData from "@salesforce/apex/TimeTrackingController.getTimeTrackingData";
import startTimer from "@salesforce/apex/TimeTrackingController.startTimer";
import completeTimer from "@salesforce/apex/TimeTrackingController.completeTimer";
import createManualEntry from "@salesforce/apex/TimeTrackingController.createManualEntry";

jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/TimeTrackingController.getTimeTrackingData",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimeTrackingController.startTimer",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimeTrackingController.completeTimer",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimeTrackingController.createManualEntry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimeTrackingController.updateTimeTracking",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimeTrackingController.deleteTimeTracking",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const RECORD_ID = "500000000000001AAA";
const OTHER_RECORD_ID = "500000000000002AAA";
const NOW = new Date("2026-11-05T02:00:00.000Z").getTime();
const COMPLETED_RECORDS = [
  {
    id: "a0T000000000001AAA",
    assigneeName: "Test User",
    startTime: "2026-11-05T01:00:00.000Z",
    endTime: "2026-11-05T01:15:00.000Z",
    durationMinutes: 15,
    status: "Completed",
    comments: "First entry"
  },
  {
    id: "a0T000000000002AAA",
    assigneeName: "Test User",
    startTime: "2026-11-05T01:20:00.000Z",
    endTime: "2026-11-05T01:40:00.000Z",
    durationMinutes: 20,
    status: "Completed",
    comments: "Second entry"
  }
];
const ACTIVE_TIMER = {
  id: "a0T000000000003AAA",
  assigneeName: "Test User",
  startTime: "2026-11-05T01:55:00.000Z",
  durationMinutes: 5,
  status: "In progress",
  relatedRecordId: RECORD_ID,
  relatedRecordName: "00000123"
};
const BLOCKING_TIMER = {
  ...ACTIVE_TIMER,
  id: "a0T000000000004AAA",
  relatedRecordId: OTHER_RECORD_ID,
  relatedRecordName: "00000456"
};
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function trackingData(overrides = {}) {
  return {
    records: COMPLETED_RECORDS,
    activeTimer: null,
    blockingTimer: null,
    totalMinutes: 35,
    objectType: "Case",
    isAdmin: false,
    ...overrides
  };
}

async function mount(data = trackingData()) {
  const element = createElement("c-time-tracking", { is: TimeTracking });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  await flushPromises();
  if (data !== null) {
    getTimeTrackingData.emit(data);
    await flushPromises();
  }
  return element;
}

function actions(element) {
  return [
    ...element.shadowRoot
      .querySelector("lightning-card")
      .querySelectorAll('[slot="actions"]')
  ].find((slot) => slot.querySelector("lightning-button-icon"));
}

function iconButton(element, alternativeText) {
  return headerButtons(element).find(
    (button) =>
      (button.alternativeText || button.getAttribute("aria-label")) ===
      alternativeText
  );
}

function headerButtons(element) {
  return [
    ...actions(element).querySelectorAll(
      'lightning-button-icon, button[data-action="stop"]'
    )
  ];
}

function modalButton(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (button) => button.label === label
  );
}

function accordion(element) {
  return element.shadowRoot.querySelector("lightning-accordion");
}

function badge(element) {
  return element.shadowRoot.querySelector(
    "lightning-accordion-section lightning-badge"
  );
}

async function clickIcon(element, alternativeText) {
  iconButton(element, alternativeText).click();
  await flushPromises();
}

async function setManualField(element, field, value) {
  const input = element.shadowRoot.querySelector(`[data-field="${field}"]`);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
  await flushPromises();
}

describe("c-time-tracking", () => {
  beforeEach(() => {
    jest.spyOn(Date, "now").mockReturnValue(NOW);
    refreshApex.mockReset();
    refreshApex.mockResolvedValue();
    startTimer.mockReset();
    startTimer.mockResolvedValue({ success: true });
    completeTimer.mockReset();
    completeTimer.mockResolvedValue();
    createManualEntry.mockReset();
    createManualEntry.mockResolvedValue("a0T000000000005AAA");
  });

  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.restoreAllMocks();
  });

  it("keeps every header action disabled until the initial data is loaded", async () => {
    const element = await mount(null);
    const buttons = actions(element).querySelectorAll("lightning-button-icon");
    expect(buttons).toHaveLength(3);
    buttons.forEach((button) => expect(button.disabled).toBe(true));
    expect(startTimer).not.toHaveBeenCalled();
    expect(refreshApex).not.toHaveBeenCalled();
  });

  it("places accessible play, add, and refresh icons in the card action slot", async () => {
    const element = await mount();
    const expected = [
      ["Start timer", "utility:play"],
      ["Add manual entry", "utility:add"],
      ["Refresh time tracking", "utility:refresh"]
    ];
    expected.forEach(([label, icon]) => {
      const button = iconButton(element, label);
      expect(button).toBeDefined();
      expect(button.iconName).toBe(icon);
      expect(button.title).toBe(label);
      expect(button.disabled).toBe(false);
    });
    expect(iconButton(element, "Start timer").variant).toBe("brand");
    expect(element.shadowRoot.querySelector("lightning-button")).toBeNull();
  });

  it("starts with logged time collapsed and shows the number of records in the section badge", async () => {
    const element = await mount();
    const section = element.shadowRoot.querySelector(
      "lightning-accordion-section"
    );
    expect(accordion(element).allowMultipleSectionsOpen).toBe(true);
    expect(accordion(element).activeSectionName).toEqual([]);
    expect(section.name).toBe("logged-time");
    expect(section.label).toBe("Logged Time");
    expect(String(badge(element).label)).toBe("2");
    expect(badge(element).getAttribute("slot")).toBe("actions");
    expect(section.querySelector("lightning-datatable").data).toHaveLength(2);
  });

  it("keeps the logged total inside Logged Time and hides the summary when no timer is running", async () => {
    const element = await mount();
    const section = element.shadowRoot.querySelector(
      "lightning-accordion-section"
    );
    expect(section.querySelector(".logged-total").textContent).toBe(
      "Total logged time: 0d 0h 35m"
    );
    expect(element.shadowRoot.querySelector(".tracking-summary")).toBeNull();
    expect(element.shadowRoot.querySelector(".timer-display")).toBeNull();
    expect(element.shadowRoot.textContent).not.toContain("No timer running");
    expect(element.shadowRoot.textContent).not.toContain("Total Minutes:");
    expect(String(badge(element).label)).toBe("2");
    expect(accordion(element).activeSectionName).toEqual([]);
  });

  it.each(["current", "other"])(
    "shows the summary when a %s timer appears and hides it when that timer ends",
    async (timerLocation) => {
      const element = await mount();
      const isCurrent = timerLocation === "current";
      expect(element.shadowRoot.querySelector(".tracking-summary")).toBeNull();

      getTimeTrackingData.emit(
        trackingData({
          activeTimer: isCurrent ? ACTIVE_TIMER : null,
          blockingTimer: isCurrent ? null : BLOCKING_TIMER,
          records: isCurrent
            ? [...COMPLETED_RECORDS, ACTIVE_TIMER]
            : COMPLETED_RECORDS,
          totalMinutes: isCurrent ? 40 : 35
        })
      );
      await flushPromises();
      expect(
        element.shadowRoot.querySelector(".tracking-summary")
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector(".timer-display").textContent
      ).toBe("0d 0h 5m");
      expect(
        Boolean(element.shadowRoot.querySelector(".other-record-badge"))
      ).toBe(!isCurrent);

      getTimeTrackingData.emit(trackingData());
      await flushPromises();
      expect(element.shadowRoot.querySelector(".tracking-summary")).toBeNull();
      expect(element.shadowRoot.querySelector(".timer-display")).toBeNull();
      expect(
        element.shadowRoot.querySelector(".blocking-timer-notice")
      ).toBeNull();
      expect(element.shadowRoot.textContent).not.toContain("No timer running");
      expect(
        element.shadowRoot.querySelector(".logged-total").textContent
      ).toBe("Total logged time: 0d 0h 35m");
      expect(String(badge(element).label)).toBe("2");
      expect(iconButton(element, "Start timer")).toBeDefined();
      expect(accordion(element).activeSectionName).toEqual([]);
    }
  );

  it.each([
    [null, "0d 0h 0m"],
    [0, "0d 0h 0m"],
    [1 / 60, "0d 0h 1m"],
    [0.99, "0d 0h 1m"],
    [1, "0d 0h 1m"],
    [61 / 60, "0d 0h 2m"],
    [59.99, "0d 1h 0m"],
    [60, "0d 1h 0m"],
    [60 + 1 / 60, "0d 1h 1m"],
    [1440, "1d 0h 0m"],
    [1440 + 1 / 60, "1d 0h 1m"],
    [2945.75, "2d 1h 6m"]
  ])(
    "formats %s logged minutes as %s in the total and table",
    async (minutes, expected) => {
      const element = await mount(
        trackingData({
          records: [{ ...COMPLETED_RECORDS[0], durationMinutes: minutes }],
          totalMinutes: minutes
        })
      );
      const table = element.shadowRoot.querySelector("lightning-datatable");
      expect(table.columns).toContainEqual(
        expect.objectContaining({
          label: "Duration",
          fieldName: "durationDisplay"
        })
      );
      expect(table.data[0].durationDisplay).toBe(expected);
      expect(
        element.shadowRoot.querySelector(".logged-total").textContent
      ).toBe(`Total logged time: ${expected}`);
    }
  );

  it.each([
    [0, 0],
    [1, 1],
    [29, 1],
    [59, 1],
    [60, 1],
    [61, 2]
  ])("rounds %s elapsed seconds to %s minutes in the running timer and total", async (seconds, minutes) => {
    const timer = {
      ...ACTIVE_TIMER,
      startTime: new Date(NOW - seconds * 1000).toISOString(),
      durationMinutes: minutes
    };
    const element = await mount(
      trackingData({
        activeTimer: timer,
        records: [...COMPLETED_RECORDS, timer],
        totalMinutes: 35 + minutes
      })
    );
    expect(element.shadowRoot.querySelector(".timer-display").textContent).toBe(
      `0d 0h ${minutes}m`
    );
    expect(element.shadowRoot.querySelector(".logged-total").textContent).toBe(
      `Total logged time: 0d 0h ${35 + minutes}m`
    );
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data[2].durationDisplay
    ).toBe(`0d 0h ${minutes}m`);
  });

  it("keeps the manually opened accordion open when refreshed data changes the count and table", async () => {
    const element = await mount();
    accordion(element).dispatchEvent(
      new CustomEvent("sectiontoggle", {
        detail: { openSections: ["logged-time"] }
      })
    );
    await flushPromises();
    expect(accordion(element).activeSectionName).toEqual(["logged-time"]);

    refreshApex.mockImplementationOnce(async () => {
      getTimeTrackingData.emit(
        trackingData({
          records: [...COMPLETED_RECORDS, ACTIVE_TIMER],
          activeTimer: ACTIVE_TIMER,
          totalMinutes: 40
        })
      );
    });
    await clickIcon(element, "Refresh time tracking");
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(accordion(element).activeSectionName).toEqual(["logged-time"]);
    expect(String(badge(element).label)).toBe("3");
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data
    ).toHaveLength(3);
  });

  it("does not automatically open logged time when starting or refreshing a timer", async () => {
    const element = await mount();
    await clickIcon(element, "Start timer");
    expect(startTimer).toHaveBeenCalledWith({ recordId: RECORD_ID });
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(accordion(element).activeSectionName).toEqual([]);
    await clickIcon(element, "Refresh time tracking");
    expect(refreshApex).toHaveBeenCalledTimes(2);
    expect(accordion(element).activeSectionName).toEqual([]);
  });

  it("disables header actions while refreshing and only refreshes the existing wire result once", async () => {
    let finishRefresh;
    refreshApex.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finishRefresh = resolve;
        })
    );
    const data = trackingData({
      activeTimer: ACTIVE_TIMER,
      records: [...COMPLETED_RECORDS, ACTIVE_TIMER],
      totalMinutes: 40
    });
    const element = await mount(data);
    await clickIcon(element, "Refresh time tracking");
    expect(headerButtons(element)).toHaveLength(3);
    expect(iconButton(element, "Stop timer").disabled).toBe(true);
    headerButtons(element).forEach((button) =>
      expect(button.disabled).toBe(true)
    );
    expect(refreshApex).toHaveBeenCalledWith(expect.objectContaining({ data }));
    await clickIcon(element, "Refresh time tracking");
    expect(refreshApex).toHaveBeenCalledTimes(1);
    finishRefresh();
    await flushPromises();
    headerButtons(element).forEach((button) =>
      expect(button.disabled).toBe(false)
    );
  });

  it("reports refresh failures without losing the logged table and allows retrying", async () => {
    refreshApex.mockRejectedValueOnce({
      body: { message: "Refresh unavailable." }
    });
    const element = await mount();
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    await clickIcon(element, "Refresh time tracking");
    expect(toast).toHaveBeenCalledWith(
      expect.objectContaining({
        detail: expect.objectContaining({
          variant: "error",
          message: "Refresh unavailable."
        })
      })
    );
    expect(String(badge(element).label)).toBe("2");
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data
    ).toHaveLength(2);
    expect(iconButton(element, "Refresh time tracking").disabled).toBe(false);
    await clickIcon(element, "Refresh time tracking");
    expect(refreshApex).toHaveBeenCalledTimes(2);
  });

  it("shows the running timer with a Stop icon and keeps comments optional when stopping", async () => {
    const element = await mount(
      trackingData({
        activeTimer: ACTIVE_TIMER,
        records: [...COMPLETED_RECORDS, ACTIVE_TIMER],
        totalMinutes: 40
      })
    );
    expect(iconButton(element, "Start timer")).toBeUndefined();
    const stopButton = iconButton(element, "Stop timer");
    expect(stopButton.title).toBe("Stop timer");
    expect(stopButton.getAttribute("aria-label")).toBe("Stop timer");
    expect(stopButton.querySelector("lightning-icon").iconName).toBe(
      "utility:stop"
    );
    expect(element.shadowRoot.querySelector(".timer-display").textContent).toBe(
      "0d 0h 5m"
    );
    await clickIcon(element, "Stop timer");
    expect(
      element.shadowRoot.querySelector('[role="dialog"]').textContent
    ).toContain("Complete Timer");
    expect(element.shadowRoot.querySelector("lightning-textarea").label).toBe(
      "Comments (optional)"
    );
    expect(completeTimer).not.toHaveBeenCalled();
    modalButton(element, "OK").click();
    await flushPromises();
    expect(completeTimer).toHaveBeenCalledWith({
      timeTrackingId: ACTIVE_TIMER.id,
      comments: ""
    });
    expect(refreshApex).toHaveBeenCalledTimes(1);
  });

  it("opens and saves a manual entry from the plus icon", async () => {
    const element = await mount();
    await clickIcon(element, "Add manual entry");
    expect(
      element.shadowRoot.querySelector('[role="dialog"]').textContent
    ).toContain("Add Manual Time Entry");
    await setManualField(element, "manualDate", "2026-11-04");
    await setManualField(element, "manualStartTime", "09:00:00");
    await setManualField(element, "manualEndTime", "09:15:00");
    modalButton(element, "Save").click();
    await flushPromises();
    expect(createManualEntry).toHaveBeenCalledWith(
      expect.objectContaining({ recordId: RECORD_ID, comments: "" })
    );
    const request = createManualEntry.mock.calls[0][0];
    expect(
      new Date(request.endTime).getTime() -
        new Date(request.startTime).getTime()
    ).toBe(15 * 60 * 1000);
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
  });

  it("shows an existing timer on another record before Start is clicked without including it in this record's totals", async () => {
    const element = await mount(
      trackingData({ blockingTimer: BLOCKING_TIMER })
    );
    const notice = element.shadowRoot.querySelector(".blocking-timer-notice");
    expect(notice).not.toBeNull();
    const otherRecordBadge = notice.querySelector(".other-record-badge");
    expect(otherRecordBadge.tagName).toBe("A");
    expect(
      otherRecordBadge.querySelector(".other-record-label").textContent
    ).toBe(`Running on ${BLOCKING_TIMER.relatedRecordName}`);
    expect(otherRecordBadge.querySelector(".timer-display").textContent).toBe(
      "0d 0h 5m"
    );
    expect(notice.classList.contains("slds-box")).toBe(false);
    expect(notice.classList.contains("slds-theme_warning")).toBe(false);
    expect(otherRecordBadge.getAttribute("href")).toContain(OTHER_RECORD_ID);
    expect(otherRecordBadge.title).toContain(BLOCKING_TIMER.relatedRecordName);
    expect(
      element.shadowRoot.querySelectorAll(".tracking-summary .timer-display")
    ).toHaveLength(1);
    expect(element.shadowRoot.querySelector(".logged-total").textContent).toBe(
      "Total logged time: 0d 0h 35m"
    );
    expect(String(badge(element).label)).toBe("2");
    expect(startTimer).not.toHaveBeenCalled();
    await clickIcon(element, "Start timer");
    expect(startTimer).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="dialog"]').textContent
    ).toContain("Timer Already Running");
  });

  it("keeps the elapsed time and record name together when the other timer has no record link", async () => {
    const element = await mount(
      trackingData({
        blockingTimer: { ...BLOCKING_TIMER, relatedRecordId: null }
      })
    );
    const notice = element.shadowRoot.querySelector(".blocking-timer-notice");
    const otherRecordBadge = notice.querySelector(".other-record-badge");
    expect(otherRecordBadge.tagName).toBe("SPAN");
    expect(notice.querySelector("a")).toBeNull();
    expect(otherRecordBadge.querySelector(".timer-display").textContent).toBe(
      "0d 0h 5m"
    );
    expect(
      otherRecordBadge.querySelector(".other-record-label").textContent
    ).toBe(`Running on ${BLOCKING_TIMER.relatedRecordName}`);
    expect(
      element.shadowRoot.querySelectorAll(".tracking-summary .timer-display")
    ).toHaveLength(1);
  });

  it("shows independent elapsed times for this record and another record without combining their logged totals", async () => {
    const interval = jest.spyOn(window, "setInterval");
    const element = await mount(
      trackingData({
        activeTimer: ACTIVE_TIMER,
        blockingTimer: {
          ...BLOCKING_TIMER,
          startTime: "2026-11-05T01:35:00.000Z"
        },
        records: [...COMPLETED_RECORDS, ACTIVE_TIMER],
        totalMinutes: 40
      })
    );
    const summary = element.shadowRoot.querySelector(".tracking-summary");
    const currentTimer = [...summary.querySelectorAll(".timer-display")].filter(
      (timer) => !timer.closest(".other-record-badge")
    );
    const otherRecordBadge = summary.querySelector(".other-record-badge");
    expect(currentTimer).toHaveLength(1);
    expect(currentTimer[0].textContent).toBe("0d 0h 5m");
    expect(otherRecordBadge.querySelector(".timer-display").textContent).toBe(
      "0d 0h 25m"
    );
    expect(
      otherRecordBadge.querySelector(".other-record-label").textContent
    ).toBe(`Also running on ${BLOCKING_TIMER.relatedRecordName}`);
    expect(element.shadowRoot.querySelector(".logged-total").textContent).toBe(
      "Total logged time: 0d 0h 40m"
    );

    Date.now.mockReturnValue(NOW + 61 * 1000);
    interval.mock.calls[0][0]();
    await flushPromises();
    expect(currentTimer[0].textContent).toBe("0d 0h 7m");
    expect(otherRecordBadge.querySelector(".timer-display").textContent).toBe(
      "0d 0h 27m"
    );
    expect(element.shadowRoot.querySelector(".logged-total").textContent).toBe(
      "Total logged time: 0d 0h 42m"
    );
    expect(String(badge(element).label)).toBe("3");
    expect(accordion(element).activeSectionName).toEqual([]);
  });

  it("omits the other-record notice when the current record owns the active timer", async () => {
    const element = await mount(
      trackingData({
        activeTimer: ACTIVE_TIMER,
        records: [ACTIVE_TIMER],
        totalMinutes: 5
      })
    );
    expect(
      element.shadowRoot.querySelector(".blocking-timer-notice")
    ).toBeNull();
    expect(iconButton(element, "Stop timer")).toBeDefined();
  });

  it.each(["current", "other"])(
    "updates the running time on interval ticks for the %s record without mixing logged totals",
    async (timerLocation) => {
      const interval = jest.spyOn(window, "setInterval");
      const isCurrent = timerLocation === "current";
      const element = await mount(
        trackingData({
          activeTimer: isCurrent ? ACTIVE_TIMER : null,
          blockingTimer: isCurrent ? null : BLOCKING_TIMER,
          records: isCurrent
            ? [...COMPLETED_RECORDS, ACTIVE_TIMER]
            : COMPLETED_RECORDS,
          totalMinutes: isCurrent ? 40 : 35
        })
      );
      expect(
        element.shadowRoot.querySelector(".timer-display").textContent
      ).toBe("0d 0h 5m");
      Date.now.mockReturnValue(NOW + 61 * 1000);
      interval.mock.calls[0][0]();
      await flushPromises();
      expect(
        element.shadowRoot.querySelector(".timer-display").textContent
      ).toBe("0d 0h 7m");
      expect(
        element.shadowRoot.querySelector(".logged-total").textContent
      ).toBe(`Total logged time: 0d 0h ${isCurrent ? 42 : 35}m`);
      expect(String(badge(element).label)).toBe(isCurrent ? "3" : "2");
      expect(accordion(element).activeSectionName).toEqual([]);
    }
  );

  it("completes the blocking timer before starting time on the current record", async () => {
    const element = await mount(
      trackingData({ blockingTimer: BLOCKING_TIMER })
    );
    await clickIcon(element, "Start timer");
    modalButton(element, "Completed").click();
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[role="dialog"]').textContent
    ).toContain("Complete Existing Timer");
    modalButton(element, "OK").click();
    await flushPromises();
    expect(completeTimer).toHaveBeenCalledWith({
      timeTrackingId: BLOCKING_TIMER.id,
      comments: ""
    });
    expect(startTimer).toHaveBeenCalledWith({ recordId: RECORD_ID });
    expect(completeTimer.mock.invocationCallOrder[0]).toBeLessThan(
      startTimer.mock.invocationCallOrder[0]
    );
    expect(refreshApex).toHaveBeenCalledTimes(1);
  });
});
