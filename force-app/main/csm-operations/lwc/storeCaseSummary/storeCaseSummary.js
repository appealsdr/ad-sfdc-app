import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import getCaseSummary from '@salesforce/apex/StoreCaseSummaryController.getCaseSummary';

const EMPTY_SUMMARY = {
    newCases: 0,
    inProgressCases: 0,
    resolvedCases: 0,
    closedCases: 0
};

export default class StoreCaseSummary extends NavigationMixin(LightningElement) {
    @api recordId;

    summary = { ...EMPTY_SUMMARY };
    error;
    recordTypeOptions = [];
    selectedRecordTypeId;
    showRecordTypeSelector = false;

    @wire(getCaseSummary, { storeId: '$recordId' })
    wiredCaseSummary({ data, error }) {
        if (data) {
            this.summary = { ...EMPTY_SUMMARY, ...data };
            this.error = undefined;
        } else if (error) {
            this.summary = { ...EMPTY_SUMMARY };
            this.error = error;
        }
    }

    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    wiredCaseObjectInfo({ data, error }) {
        if (data) {
            const recordTypeInfos = data.recordTypeInfos || {};

            this.recordTypeOptions = Object.keys(recordTypeInfos)
                .filter(recordTypeId => recordTypeInfos[recordTypeId].available && !recordTypeInfos[recordTypeId].master)
                .map(recordTypeId => ({
                    label: recordTypeInfos[recordTypeId].name,
                    value: recordTypeInfos[recordTypeId].recordTypeId
                }));

            const defaultRecordType = this.recordTypeOptions.find(
                recordType => recordType.value === data.defaultRecordTypeId
            );

            this.selectedRecordTypeId = defaultRecordType?.value || this.recordTypeOptions[0]?.value;
        } else if (error) {
            this.recordTypeOptions = [];
            this.selectedRecordTypeId = undefined;
        }
    }

    get caseGroups() {
        return [
            {
                label: 'New',
                value: this.summary.newCases,
                className: 'summary-item new'
            },
            {
                label: 'In Progress',
                value: this.summary.inProgressCases,
                className: 'summary-item in-progress'
            },
            {
                label: 'Waiting on Client',
                value: this.summary.waitingOnClientCases,
                className: 'summary-item waiting-on-client'
            },
            {
                label: 'Waiting on Amazon',
                value: this.summary.waitingOnAmazonCases,
                className: 'summary-item waiting-on-amazon'
            },
            {
                label: 'Resolved',
                value: this.summary.resolvedCases,
                className: 'summary-item resolved'
            },
            {
                label: 'Closed',
                value: this.summary.closedCases,
                className: 'summary-item closed'
            }
        ];
    }

    get showError() {
        return Boolean(this.error);
    }

    get disableCreateCase() {
        return !this.selectedRecordTypeId;
    }

    handleRecordTypeChange(event) {
        this.selectedRecordTypeId = event.detail.value;
    }

    handleCancelNewCase() {
        this.showRecordTypeSelector = false;
    }

    handleNewCase() {
        if (!this.selectedRecordTypeId) {
            return;
        }

        const defaultFieldValues = encodeDefaultFieldValues({
            Store__c: this.recordId
        });

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName: 'new'
            },
            state: {
                defaultFieldValues,
                useRecordTypeCheck: 'true'
            }
        });
    }
}