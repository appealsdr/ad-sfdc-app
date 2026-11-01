import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getDocuments from '@salesforce/apex/S3DocumentController.getDocuments';
import getDocumentAccess from '@salesforce/apex/S3DocumentController.getDocumentAccess';

export default class S3DocumentViewer extends LightningElement {
    @api recordId;

    @track documents = [];
    @track selectedDocumentId;
    @track previewUrl;
    @track previewType = 'None';
    @track selectedFileName;
    @track selectedContentType;
    @track isPreviewable = false;

    isLoading = true;
    isPreviewLoading = false;
    isDownloading = false;
    wiredDocumentsResult;

    @wire(getDocuments, { recordId: '$recordId' })
    wiredDocuments(result) {
        this.wiredDocumentsResult = result;
        this.isLoading = false;

        const { data, error } = result;
        if (data) {
            this.documents = data.map((document) => ({
                ...document,
                rowClass: document.id === this.selectedDocumentId
                    ? 'file-row file-row-selected'
                    : 'file-row'
            }));

            if (!this.selectedDocumentId && this.documents.length > 0) {
                this.selectDocument(this.documents[0].id);
            } else if (this.selectedDocumentId) {
                this.refreshSelectedPreview();
            }
        } else if (error) {
            this.documents = [];
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    get hasDocuments() {
        return this.documents.length > 0;
    }

    get noDocuments() {
        return !this.isLoading && this.documents.length === 0;
    }

    get showImagePreview() {
        return this.previewUrl && this.previewType === 'Image';
    }

    get showPdfPreview() {
        return this.previewUrl && this.previewType === 'PDF';
    }

    get showVideoPreview() {
        return this.previewUrl && this.previewType === 'Video';
    }

    get showTextPreview() {
        return this.previewUrl && this.previewType === 'Text';
    }

    get showUnsupportedPreview() {
        return this.selectedDocumentId && !this.isPreviewable && !this.isPreviewLoading;
    }

    get showPreviewPanel() {
        return this.selectedDocumentId != null;
    }

    handleDocumentSelect(event) {
        const documentId = event.currentTarget.dataset.id;
        this.selectDocument(documentId);
    }

    handleDownloadClick() {
        if (!this.selectedDocumentId) {
            return;
        }

        this.isDownloading = true;
        getDocumentAccess({
            documentId: this.selectedDocumentId,
            accessType: 'download'
        })
            .then((access) => {
                this.openUrl(access.url);
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isDownloading = false;
            });
    }

    handleRefreshClick() {
        refreshApex(this.wiredDocumentsResult);
        if (this.selectedDocumentId) {
            this.refreshSelectedPreview(true);
        }
    }

    selectDocument(documentId) {
        this.selectedDocumentId = documentId;
        this.documents = this.documents.map((document) => ({
            ...document,
            rowClass: document.id === documentId ? 'file-row file-row-selected' : 'file-row'
        }));
        this.refreshSelectedPreview(true);
    }

    refreshSelectedPreview(forceReload = false) {
        const selected = this.documents.find((document) => document.id === this.selectedDocumentId);
        if (!selected) {
            this.clearPreview();
            return;
        }

        this.selectedFileName = selected.fileName;
        this.selectedContentType = selected.contentType;
        this.isPreviewable = selected.isPreviewable;
        this.previewType = selected.previewType || 'None';

        if (!selected.isPreviewable) {
            this.previewUrl = null;
            return;
        }

        if (!forceReload && this.previewUrl) {
            return;
        }

        this.isPreviewLoading = true;
        getDocumentAccess({
            documentId: selected.id,
            accessType: 'preview'
        })
            .then((access) => {
                this.previewUrl = access.url;
                this.previewType = access.previewType || this.previewType;
                this.isPreviewable = access.isPreviewable;
            })
            .catch((error) => {
                this.previewUrl = null;
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isPreviewLoading = false;
            });
    }

    clearPreview() {
        this.previewUrl = null;
        this.selectedFileName = null;
        this.selectedContentType = null;
        this.previewType = 'None';
        this.isPreviewable = false;
    }

    openUrl(url) {
        if (!url) {
            return;
        }
        window.open(url, '_blank');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    @api
    refreshDocuments() {
        return refreshApex(this.wiredDocumentsResult);
    }
}