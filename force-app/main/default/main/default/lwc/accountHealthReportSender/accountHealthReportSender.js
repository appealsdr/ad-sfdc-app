import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue }           from 'lightning/uiRecordApi';
import { ShowToastEvent }                      from 'lightning/platformShowToastEvent';
import getReportData                           from '@salesforce/apex/AccountHealthReportController.getReportData';
import sendReportEmail                         from '@salesforce/apex/AccountHealthReportController.sendReportEmail';

// Wired fields for initial account query
import ACCOUNT_NAME_FIELD  from '@salesforce/schema/Account.Name';
import ACCOUNT_OWNER_FIELD from '@salesforce/schema/Account.Owner.Name';

const ACCOUNT_FIELDS = [ACCOUNT_NAME_FIELD, ACCOUNT_OWNER_FIELD];

export default class AccountHealthReportSender extends LightningElement {

    // ── Record page context ────────────────────────────────────────────────
    @api recordId;   // injected automatically when placed on an Account record page

    // ── UI state ───────────────────────────────────────────────────────────
    @track isLoading    = true;
    @track isReady      = false;
    @track isSending    = false;
    @track showPreview  = false;
    @track sendSuccess  = false;
    @track errorMessage = '';
    @track toEmail      = '';

    // ── All report data in one reactive object ─────────────────────────────
    @track report = {
        // Header
        accountName      : '',
        accountManager   : '',
        reportDate       : '',
        reportStart      : '',
        reportEnd        : '',
        reportType       : 'Monthly',
        // Health
        currentHealth    : '1000',
        healthThisPeriod : '1000',
        healthLastPeriod : '1000',
        healthChange     : '0',
        // Solved
        solvedFeedbackRemoval    : '0',
        solvedViolation          : '0',
        solvedListingIssue       : '0',
        solvedAzClaim            : '0',
        solvedBrandApproval      : 'N/A',
        solvedBrandRemoval       : 'N/A',
        solvedBrandGating        : 'N/A',
        solvedCustomerMessage    : '0',
        solvedShippingComplaint  : 'N/A',
        solvedStorageIncrease    : 'N/A',
        solvedChargeback         : '0',
        totalIssuesFixed         : '0',
        // Ongoing
        ongoingViolation         : '0',
        ongoingListingIssue      : '0',
        ongoingAzClaim           : '0',
        ongoingBrandApproval     : 'N/A',
        ongoingFeedbackRemoval   : '0',
        ongoingBrandRemoval      : 'N/A',
        ongoingBrandGating       : 'N/A',
        ongoingCustomerMessage   : '0',
        ongoingShippingComplaint : 'N/A',
        ongoingStorageIncrease   : 'N/A',
        ongoingChargeback        : '0',
        totalNewOngoing          : '0',
    };

    // =========================================================================
    // WIRE — load account data from Apex on component init
    // =========================================================================
    @wire(getRecord, { recordId: '$recordId', fields: ACCOUNT_FIELDS })
    wiredAccount({ data, error }) {
        if (data) {
            // Pre-fill from the wired record, then call Apex for full data
            this.report = {
                ...this.report,
                accountName    : getFieldValue(data, ACCOUNT_NAME_FIELD)  || '',
                accountManager : getFieldValue(data, ACCOUNT_OWNER_FIELD) || '',
            };
            this.loadApexData();
        } else if (error) {
            // Fall back gracefully — still allow manual entry
            this.loadApexData();
        }
    }

    loadApexData() {
        if (!this.recordId) {
            this.isLoading = false;
            this.isReady   = true;
            return;
        }
        getReportData({ accountId: this.recordId })
            .then(data => {
                this.report = {
                    ...this.report,
                    accountName    : data.accountName    || this.report.accountName,
                    accountManager : data.accountManager || this.report.accountManager,
                    reportDate     : data.reportDate     || this.report.reportDate,
                    reportType     : data.reportType     || this.report.reportType,
                };
                if (data.contactEmail) {
                    this.toEmail = data.contactEmail;
                }
                this.isLoading = false;
                this.isReady   = true;
            })
            .catch(err => {
                // Non-fatal: user can still fill in fields manually
                console.warn('getReportData warning:', err);
                this.isLoading = false;
                this.isReady   = true;
            });
    }

    // =========================================================================
    // GETTERS — computed UI values
    // =========================================================================

    get reportTypeOptions() {
        return [
            { label: 'Monthly',   value: 'Monthly'   },
            { label: 'Quarterly', value: 'Quarterly' },
            { label: 'Weekly',    value: 'Weekly'    },
            { label: 'Annual',    value: 'Annual'    },
        ];
    }

    get sendButtonLabel() {
        return this.isSending ? 'Sending…' : 'Send Report Email';
    }

    get showPreview() {
        return this._showPreview;
    }

    get previewIcon() {
        return this._showPreview ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get previewToggleLabel() {
        return this._showPreview ? 'Click to collapse' : 'Click to expand';
    }

    // ── Row definitions for for:each loops ────────────────────────────────

    get solvedRows() {
        const r = this.report;
        return [
            { label: 'Feedback Removal',   field: 'solvedFeedbackRemoval',   value: r.solvedFeedbackRemoval   },
            { label: 'Violation',           field: 'solvedViolation',          value: r.solvedViolation          },
            { label: 'Listing Issue',       field: 'solvedListingIssue',       value: r.solvedListingIssue       },
            { label: 'A-Z Claim',           field: 'solvedAzClaim',            value: r.solvedAzClaim            },
            { label: 'Brand Approval',      field: 'solvedBrandApproval',      value: r.solvedBrandApproval      },
            { label: 'Brand Removal',       field: 'solvedBrandRemoval',       value: r.solvedBrandRemoval       },
            { label: 'Brand Gating',        field: 'solvedBrandGating',        value: r.solvedBrandGating        },
            { label: 'Customer Message',    field: 'solvedCustomerMessage',    value: r.solvedCustomerMessage    },
            { label: 'Shipping Complaint',  field: 'solvedShippingComplaint',  value: r.solvedShippingComplaint  },
            { label: 'Storage Increase',    field: 'solvedStorageIncrease',    value: r.solvedStorageIncrease    },
            { label: 'Chargeback',          field: 'solvedChargeback',         value: r.solvedChargeback         },
        ];
    }

    get ongoingRows() {
        const r = this.report;
        return [
            { label: 'Violation',           field: 'ongoingViolation',         value: r.ongoingViolation         },
            { label: 'Listing Issue',        field: 'ongoingListingIssue',      value: r.ongoingListingIssue      },
            { label: 'A-Z Claim',            field: 'ongoingAzClaim',           value: r.ongoingAzClaim           },
            { label: 'Brand Approval',       field: 'ongoingBrandApproval',     value: r.ongoingBrandApproval     },
            { label: 'Feedback Removal',     field: 'ongoingFeedbackRemoval',   value: r.ongoingFeedbackRemoval   },
            { label: 'Brand Removal',        field: 'ongoingBrandRemoval',      value: r.ongoingBrandRemoval      },
            { label: 'Brand Gating',         field: 'ongoingBrandGating',       value: r.ongoingBrandGating       },
            { label: 'Customer Message',     field: 'ongoingCustomerMessage',   value: r.ongoingCustomerMessage   },
            { label: 'Shipping Complaint',   field: 'ongoingShippingComplaint', value: r.ongoingShippingComplaint },
            { label: 'Storage Increase',     field: 'ongoingStorageIncrease',   value: r.ongoingStorageIncrease   },
            { label: 'Chargeback',           field: 'ongoingChargeback',        value: r.ongoingChargeback        },
        ];
    }

    // =========================================================================
    // EVENT HANDLERS
    // =========================================================================

    /** Generic field change — reads data-field attribute to update report object */
    handleChange(event) {
        const field = event.target.dataset.field;
        if (field) {
            this.report = { ...this.report, [field]: event.target.value };
        }
        this.sendSuccess = false; // reset success banner on edit
    }

    handleEmailChange(event) {
        this.toEmail     = event.target.value;
        this.sendSuccess = false;
    }

    togglePreview() {
        this._showPreview = !this._showPreview;
    }

    // ── Send Email ──────────────────────────────────────────────────────────
    handleSendEmail() {
        if (!this.toEmail || !this.toEmail.includes('@')) {
            this.showToast('Missing Email', 'Please enter a valid recipient email address.', 'error');
            return;
        }

        this.isSending   = true;
        this.sendSuccess = false;
        this.errorMessage = '';

        sendReportEmail({
            toEmail    : this.toEmail,
            reportJson : JSON.stringify(this.report),
        })
            .then(() => {
                this.isSending   = false;
                this.sendSuccess = true;
                this.showToast('Email Sent', 'Account Health Report sent to ' + this.toEmail, 'success');
            })
            .catch(err => {
                this.isSending = false;
                const msg = (err.body && err.body.message) ? err.body.message : err.message;
                this.showToast('Send Failed', msg, 'error');
            });
    }

    // =========================================================================
    // PRIVATE STATE / HELPERS
    // =========================================================================

    _showPreview = false;

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}