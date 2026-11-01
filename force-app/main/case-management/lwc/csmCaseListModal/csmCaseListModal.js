import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getCases from '@salesforce/apex/CSMCaseDashboardController.getCases';

const COLUMNS = [
    { label: 'Case', fieldName: 'url', type: 'url', typeAttributes: { label: { fieldName: 'CaseNumber' }, target: '_blank' } },
    { label: 'Subject', fieldName: 'Subject', wrapText: true },
    { label: 'Status', fieldName: 'Status', wrapText: true },
    { label: 'Store', fieldName: 'storeName', wrapText: true },
    { label: 'Service contract', fieldName: 'contractUrl', type: 'url', typeAttributes: { label: { fieldName: 'contractName' }, target: '_blank' }, wrapText: true },
    { label: 'Purchased product', fieldName: 'purchasedProduct', wrapText: true },
    { label: 'Purchased quantity', fieldName: 'purchasedQuantity', type: 'number' },
    { label: 'Type', fieldName: 'Type', wrapText: true },
    { label: 'Category', fieldName: 'Category__c', wrapText: true },
    { label: 'Priority', fieldName: 'Priority' },
    { label: 'Owner', fieldName: 'ownerName', wrapText: true },
    { label: 'Opened', fieldName: 'CreatedDate', type: 'date' }
];
export default class CsmCaseListModal extends LightningModal {
    @api heading;
    @api callId;
    @api metric;
    @api filterStore = false;
    @api storeId;
    @api filterBreakdown = false;
    @api caseType;
    @api category;
    columns = COLUMNS;
    rows = [];
    loading = false;
    error;
    hasMore = false;
    cursor = null;

    connectedCallback() { this.loadCases(); }

    get empty() { return !this.loading && !this.error && this.rows.length === 0; }
    get countLabel() { return `${this.rows.length} cases loaded`; }

    async loadCases() {
        if (this.loading) return;
        this.loading = true;
        this.error = undefined;
        try {
            const page = await getCases({ callId: this.callId, metric: this.metric,
                filterStore: this.filterStore, storeId: this.storeId || null,
                filterBreakdown: this.filterBreakdown, caseType: this.caseType || null,
                category: this.category || null, afterId: this.cursor });
            this.rows = [...this.rows, ...page.records.map((record) => {
                const contractId = record.ServiceContractId || record.Contract__c || record.Contract_Line_Item__r?.ServiceContractId;
                const contractName = record.ServiceContractId ? record.ServiceContract?.Name
                    : (record.Contract__c ? record.Contract__r?.Name : record.Contract_Line_Item__r?.ServiceContract?.Name);
                return { ...record,
                contractUrl: contractId ? `/lightning/r/ServiceContract/${contractId}/view` : null,
                contractName,
                purchasedProduct: record.Contract_Line_Item__r?.PricebookEntry?.Product2?.Name || 'No linked product',
                purchasedQuantity: record.Contract_Line_Item__r?.Quantity,
                url: `/lightning/r/Case/${record.Id}/view`,
                storeName: record.Store__r?.Name || 'No store assigned', ownerName: record.Owner?.Name
            }; })];
            this.cursor = page.nextCursor;
            this.hasMore = page.hasMore;
        } catch (error) {
            this.error = error.body?.message || error.message || 'Unable to load cases.';
        } finally { this.loading = false; }
    }

    handleClose() { this.close(); }
}