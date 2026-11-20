import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getTimeTrackingData from '@salesforce/apex/TimeTrackingController.getTimeTrackingData';
import startTimer from '@salesforce/apex/TimeTrackingController.startTimer';
import pauseTimer from '@salesforce/apex/TimeTrackingController.pauseTimer';
import resumeTimer from '@salesforce/apex/TimeTrackingController.resumeTimer';
import heartbeat from '@salesforce/apex/TimeTrackingController.heartbeat';
import completeTimer from '@salesforce/apex/TimeTrackingController.completeTimer';
import deleteTimeTracking from '@salesforce/apex/TimeTrackingController.deleteTimeTracking';
import createManualEntry from '@salesforce/apex/TimeTrackingController.createManualEntry';
import updateTimeTracking from '@salesforce/apex/TimeTrackingController.updateTimeTracking';
import { subscribe, unsubscribe } from 'lightning/empApi';
import CURRENT_USER_ID from '@salesforce/user/Id';

const BASE_COLUMNS = [
    { label: 'Assignee', fieldName: 'assigneeName', type: 'text' },
    { label: 'Type', fieldName: 'type', type: 'text' },
    { label: 'Start Time', fieldName: 'formattedStartTime', type: 'text' },
    { label: 'End Time', fieldName: 'formattedEndTime', type: 'text' },
    { label: 'Duration', fieldName: 'durationDisplay', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Comments', fieldName: 'comments', type: 'text' }
];

const ADMIN_ACTIONS_COLUMN = {
    type: 'action',
    typeAttributes: {
        rowActions: [
            { label: 'Edit', name: 'edit' },
            { label: 'Delete', name: 'delete' }
        ]
    }
};

const STATUS_IN_PROGRESS = 'In progress';
const STATUS_PAUSED_LUNCH = 'Paused - Lunch/Break';
const STATUS_PAUSED_OFFLINE = 'Paused - Offline';
const PAUSED_STATUSES = [STATUS_PAUSED_LUNCH, STATUS_PAUSED_OFFLINE];

const TYPE_INTERNAL_MEETING = 'Internal Meeting';
const TYPE_INTERNAL_TASK = 'Internal Task';

const HEARTBEAT_INTERVAL_MS = 15000;
const INSTANCE_ID_STORAGE_KEY = 'timeTrackingInstanceId';
const UPDATE_EVENT_CHANNEL = '/event/TimeTracking_Update__e';

function generateInstanceId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
        return window.crypto.randomUUID();
    }
    return `tt-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function getOrCreateInstanceId() {
    try {
        let instanceId = window.localStorage.getItem(INSTANCE_ID_STORAGE_KEY);
        if (!instanceId) {
            instanceId = generateInstanceId();
            window.localStorage.setItem(INSTANCE_ID_STORAGE_KEY, instanceId);
        }
        return instanceId;
    } catch (error) {
        // Local storage can be unavailable (private browsing, etc.); fall back to a session-only id.
        return generateInstanceId();
    }
}

export default class TimeTracking extends LightningElement {
    @api recordId = null;

    @track tableData = [];
    @track activeTimer;
    @track blockingTimer;
    @track totalMinutes = 0;
    @track displayTotalMinutes = 0;
    @track elapsedDisplay = '0d 0h 0m';
    blockingElapsedDisplay = '0d 0h 0m';
    @track showCommentModal = false;
    @track showBlockingModal = false;
    @track showManualModal = false;
    @track showInternalTypeModal = false;
    @track modalComments = '';
    @track modalMode = '';
    @track selectedRecordId;
    @track isLoading = true;
    @track isProcessing = false;
    isRefreshing = false;
    activeSections = [];
    @track isAdmin = false;
    @track columns = BASE_COLUMNS;

    @track manualDate = '';
    @track manualStartTime = '';
    @track manualEndTime = '';
    @track manualComments = '';
    @track manualEditId;
    @track manualType = TYPE_INTERNAL_TASK;

    @track internalType = TYPE_INTERNAL_TASK;

    timerInterval;
    heartbeatInterval;
    wiredDataResult;
    instanceId = getOrCreateInstanceId();

    internalTypeOptions = [
        { label: 'Internal Meeting', value: TYPE_INTERNAL_MEETING },
        { label: 'Internal Task', value: TYPE_INTERNAL_TASK }
    ];

    @wire(getTimeTrackingData, { recordId: '$recordId' })
    wiredTimeTracking(result) {
        this.wiredDataResult = result;

        const { data, error } = result;
        if (data) {
            this.isLoading = false;
            this.activeTimer = data.activeTimer;
            this.blockingTimer = data.blockingTimer;
            this.totalMinutes = data.totalMinutes || 0;
            this.isAdmin = !!data.isAdmin;
            this.columns = this.isAdmin ? [...BASE_COLUMNS, ADMIN_ACTIONS_COLUMN] : BASE_COLUMNS;
            this.tableData = (data.records || []).map((record) => ({
                ...record,
                formattedStartTime: this.formatDateTime(record.startTime),
                formattedEndTime: this.formatDateTime(record.endTime),
                durationDisplay: this.formatDuration(record.durationMinutes)
            }));
            this.syncTimerDisplay();
            this.syncHeartbeat();
        } else if (error) {
            this.isLoading = false;
            this.tableData = [];
            this.activeTimer = null;
            this.blockingTimer = null;
            this.totalMinutes = 0;
            this.syncTimerDisplay();
            this.syncHeartbeat();
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    connectedCallback() {
        this.timerInterval = window.setInterval(() => {
            this.syncTimerDisplay();
        }, 1000);
        this.boundPageHideHandler = this.handlePageHide.bind(this);
        window.addEventListener('pagehide', this.boundPageHideHandler);
        this.subscribeToUpdateEvent();
    }

    disconnectedCallback() {
        if (this.timerInterval) {
            window.clearInterval(this.timerInterval);
        }
        this.stopHeartbeat();
        if (this.boundPageHideHandler) {
            window.removeEventListener('pagehide', this.boundPageHideHandler);
        }
        this.unsubscribeFromUpdateEvent();
    }

    subscribeToUpdateEvent() {
        subscribe(UPDATE_EVENT_CHANNEL, -1, (message) => {
            const payload = message?.data?.payload;
            if (!payload || payload.Assignee_Id__c !== CURRENT_USER_ID) {
                return;
            }
            // Note: instanceId is shared across every tab/window of this
            // browser (it lives in localStorage, by design, so a second
            // computer can be told apart from a second tab). That means it
            // cannot be used here to tell "this tab caused it" apart from
            // "a sibling tab caused it" - so every matching event refreshes,
            // even the tab that made the change. The extra refresh in that
            // one tab is harmless; skipping it risked silently dropping
            // updates for every other open tab/window, which is the whole
            // point of this subscription.
            if (this.wiredDataResult) {
                refreshApex(this.wiredDataResult).catch(() => {
                    // A transient refresh failure here just means this tab stays
                    // on slightly stale data until its next successful refresh.
                });
            }
        })
            .then((subscription) => {
                this.updateEventSubscription = subscription;
            })
            .catch(() => {
                // Cross-tab sync is a convenience; this component still works
                // correctly off its own wire data and the heartbeat/cleanup
                // backstop if the subscription cannot be established.
            });
    }

    unsubscribeFromUpdateEvent() {
        if (this.updateEventSubscription) {
            unsubscribe(this.updateEventSubscription, () => {});
            this.updateEventSubscription = null;
        }
    }

    handlePageHide() {
        // Best-effort only: browsers do not guarantee this request completes
        // once the page is being torn down, so the heartbeat/cleanup job
        // remains the authoritative backstop for an unresponsive tab.
        if (!this.isActiveTimerRunning || this.activeTimer.timerInstanceId !== this.instanceId) {
            return;
        }
        pauseTimer({
            timeTrackingId: this.activeTimer.id,
            pauseStatus: 'Paused - Offline',
            instanceId: this.instanceId
        }).catch(() => {
            // Nothing to do here; the page is already closing.
        });
    }

    get isUtilityBarContext() {
        return !this.recordId;
    }

    get hasActiveTimer() {
        return this.activeTimer != null;
    }

    get isActiveTimerRunning() {
        return this.hasActiveTimer && this.activeTimer.status === STATUS_IN_PROGRESS;
    }

    get isActiveTimerPaused() {
        return this.hasActiveTimer && PAUSED_STATUSES.includes(this.activeTimer.status);
    }

    get showStartButton() {
        return !this.hasActiveTimer;
    }

    get actionsDisabled() {
        return this.isLoading || this.isProcessing || this.isRefreshing;
    }

    get loggedRecordCount() {
        return this.tableData.length;
    }

    get loggedRecordCountLabel() {
        return `${this.loggedRecordCount} time tracking records`;
    }

    get hasBlockingTimer() {
        return this.blockingTimer != null;
    }

    get blockingTimerIsPaused() {
        return this.hasBlockingTimer && PAUSED_STATUSES.includes(this.blockingTimer.status);
    }

    get blockingRecordName() {
        if (!this.blockingTimer) {
            return 'another record';
        }
        return this.blockingTimer.relatedRecordName || (this.blockingTimer.type !== 'Client' ? 'an internal entry' : 'another record');
    }

    get blockingRecordUrl() {
        return this.blockingTimer?.relatedRecordId
            ? `/lightning/r/${this.blockingTimer.relatedRecordId}/view`
            : undefined;
    }

    get blockingTimerBadgeLabel() {
        const prefix = this.hasActiveTimer ? 'Also running on' : 'Running on';
        return `${prefix} ${this.blockingRecordName}`;
    }

    get blockingTimerBadgeDescription() {
        return `${this.blockingElapsedDisplay} ${this.blockingTimerBadgeLabel}`;
    }

    get showTimerSummary() {
        return this.hasActiveTimer || this.hasBlockingTimer;
    }

    handleSectionToggle(event) {
        this.activeSections = [...event.detail.openSections];
    }

    async handleRefresh() {
        if (this.actionsDisabled || !this.wiredDataResult) {
            return;
        }
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredDataResult);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isRefreshing = false;
        }
    }

    get formattedLoggedTime() {
        return this.formatDuration(this.displayTotalMinutes);
    }

    get modalTitle() {
        if (this.modalMode === 'blocking') {
            return 'Complete Existing Timer';
        }
        if (this.modalMode === 'complete') {
            return 'Complete Timer';
        }
        if (this.modalMode === 'delete') {
            return 'Delete Time Tracking';
        }
        return 'Comments';
    }

    get manualModalTitle() {
        return this.manualEditId ? 'Edit Time Tracking' : 'Add Manual Time Entry';
    }

    get blockingMessage() {
        if (this.blockingTimerIsPaused) {
            return `You have a paused timer on ${this.blockingRecordName}. Resume or complete it before starting a new timer here.`;
        }
        return `You have a timer running on ${this.blockingRecordName}. Complete it before starting a new timer here.`;
    }

    handleStartClick() {
        if (this.blockingTimer) {
            this.openBlockingModal();
            return;
        }

        if (this.isUtilityBarContext) {
            this.showInternalTypeModal = true;
            return;
        }

        this.runStartTimer();
    }

    handleInternalTypeChange(event) {
        this.internalType = event.target.value;
    }

    handleInternalTypeCancel() {
        this.showInternalTypeModal = false;
    }

    handleInternalTypeConfirm() {
        this.showInternalTypeModal = false;
        this.runStartTimer();
    }

    handleCompleteClick() {
        if (!this.activeTimer) {
            return;
        }
        this.openCommentModal('complete', this.activeTimer.id);
    }

    handlePauseClick(event) {
        const pauseStatus = event.currentTarget.dataset.status;
        if (!this.activeTimer || this.actionsDisabled) {
            return;
        }
        this.isProcessing = true;
        pauseTimer({ timeTrackingId: this.activeTimer.id, pauseStatus, instanceId: this.instanceId })
            .then(() => {
                this.showToast('Success', 'Timer paused.', 'success');
                return refreshApex(this.wiredDataResult);
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    handleResumeClick() {
        const timer = this.activeTimer || this.blockingTimer;
        if (!timer || this.actionsDisabled) {
            return;
        }
        this.isProcessing = true;
        resumeTimer({ timeTrackingId: timer.id, instanceId: this.instanceId, takeOver: true })
            .then(() => {
                this.showBlockingModal = false;
                this.showToast('Success', 'Timer resumed.', 'success');
                return refreshApex(this.wiredDataResult);
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    handleBlockingCompleteClick() {
        if (!this.blockingTimer) {
            return;
        }
        this.showBlockingModal = false;
        this.openCommentModal('blocking', this.blockingTimer.id);
    }

    handleBlockingCancelClick() {
        this.showBlockingModal = false;
    }

    handleCommentChange(event) {
        this.modalComments = event.target.value;
    }

    handleModalCancel() {
        this.closeCommentModal();
    }

    handleModalConfirm() {
        if (this.modalMode === 'complete' || this.modalMode === 'blocking') {
            this.runCompleteTimer();
            return;
        }

        if (this.modalMode === 'delete') {
            this.runDeleteTimeTracking();
        }
    }

    handleAddManualClick() {
        this.openManualModal();
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'edit') {
            this.openManualModal(row);
        } else if (actionName === 'delete') {
            this.openCommentModal('delete', row.id);
        }
    }

    handleManualFieldChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;
    }

    handleManualCancel() {
        this.closeManualModal();
    }

    handleManualConfirm() {
        if (!this.manualDate) {
            this.showToast('Error', 'Date is required.', 'error');
            return;
        }

        const startTime = this.combineDateTime(this.manualDate, this.manualStartTime);
        const endTime = this.combineDateTime(this.manualDate, this.manualEndTime);

        if (!startTime || !endTime) {
            this.showToast('Error', 'Invalid date or time.', 'error');
            return;
        }
        if (endTime <= startTime) {
            this.showToast('Error', 'End time must be after start time.', 'error');
            return;
        }
        if (endTime.getTime() - startTime.getTime() > 24 * 60 * 60 * 1000) {
            this.showToast('Error', 'A single time entry cannot exceed 24 hours.', 'error');
            return;
        }

        this.isProcessing = true;
        const comments = (this.manualComments || '').trim();
        const type = this.isUtilityBarContext ? this.manualType : null;
        const request = this.manualEditId
            ? updateTimeTracking({
                  timeTrackingId: this.manualEditId,
                  startTime: startTime.toISOString(),
                  endTime: endTime.toISOString(),
                  comments
              })
            : createManualEntry({
                  recordId: this.recordId,
                  type,
                  startTime: startTime.toISOString(),
                  endTime: endTime.toISOString(),
                  comments
              });

        request
            .then(() => {
                this.showToast('Success', this.manualEditId ? 'Time tracking record updated.' : 'Time tracking record created.', 'success');
                this.closeManualModal();
                return refreshApex(this.wiredDataResult);
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    openBlockingModal() {
        this.showBlockingModal = true;
    }

    openCommentModal(mode, recordId) {
        this.modalMode = mode;
        this.selectedRecordId = recordId;
        this.modalComments = '';
        this.showCommentModal = true;
    }

    closeCommentModal() {
        this.showCommentModal = false;
        this.modalMode = '';
        this.selectedRecordId = null;
        this.modalComments = '';
    }

    openManualModal(row) {
        if (row) {
            this.manualEditId = row.id;
            const start = row.startTime ? new Date(row.startTime) : null;
            const end = row.endTime ? new Date(row.endTime) : null;
            this.manualDate = start ? this.toDateInput(start) : '';
            this.manualStartTime = start ? this.toTimeInput(start) : '';
            this.manualEndTime = end ? this.toTimeInput(end) : '';
            this.manualComments = row.comments || '';
        } else {
            this.manualEditId = null;
            this.manualDate = '';
            this.manualStartTime = '';
            this.manualEndTime = '';
            this.manualComments = '';
            this.manualType = TYPE_INTERNAL_TASK;
        }
        this.showManualModal = true;
    }

    closeManualModal() {
        this.showManualModal = false;
        this.manualEditId = null;
        this.manualDate = '';
        this.manualStartTime = '';
        this.manualEndTime = '';
        this.manualComments = '';
    }

    runStartTimer() {
        this.isProcessing = true;
        const type = this.isUtilityBarContext ? this.internalType : null;
        startTimer({ recordId: this.recordId, type, instanceId: this.instanceId })
            .then((result) => {
                if (result.blockingTimer) {
                    this.blockingTimer = result.blockingTimer;
                    this.openBlockingModal();
                    return refreshApex(this.wiredDataResult);
                }
                this.showToast('Success', 'Timer started.', 'success');
                return refreshApex(this.wiredDataResult);
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    runCompleteTimer() {
        const shouldStartAfterComplete = this.modalMode === 'blocking';
        this.isProcessing = true;
        completeTimer({
            timeTrackingId: this.selectedRecordId,
            comments: (this.modalComments || '').trim()
        })
            .then(() => {
                this.closeCommentModal();
                this.blockingTimer = null;

                if (shouldStartAfterComplete) {
                    const type = this.isUtilityBarContext ? this.internalType : null;
                    return startTimer({ recordId: this.recordId, type, instanceId: this.instanceId }).then((result) => {
                        if (result.blockingTimer) {
                            this.blockingTimer = result.blockingTimer;
                            this.openBlockingModal();
                            this.showToast(
                                'Warning',
                                'Previous timer completed, but another active timer was found.',
                                'warning'
                            );
                        } else {
                            this.showToast(
                                'Success',
                                'Previous timer completed and new timer started.',
                                'success'
                            );
                        }
                        return refreshApex(this.wiredDataResult);
                    });
                }

                this.showToast('Success', 'Timer completed.', 'success');
                return refreshApex(this.wiredDataResult);
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    runDeleteTimeTracking() {
        this.isProcessing = true;
        deleteTimeTracking({
            timeTrackingId: this.selectedRecordId,
            comments: (this.modalComments || '').trim()
        })
            .then(() => {
                this.closeCommentModal();
                this.showToast('Success', 'Time tracking record deleted.', 'success');
                return refreshApex(this.wiredDataResult);
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    syncHeartbeat() {
        const shouldHeartbeat = this.isActiveTimerRunning && this.activeTimer.timerInstanceId === this.instanceId;
        if (!shouldHeartbeat) {
            this.stopHeartbeat();
            return;
        }
        if (this.heartbeatInterval) {
            return;
        }
        const timerId = this.activeTimer.id;
        this.heartbeatInterval = window.setInterval(() => {
            heartbeat({ timeTrackingId: timerId, instanceId: this.instanceId }).catch(() => {
                // Heartbeats are best-effort; a transient failure is retried on the next tick.
            });
        }, HEARTBEAT_INTERVAL_MS);
    }

    stopHeartbeat() {
        if (this.heartbeatInterval) {
            window.clearInterval(this.heartbeatInterval);
            this.heartbeatInterval = null;
        }
    }

    syncTimerDisplay() {
        const blockingElapsedMs = this.blockingTimer?.startTime
            ? Date.now() - new Date(this.blockingTimer.startTime).getTime()
            : 0;
        this.blockingElapsedDisplay = this.formatElapsed(blockingElapsedMs);

        const runningTimer = this.activeTimer || this.blockingTimer;
        const runningElapsedMs = runningTimer?.startTime
            ? Date.now() - new Date(runningTimer.startTime).getTime()
            : 0;
        this.elapsedDisplay = this.formatElapsed(runningElapsedMs);

        if (!this.activeTimer || !this.activeTimer.startTime || this.isActiveTimerPaused) {
            this.displayTotalMinutes = this.totalMinutes + (this.activeTimer ? Number(this.activeTimer.durationMinutes) || 0 : 0);
            return;
        }

        const elapsedMs = Math.max(0, Date.now() - new Date(this.activeTimer.startTime).getTime());
        const pausedMs = (Number(this.activeTimer.pausedDurationMinutes) || 0) * 60000;
        const activeDurationMinutes = Math.ceil(Math.max(0, elapsedMs - pausedMs) / 60000);
        const activeRecordId = this.activeTimer.id;
        const completedTotal = (this.tableData || []).reduce((sum, record) => {
            if (record.id === activeRecordId) {
                return sum;
            }
            return sum + (Number(record.durationMinutes) || 0);
        }, 0);
        this.displayTotalMinutes = completedTotal + activeDurationMinutes;
    }

    formatElapsed(elapsedMs) {
        return this.formatDuration(elapsedMs / 60000);
    }

    formatDateTime(value) {
        if (!value) {
            return '';
        }
        return new Date(value).toLocaleString('en-US', {
            month: '2-digit',
            day: '2-digit',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            hour12: true
        });
    }

    formatDuration(value) {
        const minutes = Number(value);
        const totalMinutes = Number.isFinite(minutes) ? Math.max(0, Math.ceil(minutes)) : 0;
        const days = Math.floor(totalMinutes / (24 * 60));
        const hours = Math.floor((totalMinutes % (24 * 60)) / 60);
        const remainingMinutes = totalMinutes % 60;
        return `${days}d ${hours}h ${remainingMinutes}m`;
    }

    combineDateTime(dateStr, timeStr) {
        if (!dateStr) {
            return null;
        }
        const time = timeStr || '00:00:00';
        const normalizedTime = time.length === 5 ? `${time}:00` : time;
        const combined = new Date(`${dateStr}T${normalizedTime}`);
        return isNaN(combined.getTime()) ? null : combined;
    }

    toDateInput(date) {
        const year = date.getFullYear();
        const month = this.pad(date.getMonth() + 1);
        const day = this.pad(date.getDate());
        return `${year}-${month}-${day}`;
    }

    toTimeInput(date) {
        return `${this.pad(date.getHours())}:${this.pad(date.getMinutes())}:${this.pad(date.getSeconds())}`;
    }

    pad(value) {
        return String(value).padStart(2, '0');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}
