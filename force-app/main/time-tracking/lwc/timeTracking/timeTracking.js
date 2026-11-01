import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getTimeTrackingData from '@salesforce/apex/TimeTrackingController.getTimeTrackingData';
import startTimer from '@salesforce/apex/TimeTrackingController.startTimer';
import completeTimer from '@salesforce/apex/TimeTrackingController.completeTimer';
import deleteTimeTracking from '@salesforce/apex/TimeTrackingController.deleteTimeTracking';
import createManualEntry from '@salesforce/apex/TimeTrackingController.createManualEntry';
import updateTimeTracking from '@salesforce/apex/TimeTrackingController.updateTimeTracking';

const BASE_COLUMNS = [
    { label: 'Assignee', fieldName: 'assigneeName', type: 'text' },
    { label: 'Start Time', fieldName: 'formattedStartTime', type: 'text' },
    { label: 'End Time', fieldName: 'formattedEndTime', type: 'text' },
    { label: 'Duration (min)', fieldName: 'durationDisplay', type: 'text' },
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

export default class TimeTracking extends LightningElement {
    @api recordId;

    @track tableData = [];
    @track activeTimer;
    @track blockingTimer;
    @track totalMinutes = 0;
    @track displayTotalMinutes = 0;
    @track elapsedDisplay = '00:00:00';
    @track showCommentModal = false;
    @track showBlockingModal = false;
    @track showManualModal = false;
    @track modalComments = '';
    @track modalMode = '';
    @track selectedRecordId;
    @track isLoading = true;
    @track isProcessing = false;
    @track isAdmin = false;
    @track columns = BASE_COLUMNS;

    @track manualDate = '';
    @track manualStartTime = '';
    @track manualEndTime = '';
    @track manualComments = '';
    @track manualEditId;

    timerInterval;
    wiredDataResult;

    @wire(getTimeTrackingData, { recordId: '$recordId' })
    wiredTimeTracking(result) {
        this.wiredDataResult = result;
        this.isLoading = false;

        const { data, error } = result;
        if (data) {
            this.activeTimer = data.activeTimer;
            this.blockingTimer = data.blockingTimer;
            this.totalMinutes = data.totalMinutes || 0;
            this.isAdmin = !!data.isAdmin;
            this.columns = this.isAdmin ? [...BASE_COLUMNS, ADMIN_ACTIONS_COLUMN] : BASE_COLUMNS;
            this.tableData = (data.records || []).map((record) => ({
                ...record,
                formattedStartTime: this.formatDateTime(record.startTime),
                formattedEndTime: this.formatDateTime(record.endTime),
                durationDisplay: this.formatMinutes(record.durationMinutes)
            }));
            this.syncTimerDisplay();
        } else if (error) {
            this.tableData = [];
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    connectedCallback() {
        this.timerInterval = window.setInterval(() => {
            this.syncTimerDisplay();
        }, 1000);
    }

    disconnectedCallback() {
        if (this.timerInterval) {
            window.clearInterval(this.timerInterval);
        }
    }

    get hasActiveTimer() {
        return this.activeTimer != null;
    }

    get showStartButton() {
        return !this.hasActiveTimer;
    }

    get formattedTotalMinutes() {
        return this.formatMinutes(this.displayTotalMinutes);
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
        const relatedName = this.blockingTimer?.relatedRecordName || 'another record';
        return `You cannot start new time until other timer not completed. Active timer is on ${relatedName}.`;
    }

    handleStartClick() {
        if (this.blockingTimer) {
            this.openBlockingModal();
            return;
        }

        this.runStartTimer();
    }

    handleCompleteClick() {
        if (!this.activeTimer) {
            return;
        }
        this.openCommentModal('complete', this.activeTimer.id);
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
        const request = this.manualEditId
            ? updateTimeTracking({
                  timeTrackingId: this.manualEditId,
                  startTime: startTime.toISOString(),
                  endTime: endTime.toISOString(),
                  comments
              })
            : createManualEntry({
                  recordId: this.recordId,
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
        startTimer({ recordId: this.recordId })
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
                    return startTimer({ recordId: this.recordId }).then((result) => {
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

    syncTimerDisplay() {
        if (!this.activeTimer || !this.activeTimer.startTime) {
            this.elapsedDisplay = '00:00:00';
            this.displayTotalMinutes = this.totalMinutes;
            return;
        }

        const elapsedMs = Date.now() - new Date(this.activeTimer.startTime).getTime();
        this.elapsedDisplay = this.formatElapsed(elapsedMs);

        const activeDurationMinutes = elapsedMs / 60000;
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
        const totalSeconds = Math.max(0, Math.floor(elapsedMs / 1000));
        const hours = Math.floor(totalSeconds / 3600);
        const minutes = Math.floor((totalSeconds % 3600) / 60);
        const seconds = totalSeconds % 60;
        return `${this.pad(hours)}:${this.pad(minutes)}:${this.pad(seconds)}`;
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

    formatMinutes(value) {
        if (value == null || value === '') {
            return '0';
        }
        return String(Math.round(Number(value)));
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