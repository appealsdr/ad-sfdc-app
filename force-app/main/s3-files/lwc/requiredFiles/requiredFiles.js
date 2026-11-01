import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import getRequiredFiles from '@salesforce/apex/RequiredFileController.getRequiredFiles';
import getDocumentTemplates from '@salesforce/apex/RequiredFileController.getDocumentTemplates';
import createRequiredFileDefault from '@salesforce/apex/RequiredFileController.createRequiredFileDefault';
import createRequiredFileFromTemplate from '@salesforce/apex/RequiredFileController.createRequiredFileFromTemplate';
import getDocumentAccess from '@salesforce/apex/S3DocumentController.getDocumentAccess';
import REQUIRED_FILE_OBJECT from '@salesforce/schema/Required_File__c';
import ACCEPTED_FORMAT_FIELD from '@salesforce/schema/Required_File__c.Accepted_Format__c';

const CREATE_MODE_DEFAULT = 'default';
const CREATE_MODE_TEMPLATE = 'template';

const CREATE_MODE_OPTIONS = [
    { label: 'Default', value: CREATE_MODE_DEFAULT },
    { label: 'From Template', value: CREATE_MODE_TEMPLATE }
];

export default class RequiredFiles extends NavigationMixin(LightningElement) {
    @api recordId;

    @track requiredFiles = [];
    @track filteredFiles = [];
    @track templates = [];
    @track acceptedFormatOptions = [];

    searchTerm = '';
    isLoading = true;
    isCreateModalOpen = false;
    isPreviewModalOpen = false;
    isPreviewLoading = false;
    isSaving = false;
    createMode = CREATE_MODE_DEFAULT;

    defaultName = '';
    defaultShortDescription = '';
    defaultInstructions = '';
    selectedAcceptedFormats = [];
    selectedTemplateId;

    previewUrl;
    previewType = 'None';
    previewFileName;
    previewDocumentId;
    previewIsPreviewable = false;
    previewContentType;

    wiredRequiredFilesResult;
    wiredTemplatesResult;

    @wire(getObjectInfo, { objectApiName: REQUIRED_FILE_OBJECT })
    requiredFileObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$requiredFileObjectInfo.data.defaultRecordTypeId',
        fieldApiName: ACCEPTED_FORMAT_FIELD
    })
    wiredAcceptedFormatPicklist({ data, error }) {
        if (data) {
            this.acceptedFormatOptions = data.values.map((entry) => ({
                label: entry.label,
                value: entry.value
            }));
        } else if (error) {
            this.acceptedFormatOptions = [];
        }
    }

    @wire(getRequiredFiles, { recordId: '$recordId' })
    wiredRequiredFiles(result) {
        this.wiredRequiredFilesResult = result;
        this.isLoading = false;

        const { data, error } = result;
        if (data) {
            this.requiredFiles = data.map((file) => ({
                ...file,
                hasUploadedFile: file.fileUploaded && file.uploadedFileName
            }));
            this.applySearchFilter();
        } else if (error) {
            this.requiredFiles = [];
            this.filteredFiles = [];
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    @wire(getDocumentTemplates, { recordId: '$recordId' })
    wiredDocumentTemplates(result) {
        this.wiredTemplatesResult = result;
        const { data, error } = result;
        if (data) {
            this.templates = data;
        } else if (error) {
            this.templates = [];
        }
    }

    get hasFiles() {
        return this.filteredFiles.length > 0;
    }

    get noFiles() {
        return !this.isLoading && this.filteredFiles.length === 0;
    }

    get isDefaultMode() {
        return this.createMode === CREATE_MODE_DEFAULT;
    }

    get isTemplateMode() {
        return this.createMode === CREATE_MODE_TEMPLATE;
    }

    get createModeOptions() {
        return CREATE_MODE_OPTIONS;
    }

    get disableSaveDefault() {
        return this.isSaving
            || !this.defaultName
            || !this.defaultShortDescription
            || this.selectedAcceptedFormats.length === 0;
    }

    get disableSaveTemplate() {
        return this.isSaving || !this.selectedTemplateId;
    }

    get templateColumns() {
        return [
            { label: 'Template Name', fieldName: 'name' },
            { label: 'Short Description', fieldName: 'shortDescription' },
            { label: 'Accepted Format', fieldName: 'acceptedFormat' }
        ];
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
        return this.previewDocumentId && !this.previewIsPreviewable && !this.isPreviewLoading;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
        this.applySearchFilter();
    }

    handleNewClick() {
        this.resetCreateForm();
        this.isCreateModalOpen = true;
    }

    handleCloseCreateModal() {
        this.isCreateModalOpen = false;
    }

    handleCreateModeChange(event) {
        this.createMode = event.target.value;
    }

    handleDefaultNameChange(event) {
        this.defaultName = event.target.value;
    }

    handleDefaultShortDescriptionChange(event) {
        this.defaultShortDescription = event.detail.value;
    }

    handleDefaultInstructionsChange(event) {
        this.defaultInstructions = event.detail.value;
    }

    handleAcceptedFormatChange(event) {
        this.selectedAcceptedFormats = event.detail.value;
    }

    handleTemplateSelection(event) {
        const selectedRows = event.detail.selectedRows || [];
        this.selectedTemplateId = selectedRows.length ? selectedRows[0].id : null;
    }

    handleNameClick(event) {
        const fileId = event.currentTarget.dataset.id;
        if (!fileId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: fileId,
                objectApiName: 'Required_File__c',
                actionName: 'view'
            }
        });
    }

    handleUploadedFileClick(event) {
        const fileId = event.currentTarget.dataset.id;
        const file = this.requiredFiles.find((item) => item.id === fileId);
        if (!file || !file.lastVersionId) {
            return;
        }
        this.openPreview(file);
    }

    handleClosePreviewModal() {
        this.isPreviewModalOpen = false;
        this.clearPreview();
    }

    handleDownloadPreview() {
        if (!this.previewDocumentId) {
            return;
        }

        getDocumentAccess({
            documentId: this.previewDocumentId,
            accessType: 'download'
        })
            .then((access) => {
                window.open(access.url, '_blank');
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }

    async handleSaveDefault() {
        if (this.disableSaveDefault) {
            return;
        }

        this.isSaving = true;
        try {
            await createRequiredFileDefault({
                recordId: this.recordId,
                name: this.defaultName.trim(),
                acceptedFormat: this.selectedAcceptedFormats.join(';'),
                shortDescription: this.defaultShortDescription.trim(),
                instructions: this.defaultInstructions
            });
            this.showToast('Success', 'Required file created.', 'success');
            this.isCreateModalOpen = false;
            await refreshApex(this.wiredRequiredFilesResult);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveTemplate() {
        if (this.disableSaveTemplate) {
            return;
        }

        this.isSaving = true;
        try {
            await createRequiredFileFromTemplate({
                recordId: this.recordId,
                templateId: this.selectedTemplateId
            });
            this.showToast('Success', 'Required file created from template.', 'success');
            this.isCreateModalOpen = false;
            await refreshApex(this.wiredRequiredFilesResult);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    openPreview(file) {
        this.previewDocumentId = file.lastVersionId;
        this.previewFileName = file.uploadedFileName || file.name;
        this.isPreviewModalOpen = true;
        this.isPreviewLoading = true;
        this.previewUrl = null;
        this.previewType = 'None';
        this.previewIsPreviewable = false;

        getDocumentAccess({
            documentId: file.lastVersionId,
            accessType: 'preview'
        })
            .then((access) => {
                this.previewUrl = access.url;
                this.previewType = access.previewType || 'None';
                this.previewIsPreviewable = access.isPreviewable;
                this.previewContentType = access.contentType;
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
                this.isPreviewModalOpen = false;
            })
            .finally(() => {
                this.isPreviewLoading = false;
            });
    }

    applySearchFilter() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) {
            this.filteredFiles = [...this.requiredFiles];
            return;
        }

        this.filteredFiles = this.requiredFiles.filter((file) => {
            const name = (file.name || '').toLowerCase();
            const shortDescription = (file.shortDescription || '').toLowerCase();
            const uploadedLabel = (file.uploadedLabel || '').toLowerCase();
            const uploadedFileName = (file.uploadedFileName || '').toLowerCase();
            return name.includes(term)
                || shortDescription.includes(term)
                || uploadedLabel.includes(term)
                || uploadedFileName.includes(term);
        });
    }

    resetCreateForm() {
        this.createMode = CREATE_MODE_DEFAULT;
        this.defaultName = '';
        this.defaultShortDescription = '';
        this.defaultInstructions = '';
        this.selectedAcceptedFormats = [];
        this.selectedTemplateId = null;
    }

    clearPreview() {
        this.previewUrl = null;
        this.previewType = 'None';
        this.previewFileName = null;
        this.previewDocumentId = null;
        this.previewIsPreviewable = false;
        this.previewContentType = null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}