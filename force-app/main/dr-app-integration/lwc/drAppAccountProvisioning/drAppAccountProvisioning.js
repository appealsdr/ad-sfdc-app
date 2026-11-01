import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContactsForAccount from '@salesforce/apex/DrAppProvisioningController.getContactsForAccount';
import provisionAccount from '@salesforce/apex/DrAppProvisioningController.provisionAccount';
import resetPassword from '@salesforce/apex/DrAppProvisioningController.resetPassword';
import sendResetPasswordNotification from '@salesforce/apex/DrAppProvisioningController.sendResetPasswordNotification';

export default class DrAppAccountProvisioning extends LightningElement {
    @api recordId;

    /** Email Template used to notify a contact after a password reset. Configured in App Builder. */
    @api templateId;

    contacts = [];
    selectedContactId;
    temporaryPassword;
    username;
    errorMessage;
    isLoading = false;
    showNotifyConfirm = false;

    @wire(getContactsForAccount, { accountId: '$recordId' })
    wiredContacts({ data, error }) {
        if (data) {
            this.contacts = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.contacts = [];
            this.errorMessage = this.extractErrorMessage(error);
        }
    }

    get contactOptions() {
        return this.contacts.map((c) => ({
            label: `${c.FirstName ? c.FirstName + ' ' : ''}${c.LastName}${c.Email ? ' (' + c.Email + ')' : ''}`,
            value: c.Id
        }));
    }

    get isProvisionDisabled() {
        return this.isLoading || !this.selectedContactId;
    }

    get isResetDisabled() {
        return this.isLoading || !this.selectedContactId;
    }

    handleContactChange(event) {
        this.selectedContactId = event.detail.value;
        this.temporaryPassword = undefined;
        this.username = undefined;
        this.errorMessage = undefined;
    }

    async handleProvision() {
        this.resetOutput();
        this.isLoading = true;
        try {
            const res = await provisionAccount({
                accountId: this.recordId,
                contactId: this.selectedContactId
            });
            this.temporaryPassword = res.temporaryPassword;
            this.username = res.username;
            this.showToast('Success', 'Account/contact provisioned in the Dr App.', 'success');
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleResetPassword() {
        this.resetOutput();
        this.isLoading = true;
        try {
            const res = await resetPassword({ contactId: this.selectedContactId });
            this.temporaryPassword = res.temporaryPassword;
            this.username = res.username;
            this.showToast('Success', 'Password reset in the Dr App.', 'success');
            this.showNotifyConfirm = true;
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleNotifyNo() {
        this.showNotifyConfirm = false;
    }

    async handleNotifyYes() {
        this.showNotifyConfirm = false;

        if (!this.templateId) {
            this.showToast('Error', 'Email template not configured.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            await sendResetPasswordNotification({
                contactId: this.selectedContactId,
                templateId: this.templateId
            });
            this.showToast('Success', 'Reset password notification sent.', 'success');
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    resetOutput() {
        this.errorMessage = undefined;
        this.temporaryPassword = undefined;
        this.username = undefined;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unknown error occurred.';
    }
}