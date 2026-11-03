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

const DOCUMENT_ACTIONS = [
    { label: 'Preview', name: 'preview' },
    { label: 'View', name: 'view' }
];

const COLUMNS = [
    {
        label: 'File Name',
        fieldName: 'name',
        type: 'button',
        initialWidth: 420,
        typeAttributes: {
            label: { fieldName: 'name' },
            title: { fieldName: 'name' },
            name: 'open',
            variant: 'base'
        },
        cellAttributes: { iconName: { fieldName: 'iconName' } }
    },
    {
        label: 'Short Description',
        fieldName: 'shortDescription',
        type: 'text',
        wrapText: true,
        initialWidth: 300
    },
    { label: 'Uploaded', fieldName: 'uploadedLabel', type: 'text', initialWidth: 100 },
    {
        type: 'action',
        initialWidth: 70,
        typeAttributes: { rowActions: { fieldName: 'rowActions' } }
    }
];

export default class RequiredFiles extends NavigationMixin(LightningElement) {
    @api recordId;

    @track requiredFiles = [];
    @track filteredFiles = [];
    @track templates = [];
    @track acceptedFormatOptions = [];

    searchTerm = '';
    expandedRowIds = [];
    columns = COLUMNS;
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
    previewError;
    selectedPreviewNavigationItem;

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
            this.requiredFiles = data.map((file) => {
                if (file.rowType === 'uploadedFile') {
                    return this.toDocumentRow(file);
                }
                const uploadedFiles = file.uploadedFiles || [];
                const uploadCount = uploadedFiles.length;
                const row = {
                    id: file.id,
                    name: `${file.name} (${uploadCount})`,
                    folderName: file.name,
                    shortDescription: file.shortDescription,
                    uploadedLabel: file.uploadedLabel,
                    uploadCount,
                    rowType: 'requiredFile',
                    iconName: 'utility:open_folder',
                    rowActions: []
                };
                if (uploadedFiles.length) {
                    row._children = uploadedFiles.map((document) => this.toDocumentRow(document, file.id));
                }
                return row;
            });
            this.expandedRowIds = this.expandedRowIds.filter((id) =>
                this.requiredFiles.some((file) => file.id === id && file._children)
            );
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

    get emptyStateMessage() {
        return this.searchTerm.trim()
            ? 'No required files or uploaded files match your search.'
            : 'No required files or uploaded files found for this record.';
    }

    get expandedRows() {
        return this.searchTerm.trim()
            ? this.filteredFiles.filter((file) => file._children?.length).map((file) => file.id)
            : this.expandedRowIds;
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
        return this.previewDocumentId
            && !this.previewIsPreviewable
            && !this.isPreviewLoading
            && !this.previewError;
    }

    get showPreviewError() {
        return this.previewError && !this.isPreviewLoading;
    }

    get previewNavigationItems() {
        return this.requiredFiles.reduce((items, row) => {
            if (row.rowType === 'requiredFile') {
                items.push({
                    navigationName: `folder:${row.id}`,
                    label: row.name,
                    iconName: 'utility:open_folder',
                    isFolder: true,
                    isDocument: false
                });
                (row._children || []).forEach((document) => {
                    items.push({
                        navigationName: `document:${document.documentId}`,
                        label: `↳ ${document.name}`,
                        iconName: 'utility:file',
                        isFolder: false,
                        isDocument: true
                    });
                });
            } else {
                items.push({
                    navigationName: `document:${row.documentId}`,
                    label: row.name,
                    iconName: 'utility:file',
                    isFolder: false,
                    isDocument: true
                });
            }
            return items;
        }, []);
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
        this.applySearchFilter();
    }

    async handleRefresh() {
        if (!this.wiredRequiredFilesResult || this.isLoading) {
            return;
        }

        this.isLoading = true;
        try {
            await refreshApex(this.wiredRequiredFilesResult);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
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

    handleRowAction(event) {
        const { action, row } = event.detail;
        const isDocument = Boolean(row.documentId);
        if (action.name === 'preview' && isDocument) {
            this.openPreview(row);
            return;
        }

        if (action.name === 'view' && isDocument) {
            this.navigateToRecord(row.documentId, 'S3_Document__c');
            return;
        }

        if (action.name !== 'open') {
            return;
        }

        if (isDocument) {
            this.openPreview(row);
            return;
        }

        this.navigateToRecord(row.id, 'Required_File__c');
    }

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    handleRowToggle(event) {
        if (this.searchTerm.trim()) {
            return;
        }
        const { name, isExpanded } = event.detail;
        const expanded = this.expandedRowIds.filter((id) => id !== name);
        this.expandedRowIds = isExpanded ? [...expanded, name] : expanded;
    }

    handleClosePreviewModal() {
        this.isPreviewModalOpen = false;
        this.clearPreview();
    }

    handlePreviewNavigationBeforeSelect(event) {
        const navigationName = event.detail?.name || event.detail;
        if (navigationName?.startsWith('folder:')) {
            event.preventDefault();
        }
    }

    handlePreviewNavigationSelect(event) {
        const navigationName = event.detail?.name || event.detail;
        if (!navigationName?.startsWith('document:')) {
            return;
        }

        const documentId = navigationName.substring('document:'.length);
        const document = this.findDocumentRow(documentId);
        if (document) {
            this.openPreview(document);
        }
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
        const documentId = file.documentId || file.id;
        if (!documentId) {
            this.showToast('Error', 'Document Id is required to open the preview.', 'error');
            return;
        }

        this.previewDocumentId = documentId;
        this.selectedPreviewNavigationItem = `document:${documentId}`;
        this.previewFileName = file.name;
        this.isPreviewModalOpen = true;
        this.isPreviewLoading = true;
        this.previewUrl = null;
        this.previewType = 'None';
        this.previewIsPreviewable = false;
        this.previewError = null;

        getDocumentAccess({
            documentId,
            accessType: 'preview'
        })
            .then((access) => {
                this.previewUrl = access.url;
                this.previewType = access.previewType || 'None';
                this.previewIsPreviewable = access.isPreviewable;
                this.previewContentType = access.contentType;
            })
            .catch((error) => {
                this.previewError = this.getErrorMessage(error);
            })
            .finally(() => {
                this.isPreviewLoading = false;
            });
    }

    toDocumentRow(document, requiredFileId) {
        return {
            id: requiredFileId ? `${requiredFileId}-${document.id}` : document.id,
            documentId: document.id,
            name: document.name,
            shortDescription: document.shortDescription,
            uploadedLabel: document.uploadedLabel,
            rowType: 'uploadedFile',
            iconName: 'utility:file',
            rowActions: DOCUMENT_ACTIONS
        };
    }

    findDocumentRow(documentId) {
        for (const row of this.requiredFiles) {
            if (row.documentId === documentId) {
                return row;
            }
            const child = (row._children || []).find((document) => document.documentId === documentId);
            if (child) {
                return child;
            }
        }
        return null;
    }

    applySearchFilter() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) {
            this.filteredFiles = [...this.requiredFiles];
            return;
        }

        const matches = (row) => [row.name, row.shortDescription, row.uploadedLabel]
            .some((value) => (value || '').toLowerCase().includes(term));

        this.filteredFiles = this.requiredFiles.reduce((rows, file) => {
            if (matches(file)) {
                rows.push(file);
            } else {
                const children = (file._children || []).filter(matches);
                if (children.length) {
                    rows.push({ ...file, _children: children });
                }
            }
            return rows;
        }, []);
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
        this.previewError = null;
        this.selectedPreviewNavigationItem = null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}
