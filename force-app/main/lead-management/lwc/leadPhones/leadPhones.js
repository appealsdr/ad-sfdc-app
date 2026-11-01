import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ID_FIELD from '@salesforce/schema/Lead.Id';
import DO_NOT_CALL_FIELD from '@salesforce/schema/Lead.DoNotCall';
import PHONE_FIELD from '@salesforce/schema/Lead.Phone';
import MOBILE_PHONE_FIELD from '@salesforce/schema/Lead.MobilePhone';
import MOBILE_PHONE_2_FIELD from '@salesforce/schema/Lead.Mobile_Phone_2__c';
import MOBILE_PHONE_3_FIELD from '@salesforce/schema/Lead.Mobile_Phone_3__c';
import MOBILE_PHONE_4_FIELD from '@salesforce/schema/Lead.Mobile_Phone_4__c';
import NOT_VALID_PHONE_FIELD from '@salesforce/schema/Lead.Not_Valid_Phone__c';
import NOT_VALID_MOBILE_PHONE_FIELD from '@salesforce/schema/Lead.Not_Valid_Mobile_Phone__c';
import NOT_VALID_MOBILE_PHONE_2_FIELD from '@salesforce/schema/Lead.Not_Valid_Mobile_Phone_2__c';
import NOT_VALID_MOBILE_PHONE_3_FIELD from '@salesforce/schema/Lead.Not_Valid_Mobile_Phone_3__c';
import NOT_VALID_MOBILE_PHONE_4_FIELD from '@salesforce/schema/Lead.Not_Valid_Mobile_Phone_4__c';

// Each phone field paired with the checkbox that flags it as not valid.
const PHONES = [
    { phone: PHONE_FIELD, notValid: NOT_VALID_PHONE_FIELD },
    { phone: MOBILE_PHONE_FIELD, notValid: NOT_VALID_MOBILE_PHONE_FIELD },
    { phone: MOBILE_PHONE_2_FIELD, notValid: NOT_VALID_MOBILE_PHONE_2_FIELD },
    { phone: MOBILE_PHONE_3_FIELD, notValid: NOT_VALID_MOBILE_PHONE_3_FIELD },
    { phone: MOBILE_PHONE_4_FIELD, notValid: NOT_VALID_MOBILE_PHONE_4_FIELD }
];

const FIELDS = [DO_NOT_CALL_FIELD, ...PHONES.flatMap((p) => [p.phone, p.notValid])];

export default class LeadPhones extends LightningElement {
    @api recordId;

    lead;
    isSaving = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLead({ data, error }) {
        if (data) {
            this.lead = data;
        } else if (error) {
            this.showError('Could not load lead phones', error);
        }
    }

    get doNotCall() {
        return this.lead ? getFieldValue(this.lead, DO_NOT_CALL_FIELD) === true : false;
    }

    // Buttons show the current status: blue when the checkbox is off, red when it is on.
    // Colours come from CSS styling hooks, not the brand variant, so the org theme can't recolour them.
    get doNotCallButton() {
        return this.doNotCall
            ? { label: 'Do Not Call', icon: 'utility:end_call', cssClass: 'status-btn status-btn_red', title: 'Do Not Call is set. Click to allow calls.' }
            : { label: 'Can Call', icon: 'utility:call', cssClass: 'status-btn status-btn_blue', title: 'Calls allowed. Click to set Do Not Call.' };
    }

    // Filled-in numbers first (in field order), empty phone fields at the bottom.
    get rows() {
        const rows = PHONES.map((p) => {
            const notValid = this.lead ? getFieldValue(this.lead, p.notValid) === true : false;
            const hasNumber = this.lead ? Boolean(getFieldValue(this.lead, p.phone)) : false;
            return {
                key: p.phone.fieldApiName,
                hasNumber,
                rowClass: ['phone-row', hasNumber ? '' : 'phone-row_empty', hasNumber && notValid ? 'phone-row_invalid' : '']
                    .filter(Boolean)
                    .join(' '),
                phoneField: p.phone.fieldApiName,
                notValidField: p.notValid.fieldApiName,
                label: notValid ? 'Not Valid' : 'Valid',
                icon: notValid ? 'utility:close' : 'utility:check',
                buttonClass: notValid ? 'status-btn status-btn_red' : 'status-btn status-btn_blue',
                title: notValid ? 'Number is not valid. Click to mark as valid.' : 'Number is valid. Click to mark as not valid.'
            };
        });
        return [...rows.filter((r) => r.hasNumber), ...rows.filter((r) => !r.hasNumber)];
    }

    // Buttons are never disabled (that would turn them grey); clicks are ignored until the lead
    // has loaded and while a save is in flight.
    handleDoNotCall() {
        if (!this.lead || this.isSaving) {
            return;
        }
        this.save({ [DO_NOT_CALL_FIELD.fieldApiName]: !this.doNotCall });
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