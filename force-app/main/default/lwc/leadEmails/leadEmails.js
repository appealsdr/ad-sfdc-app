import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ID_FIELD from '@salesforce/schema/Lead.Id';
import EMAIL_OPT_OUT_FIELD from '@salesforce/schema/Lead.HasOptedOutOfEmail';
import EMAIL_FIELD from '@salesforce/schema/Lead.Email';
import CUSTOM_EMAIL_FIELD from '@salesforce/schema/Lead.Custom_Email__c';
import DIRECT_EMAIL_3_FIELD from '@salesforce/schema/Lead.Direct_Email_3__c';
import OFFICE_EMAIL_FIELD from '@salesforce/schema/Lead.Office_Email__c';
import NOT_VALID_EMAIL_FIELD from '@salesforce/schema/Lead.Not_Valid_Email__c';
import NOT_VALID_CUSTOM_EMAIL_FIELD from '@salesforce/schema/Lead.Not_Valid_Custom_Email__c';
import NOT_VALID_DIRECT_EMAIL_3_FIELD from '@salesforce/schema/Lead.Not_Valid_Direct_Email_3__c';
import NOT_VALID_OFFICE_EMAIL_FIELD from '@salesforce/schema/Lead.Not_Valid_Office_Email__c';

// Each email field paired with the checkbox that flags it as not valid.
const EMAILS = [
    { email: EMAIL_FIELD, notValid: NOT_VALID_EMAIL_FIELD },
    { email: CUSTOM_EMAIL_FIELD, notValid: NOT_VALID_CUSTOM_EMAIL_FIELD },
    { email: DIRECT_EMAIL_3_FIELD, notValid: NOT_VALID_DIRECT_EMAIL_3_FIELD },
    { email: OFFICE_EMAIL_FIELD, notValid: NOT_VALID_OFFICE_EMAIL_FIELD }
];

const FIELDS = [EMAIL_OPT_OUT_FIELD, ...EMAILS.flatMap((e) => [e.email, e.notValid])];

export default class LeadEmails extends LightningElement {
    @api recordId;

    lead;
    isSaving = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLead({ data, error }) {
        if (data) {
            this.lead = data;
        } else if (error) {
            this.showError('Could not load lead emails', error);
        }
    }

    get emailOptOut() {
        return this.lead ? getFieldValue(this.lead, EMAIL_OPT_OUT_FIELD) === true : false;
    }

    // Buttons show the current status: blue when the checkbox is off, red when it is on.
    // Colours come from CSS styling hooks, not the brand variant, so the org theme can't recolour them.
    get emailOptOutButton() {
        return this.emailOptOut
            ? { label: 'Email Opt Out', icon: 'utility:ban', cssClass: 'status-btn status-btn_red', title: 'Lead opted out of email. Click to allow emails.' }
            : { label: 'Can Email', icon: 'utility:email', cssClass: 'status-btn status-btn_blue', title: 'Emails allowed. Click to set Email Opt Out.' };
    }

    // Filled-in emails first (in field order), empty email fields at the bottom.
    get rows() {
        const rows = EMAILS.map((e) => {
            const notValid = this.lead ? getFieldValue(this.lead, e.notValid) === true : false;
            const hasEmail = this.lead ? Boolean(getFieldValue(this.lead, e.email)) : false;
            return {
                key: e.email.fieldApiName,
                hasEmail,
                rowClass: ['email-row', hasEmail ? '' : 'email-row_empty', hasEmail && notValid ? 'email-row_invalid' : '']
                    .filter(Boolean)
                    .join(' '),
                emailField: e.email.fieldApiName,
                notValidField: e.notValid.fieldApiName,
                label: notValid ? 'Not Valid' : 'Valid',
                icon: notValid ? 'utility:close' : 'utility:check',
                buttonClass: notValid ? 'status-btn status-btn_red' : 'status-btn status-btn_blue',
                title: notValid ? 'Email is not valid. Click to mark as valid.' : 'Email is valid. Click to mark as not valid.'
            };
        });
        return [...rows.filter((r) => r.hasEmail), ...rows.filter((r) => !r.hasEmail)];
    }

    // Buttons are never disabled (that would turn them grey); clicks are ignored until the lead
    // has loaded and while a save is in flight.
    handleEmailOptOut() {
        if (!this.lead || this.isSaving) {
            return;
        }
        this.save({ [EMAIL_OPT_OUT_FIELD.fieldApiName]: !this.emailOptOut });
    }

    handleNotValid(event) {
        if (!this.lead || this.isSaving) {
            return;
        }
        const field = event.currentTarget.dataset.field;
        const current = getFieldValue(this.lead, `Lead.${field}`) === true;
        this.save({ [field]: !current });
    }

    async save(changes) {
        this.isSaving = true;
        try {
            await updateRecord({ fields: { [ID_FIELD.fieldApiName]: this.recordId, ...changes } });
        } catch (error) {
            this.showError('Could not update lead', error);
        } finally {
            this.isSaving = false;
        }
    }

    showError(title, error) {
        const message = error?.body?.output?.errors?.[0]?.message || error?.body?.message || error?.message || 'Unknown error';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }
}