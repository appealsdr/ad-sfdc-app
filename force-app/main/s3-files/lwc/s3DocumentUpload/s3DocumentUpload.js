import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUploadContext from '@salesforce/apex/S3DocumentUploadController.getUploadContext';
import prepareUpload from '@salesforce/apex/S3DocumentUploadController.prepareUpload';
import uploadFileContent from '@salesforce/apex/S3DocumentUploadController.uploadFileContent';
import finalizeUpload from '@salesforce/apex/S3DocumentUploadController.finalizeUpload';

const MAX_FILE_SIZE_BYTES = 52428800;
const APEX_UPLOAD_MAX_BYTES = 3500000;

export default class S3DocumentUpload extends LightningElement {
    @api recordId;

    uploadContext;
    description = '';
    selectedFiles = [];
    isContextLoading = true;
    isUploading = false;
    uploadProgress = 0;
    uploadStatusMessage = '';

    @wire(getUploadContext, { recordId: '$recordId' })
    wiredUploadContext({ data, error }) {
        this.isContextLoading = false;

        if (data) {
            this.uploadContext = data;
        } else if (error) {
            this.uploadContext = {
                uploadAllowed: false,
                message: this.getErrorMessage(error)
            };
        }
    }

    get uploadAllowed() {
        return this.uploadContext?.uploadAllowed === true;
    }

    get uploadDisabled() {
        return !this.uploadAllowed || this.isUploading || this.selectedFiles.length === 0;
    }

    get hasAcceptedFormats() {
        return (this.uploadContext?.acceptedFormats || []).length > 0;
    }

    get acceptedFormatsLabel() {
        return (this.uploadContext?.acceptedFormats || []).join(', ');
    }

    get pathDescription() {
        return this.uploadContext?.pathDescription || '';
    }

    get contextMessage() {
        return this.uploadContext?.message || '';
    }

    get showProgress() {
        return this.isUploading;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleFileChange(event) {
        const files = Array.from(event.target.files || []);
        const invalidFiles = files.filter((file) => file.size > MAX_FILE_SIZE_BYTES);

        if (invalidFiles.length > 0) {
            this.showToast('Error', 'Each file must be 50 MB or smaller.', 'error');
            event.target.value = null;
            this.selectedFiles = [];
            return;
        }

        this.selectedFiles = files;
        this.uploadStatusMessage = files.length
            ? `${files.length} file(s) selected`
            : '';
    }

    async handleUploadClick() {
        if (this.uploadDisabled) {
            return;
        }

        this.isUploading = true;
        this.uploadProgress = 0;

        try {
            const totalFiles = this.selectedFiles.length;
            for (let index = 0; index < totalFiles; index += 1) {
                const file = this.selectedFiles[index];
                this.uploadStatusMessage = `Uploading ${file.name} (${index + 1} of ${totalFiles})`;
                await this.uploadSingleFile(file);
                this.uploadProgress = Math.round(((index + 1) / totalFiles) * 100);
            }

            this.showToast('Success', 'File upload completed.', 'success');
            this.resetFileInput();
            this.refreshViewer();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isUploading = false;
            this.uploadStatusMessage = '';
        }
    }

    async uploadSingleFile(file) {
        const target = await prepareUpload({
            recordId: this.recordId,
            fileName: file.name,
            contentType: file.type,
            fileSize: file.size
        });

        if (file.size <= APEX_UPLOAD_MAX_BYTES) {
            const fileBodyBase64 = await this.readFileAsBase64(file);
            await uploadFileContent({
                uploadUrl: target.uploadUrl,
                contentType: target.contentType,
                fileBodyBase64
            });
        } else {
            await this.uploadViaBrowserFetch(file, target);
        }

        await finalizeUpload({
            recordId: this.recordId,
            fileName: file.name,
            contentType: target.contentType,
            fileSize: file.size,
            s3Key: target.s3Key,
            description: this.description
        });
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = reader.result;
                if (typeof result !== 'string' || !result.includes(',')) {
                    reject(new Error('Unable to read the selected file.'));
                    return;
                }
                resolve(result.split(',')[1]);
            };
            reader.onerror = () => reject(new Error('Unable to read the selected file.'));
            reader.readAsDataURL(file);
        });
    }

    async uploadViaBrowserFetch(file, target) {
        try {
            const response = await fetch(target.uploadUrl, {
                method: 'PUT',
                body: file,
                headers: {
                    'Content-Type': target.contentType
                }
            });

            if (!response.ok) {
                throw new Error(`S3 upload failed for ${file.name}.`);
            }
        } catch (error) {
            if (error?.message === 'Failed to fetch') {
                throw new Error(
                    'Direct upload to S3 was blocked. Ask your admin to enable the S3 CSP Trusted Site and S3 bucket CORS for browser uploads over 3.5 MB.'
                );
            }
            throw error;
        }
    }

    resetFileInput() {
        this.selectedFiles = [];
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) {
            fileInput.value = null;
        }
    }

    refreshViewer() {
        const viewer = this.template.querySelector('c-s3-document-viewer');
        if (viewer) {
            viewer.refreshDocuments();
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message === 'Failed to fetch') {
            return 'Upload to S3 was blocked by browser security settings. Refresh the page and try again after the S3 CSP Trusted Site is deployed.';
        }
        return error?.message || 'An unexpected error occurred.';
    }
}