import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import requestFileAgain from '@salesforce/apex/FileVerificationFailureController.requestFileAgain';
import CASE_FILE_INFO from '@salesforce/schema/Case_File__c.Info__c';

export default class FileVerificationFailure extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    fields = [CASE_FILE_INFO];
    @track infoValue;

    handleInfoChange(event) {
        this.infoValue = event.target.value;
    }

    handleRequestFileAgainClick() {
    requestFileAgain({
        caseFileId: this.recordId,
        infoValue: this.infoValue
    })
    .then(newRecordId => {
        this.showToast('Success', 'New Case File has been created.', 'success');

        // Close the Quick Action modal first
        this.closeAction();

        // Navigate to the new record after a short delay
        setTimeout(() => {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: newRecordId,
                    actionName: 'view'
                }
            });
        }, 300); // 300ms delay ensures modal is closed
    })
    .catch(error => {
        this.showToast('Error', error.body.message, 'error');
    });
}


    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: this.objectApiName,
                actionName: 'view'
            }
        });
    }
}