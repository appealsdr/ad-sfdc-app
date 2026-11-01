import { LightningElement, wire, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createCaseFile from '@salesforce/apex/CaseFileController.createCaseFile';
import getCaseDocTypeList from '@salesforce/apex/CaseFileController.getCaseDocTypeList';
import { refreshApex } from '@salesforce/apex';

export default class SelectedFileType extends LightningElement {
    @api recordId;
    @track selectedItems = [];
    @track CaseDocTypeListsData = [];
    @track docType = [];
    @track error;
    @track draftValues = [];
    @track wiredCaseDocTypeListResult;

    // Get Case Doc Type list from Apex
    @wire(getCaseDocTypeList)
    wiredCaseDocTypeList(result) {
        this.wiredCaseDocTypeListResult = result;
        const { data, error } = result;
        if (data) {
            // Clean HTML tags from Instructions__c
            this.CaseDocTypeListsData = data.map(item => ({
                ...item,
                Instructions__c: this.stripHtmlTags(item.Instructions__c)
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.CaseDocTypeListsData = undefined;
        }
    }

    stripHtmlTags(html) {
        if (!html) return '';
        const tmp = document.createElement('div');
        tmp.innerHTML = html;
        return tmp.textContent || tmp.innerText || '';
    }


    // Datatable Columns
    columns = [
        { label: 'Case Document Type Label', fieldName: 'Case_Document_Type_Label__c' },
        { label: 'Short Description', fieldName: 'Short_Description__c', editable: true },
        { label: 'Instructions', fieldName: 'Instructions__c', editable: true }
    ];

    handleRowSelection(event) {
        // directly use event.detail.selectedRows
        this.selectedItems = event.detail.selectedRows.map(row => ({
            Id: row.Id,
            Case_Document_Type_Label__c: row.Case_Document_Type_Label__c,
            Short_Description__c: row.Short_Description__c
        }));
        console.log('Selected Items:', JSON.stringify(this.selectedItems));
    }

    handleSaveInlineEdit(event) {
        const updatedFields = event.detail.draftValues;
        // Update CaseDocTypeListsData with new edits
        this.CaseDocTypeListsData = this.CaseDocTypeListsData.map(row => {
            const updatedRow = updatedFields.find(item => item.Id === row.Id);
            return updatedRow ? { ...row, ...updatedRow } : row;
        });

        // Clear draft values
        this.draftValues = [];
    }

    async handleSave() {
        if (!this.selectedItems.length || !this.recordId) {
            this.showToast('Error', 'Please select at least one document type.', 'error');
            return;
        }

        const selectedIds = this.selectedItems.map(item => item.Id);
        const selectedData = this.CaseDocTypeListsData.filter(item => selectedIds.includes(item.Id));

        this.docType = selectedData.map(item => ({
            documentTypeLabel: item.Case_Document_Type_Label__c,
            shortDescription: item.Short_Description__c,
            instructions: item.Instructions__c
        }));

        try {
            const result = await createCaseFile({
                docTypes: this.docType,
                caseId: this.recordId
            });

            if (result === 'Success') {
                this.showToast('Success', 'Case File records created successfully.', 'success');
                this.selectedItems = [];
                this.draftValues = [];

                // Clear selection in datatable
                const dt = this.template.querySelector('lightning-datatable');
                if (dt) dt.selectedRows = [];

                // **Refresh datatable**
                await refreshApex(this.wiredCaseDocTypeListResult);
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    // Show toast helper method
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant, // 'success', 'error', 'warning', 'info'
                mode: 'dismissable' // optional, can be omitted
            })
        );
    }


}