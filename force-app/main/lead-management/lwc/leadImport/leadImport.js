import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import parseCSVPreview  from '@salesforce/apex/LeadImportController.parseCSVPreview';
import importLeads      from '@salesforce/apex/LeadImportController.importLeads';
import getSourceOptions from '@salesforce/apex/LeadImportController.getSourceOptions';

// Columns shown in the preview datatable.
// These match the Apex CSV_TO_LEAD_FIELD_MAP keys — only relevant fields are shown.
// Add or remove entries here without touching Apex.
const PREVIEW_COLUMN_LABELS = [
    'Seller Name',
    'First Name',
    'Last Name',
    'Mail',
    'Phone',
    'Title',
    'City',
    'State',
    'Country'
];

export default class LeadImport extends LightningElement {

    // ─── Public property (configurable in App Builder) ───────────────────────
    @api cardTitle = 'Lead Import';

    // ─── Form state ──────────────────────────────────────────────────────────
    @track uploadName    = '';
    @track source        = '';
    @track sourceOptions = [];
    @track sourceOptionsLoaded = false;

    // =========================================================================
    // WIRED APEX — load Source picklist values once on component init
    // =========================================================================
    @wire(getSourceOptions)
    wiredSourceOptions({ data, error }) {
        if (data) {
            // Apex returns List<Map<String,String>> with {label, value} pairs;
            // lightning-combobox expects the same shape, so no transform needed.
            this.sourceOptions       = data;
            this.sourceOptionsLoaded = true;
        } else if (error) {
            this.sourceOptions       = [];
            this.sourceOptionsLoaded = true;
            const msg = error.body ? error.body.message : error.message;
            this.showToast('Source list unavailable', msg, 'warning');
        }
    }

    // ─── File state ──────────────────────────────────────────────────────────
    @track fileName   = '';
    csvContent        = '';          // raw CSV string kept in memory

    // ─── Preview state ───────────────────────────────────────────────────────
    @track previewData    = [];
    @track previewColumns = [];
    @track totalRowCount  = 0;

    // ─── UI state ────────────────────────────────────────────────────────────
    @track isLoading          = false;
    @track loadingMessage     = 'Loading…';
    @track showPreview        = false;
    @track showResult         = false;
    @track showValidationError = false;
    @track isUploading        = false;

    // ─── Result state ────────────────────────────────────────────────────────
    @track importResult = { successCount: 0, failureCount: 0, errors: [], failedLeads: [] };
    @track failedTableData    = [];
    @track failedTableColumns = [];

    // =========================================================================
    // GETTERS
    // =========================================================================

    get uploadNameClass() {
        return this.uploadName ? '' : 'slds-has-error';
    }
    get sourceClass() {
        return this.source ? '' : 'slds-has-error';
    }
    get isFileInputDisabled() {
        // File input stays enabled always; validation fires on file select
        return false;
    }
    get previewRowCount() {
        return this.previewData.length;
    }
    get previewCapped() {
        return this.totalRowCount > 50;
    }
    get uploadButtonLabel() {
        return this.isUploading
            ? 'Uploading…'
            : `Upload ${this.totalRowCount} Lead${this.totalRowCount !== 1 ? 's' : ''}`;
    }
    get hasSuccesses() {
        return this.importResult && this.importResult.successCount > 0;
    }
    get hasFailures() {
        return this.importResult && this.importResult.failureCount > 0;
    }
    get hasFailedLeads() {
        return this.importResult
            && this.importResult.failedLeads
            && this.importResult.failedLeads.length > 0;
    }
    get hasSourceOptions() {
        // True when Apex returned a non-empty picklist — drives combobox vs text fallback.
        return this.sourceOptions && this.sourceOptions.length > 0;
    }

    // =========================================================================
    // EVENT HANDLERS — Form inputs
    // =========================================================================

    handleUploadNameChange(event) {
        this.uploadName = event.target.value;
        if (this.uploadName) {
            this.showValidationError = false;
        }
    }

    handleSourceChange(event) {
        this.source = event.target.value;
        if (this.source) {
            this.showValidationError = false;
        }
    }

    // =========================================================================
    // EVENT HANDLERS — File input
    // =========================================================================

    handleFileChange(event) {
        // Validate form fields first
        if (!this.uploadName || !this.source) {
            this.showValidationError = true;
            // Clear the file input
            event.target.value = '';
            return;
        }
        this.showValidationError = false;

        const file = event.target.files[0];
        if (!file) return;

        this.fileName = file.name;
        this.loadingMessage = 'Parsing file…';
        this.isLoading = true;

        const reader = new FileReader();
        reader.onload = (e) => {
            this.csvContent = e.target.result;
            this.loadPreview();
        };
        reader.onerror = () => {
            this.isLoading = false;
            this.showToast('Error', 'Could not read the file.', 'error');
        };
        reader.readAsText(file);
    }

    // =========================================================================
    // PREVIEW — calls Apex to parse and return column/row definitions
    // =========================================================================

    loadPreview() {
        parseCSVPreview({ csvContent: this.csvContent })
            .then((result) => {
                this.totalRowCount = result.totalCount;

                // Build columns — filter to PREVIEW_COLUMN_LABELS if present,
                // otherwise show everything returned by Apex
                const allCols = result.columns || [];
                const filtered = allCols.filter(col =>
                    PREVIEW_COLUMN_LABELS.some(label =>
                        this.sanitizeKey(label) === col.fieldName
                    )
                );
                this.previewColumns = filtered.length > 0 ? filtered : allCols;

                // Rows already have __id from Apex
                this.previewData = result.rows || [];

                this.isLoading   = false;
                this.showPreview = true;
            })
            .catch((error) => {
                this.isLoading = false;
                const msg = error.body ? error.body.message : error.message;
                this.showToast('Parse Error', msg, 'error');
            });
    }

    // =========================================================================
    // EVENT HANDLERS — Upload & Reset
    // =========================================================================

    handleUpload() {
        // Re-validate (belt-and-suspenders; file input already validated)
        if (!this.uploadName || !this.source) {
            this.showValidationError = true;
            return;
        }

        this.isUploading      = true;
        this.loadingMessage   = 'Importing leads…';
        this.isLoading        = true;

        importLeads({
            csvContent : this.csvContent,
            uploadName : this.uploadName,
            source     : this.source
        })
            .then((result) => {
                this.importResult = result;
                this.buildFailedLeadsTable(result);
                this.isLoading    = false;
                this.isUploading  = false;
                this.showPreview  = false;
                this.showResult   = true;
            })
            .catch((error) => {
                this.isLoading   = false;
                this.isUploading = false;
                const msg = error.body ? error.body.message : error.message;
                this.showToast('Import Error', msg, 'error');
            });
    }

    handleClear() {
        this.resetFileState();
    }

    handleReset() {
        this.resetFileState();
        this.importResult       = { successCount: 0, failureCount: 0, errors: [], failedLeads: [] };
        this.failedTableData    = [];
        this.failedTableColumns = [];
        this.showResult         = false;
    }

    /**
     * buildFailedLeadsTable
     * Flattens the Apex FailedLead[] response into a row-shape lightning-datatable
     * can render: one row per failed lead, with the reason as the first column
     * followed by the same preview columns shown before upload.
     */
    buildFailedLeadsTable(result) {
        const failed = (result && result.failedLeads) || [];
        if (failed.length === 0) {
            this.failedTableData    = [];
            this.failedTableColumns = [];
            return;
        }

        const columns = [
            { label: 'Row',    fieldName: '__row',    type: 'number', initialWidth: 70 },
            { label: 'Reason', fieldName: '__reason', type: 'text',   wrapText: true }
        ];
        for (const label of PREVIEW_COLUMN_LABELS) {
            columns.push({
                label,
                fieldName: this.sanitizeKey(label),
                type: 'text'
            });
        }
        this.failedTableColumns = columns;

        this.failedTableData = failed.map((fl, idx) => ({
            __id:     `f${idx}`,
            __row:    fl.rowNumber,
            __reason: fl.reason,
            ...(fl.rowData || {})
        }));
    }

    // =========================================================================
    // DOWNLOAD — export failed leads as a CSV file
    // =========================================================================

    /**
     * handleDownloadFailed
     * Generates a CSV of all not-uploaded leads and triggers a browser download.
     * Columns: Row, Reason, then every original CSV column present on the rows.
     * Uses the full rowData map (not just preview columns) so re-importing the
     * downloaded file after fixes is straightforward.
     */
    handleDownloadFailed() {
        const failed = (this.importResult && this.importResult.failedLeads) || [];
        if (failed.length === 0) return;

        // Collect every distinct rowData key across all failed rows, preserving
        // first-seen order — keeps column order stable when rows have the same shape.
        const dataKeys = [];
        const seen = new Set();
        for (const fl of failed) {
            const rd = fl.rowData || {};
            for (const k of Object.keys(rd)) {
                if (!seen.has(k)) { seen.add(k); dataKeys.push(k); }
            }
        }

        const escape = (val) => {
            const s = val == null ? '' : String(val);
            return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
        };

        const header = ['Row', 'Reason', ...dataKeys].map(escape).join(',');
        const lines  = failed.map(fl => {
            const rd = fl.rowData || {};
            return [
                fl.rowNumber,
                fl.reason,
                ...dataKeys.map(k => rd[k] || '')
            ].map(escape).join(',');
        });
        // Leading BOM so Excel opens UTF-8 correctly
        const csv = '﻿' + [header, ...lines].join('\r\n');

        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url  = URL.createObjectURL(blob);
        const a    = document.createElement('a');
        a.href     = url;
        a.download = this.buildFailedFileName();
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    buildFailedFileName() {
        const safeName = (this.uploadName || 'lead-import')
            .replace(/[^a-zA-Z0-9-_ ]/g, '')
            .trim()
            .replace(/\s+/g, '_') || 'lead-import';
        const ts = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
        return `${safeName}_failed_${ts}.csv`;
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    resetFileState() {
        this.csvContent   = '';
        this.fileName     = '';
        this.previewData  = [];
        this.previewColumns = [];
        this.totalRowCount  = 0;
        this.showPreview    = false;

        // Reset the file input element so the same file can be re-selected
        const fileInput = this.template.querySelector('lightning-input[type="file"]');
        if (fileInput) {
            fileInput.value = '';
        }
    }

    /**
     * sanitizeKey — mirrors the Apex sanitizeKey helper.
     * Converts a CSV header to the safe property name used as fieldName.
     */
    sanitizeKey(header) {
        return header.replace(/[^a-zA-Z0-9]/g, '_').toLowerCase();
    }

    /**
     * showToast — dispatches a platform toast event.
     */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}