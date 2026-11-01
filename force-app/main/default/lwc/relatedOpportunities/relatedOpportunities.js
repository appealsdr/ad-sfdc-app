import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getOpportunities from '@salesforce/apex/RelatedOpportunitiesController.getOpportunities';
import NewUpsellOpportunityModal from 'c/newUpsellOpportunityModal';

const COLUMNS = [
    {
        label: 'Opportunity',
        fieldName: 'url',
        type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' },
        wrapText: true
    },
    { label: 'Status', fieldName: 'StageName' },
    { label: 'Type', fieldName: 'Type' },
    { label: 'Amount', fieldName: 'Amount', type: 'currency', cellAttributes: { alignment: 'left' } },
    { label: 'Start Date', fieldName: 'CloseDate', type: 'date-local' },
    { label: 'Owner', fieldName: 'ownerName' }
];

export default class RelatedOpportunities extends LightningElement {
    @api recordId;
    @api pricebookName = 'Service';

    columns = COLUMNS;
    opportunities = [];
    error;
    isLoading = true;
    wiredResult;

    @wire(getOpportunities, { recordId: '$recordId' })
    wiredOpportunities(result) {
        this.wiredResult = result;
        if (result.data) {
            this.opportunities = result.data.map((o) => ({
                ...o,
                url: `/lightning/r/Opportunity/${o.Id}/view`,
                ownerName: o.Owner?.Name
            }));
            this.error = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.error = result.error.body?.message || result.error.message;
            this.isLoading = false;
        }
    }

    get cardTitle() {
        return `Opportunities (${this.opportunities.length})`;
    }

    get hasOpportunities() {
        return this.opportunities.length > 0;
    }

    async handleNew() {
        const createdId = await NewUpsellOpportunityModal.open({
            size: 'large',
            label: 'New Opportunity',
            recordId: this.recordId,
            pricebookName: this.pricebookName
        });
        if (createdId) {
            this.isLoading = true;
            await refreshApex(this.wiredResult);
            this.isLoading = false;
        }
    }
}