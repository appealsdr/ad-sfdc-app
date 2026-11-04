import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOrgBaseUrl       from '@salesforce/apex/AccountCaseReportEmailController.getOrgBaseUrl';
import getFromEmailOptions from '@salesforce/apex/AccountCaseReportEmailController.getFromEmailOptions';
import getEmailOptions     from '@salesforce/apex/AccountCaseReportEmailController.getEmailOptions';
import sendReport          from '@salesforce/apex/AccountCaseReportEmailController.sendReport';

const MONTH_NAMES = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
];

export default class AccountCaseReport extends LightningElement {

    /** Account record Id — set by the Lightning record page. */
    @api recordId;

    // ─── Internal state ───────────────────────────────────────────────────────
    @track selectedMonth    = this._defaultMonth();   // YYYY-MM
    @track isModalOpen      = false;
    @track selectedEmail    = '';       // "To" combobox value
    @track customEmail      = '';       // "To" free-text value
    @track selectedFromVal  = 'CURRENT_USER';  // "From" combobox value (OWA Id or sentinel)
    @track isSending        = false;
    @track emailOptions     = [];
    @track fromEmailOptions = [];
    @track isLoadingEmails  = true;

    _orgBaseUrl = '';


    // =========================================================================
    // WIRED DATA
    // =========================================================================

    /** Org domain URL — used to construct the VF page iframe src. */
    @wire(getOrgBaseUrl)
    wiredOrgUrl({ data, error }) {
        if (data) {
            this._orgBaseUrl = data;
        } else if (error) {
            // Non-fatal — preview iframe just won't load
            console.error('accountCaseReport: could not get org base URL', error);
        }
    }

    /** Available "From" senders: current user + Org-Wide Email Addresses. */
    @wire(getFromEmailOptions)
    wiredFromEmails({ data, error }) {
        if (data) {
            this.fromEmailOptions = data;
            // Default to first option (current user)
            this.selectedFromVal  = data.length > 0 ? data[0].value : 'CURRENT_USER';
        } else if (error) {
            console.error('accountCaseReport: could not load From options', error);
        }
    }

    /** Email addresses from Account + related Contacts. */
    @wire(getEmailOptions, { accountId: '$recordId' })
    wiredEmails({ data, error }) {
        this.isLoadingEmails = false;
        if (data) {
            this.emailOptions  = data;
            this.selectedEmail = data.length > 0 ? data[0].value : '';
        } else if (error) {
            this.emailOptions = [];
            const msg = (error.body && error.body.message) ? error.body.message : error.message;
            this._toast('Error loading email addresses', msg, 'error');
        }
    }


    // =========================================================================
    // GETTERS
    // =========================================================================

    /** Full URL passed to the iframe — renders the VF page in HTML mode. */
    get vfPageUrl() {
        if (!this._orgBaseUrl || !this.recordId) return null;
        return (
            `${this._orgBaseUrl}/apex/AccountCaseReport` +
            `?id=${this.recordId}` +
            `&pdf=false` +
            `&Month=${this.selectedMonth}`
        );
    }

    get noEmailsFound() {
        return !this.isLoadingEmails && (!this.emailOptions || this.emailOptions.length === 0);
    }

    get hasEmailOptions() {
        return !this.isLoadingEmails && this.emailOptions && this.emailOptions.length > 0;
    }

    /**
     * The actual address that will be used when Send is clicked.
     * Custom free-text input takes priority over the combobox selection.
     */
    get recipientEmail() {
        const custom = (this.customEmail || '').trim();
        return custom || this.selectedEmail;
    }

    get isSendDisabled() {
        return !this.recipientEmail || this.isSending || !this._isValidEmail(this.recipientEmail);
    }

    get sendButtonLabel() {
        return this.isSending ? 'Sending…' : 'Send';
    }

    /** Human-readable label for the selected month, e.g. "April 2026". */
    get selectedMonthLabel() {
        if (!this.selectedMonth) return '';
        const [year, month] = this.selectedMonth.split('-');
        return `${MONTH_NAMES[parseInt(month, 10) - 1]} ${year}`;
    }


    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================

    handleMonthChange(event) {
        this.selectedMonth = event.target.value;
    }

    handleSendEmailClick() {
        this.isModalOpen = true;
    }

    handleModalClose() {
        if (!this.isSending) {
            this.isModalOpen  = false;
            this.customEmail  = '';           // reset custom input on close
        }
    }

    handleFromChange(event) {
        this.selectedFromVal = event.detail.value;
    }

    handleEmailChange(event) {
        this.selectedEmail = event.detail.value;
        this.customEmail   = '';              // combobox selection clears custom field
    }

    handleCustomEmailChange(event) {
        this.customEmail   = event.target.value;
        this.selectedEmail = '';              // custom input clears combobox selection
    }

    handleSend() {
        const recipient = this.recipientEmail;
        if (!recipient || this.isSending) return;

        this.isSending = true;

        sendReport({
            accountId:      this.recordId,
            recipientEmail: recipient,
            monthParam:     this.selectedMonth,
            fromOwaId:      this.selectedFromVal
        })
            .then(() => {
                this.isSending   = false;
                this.isModalOpen = false;
                this.customEmail = '';
                this._toast(
                    'Report Sent',
                    `Case report for ${this.selectedMonthLabel} sent to ${recipient}. ` +
                    'An email activity has been logged on this Account.',
                    'success'
                );
            })
            .catch((error) => {
                this.isSending = false;
                const msg = (error.body && error.body.message) ? error.body.message : error.message;
                this._toast('Send Failed', msg, 'error');
            });
    }


    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    /** Returns YYYY-MM for the previous calendar month (default report period). */
    _defaultMonth() {
        const d = new Date();
        d.setDate(1);
        d.setMonth(d.getMonth() - 1);
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        return `${y}-${m}`;
    }

    /**
     * The email address string for the selected From option — shown in the
     * preview chip. Looks up the `email` property from `fromEmailOptions`.
     */
    get senderEmail() {
        const opt = (this.fromEmailOptions || []).find(o => o.value === this.selectedFromVal);
        return opt ? opt.email : '';
    }

    /** Basic RFC-5322-ish email format check. */
    _isValidEmail(email) {
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test((email || '').trim());
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}