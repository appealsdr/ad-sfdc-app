import { LightningElement, api, wire } from 'lwc';
import CsmCaseListModal from 'c/csmCaseListModal';
import { refreshApex } from '@salesforce/apex';
import getServiceContracts from '@salesforce/apex/CSMCaseDashboardController.getServiceContracts';
import getDashboard from '@salesforce/apex/CSMCaseDashboardController.getDashboard';

export default class CsmCaseDashboard extends LightningElement {
    @api recordId;
    data;
    error;
    loading = true;
    wiredResult;
    wiredContractsResult;
    contracts = [];
    contractsLoading = true;
    contractsError;

    @wire(getServiceContracts, { callId: '$recordId' })
    wiredContracts(result) {
        this.wiredContractsResult = result;
        if (result.data) {
            this.contracts = result.data;
            this.contractsError = undefined;
            this.contractsLoading = false;
        } else if (result.error) {
            this.contracts = [];
            this.contractsError = result.error.body?.message || result.error.message || 'Unable to load service contracts.';
            this.contractsLoading = false;
        }
    }

    get contractGroups() {
        const groups = new Map();
        for (const contract of this.contracts) {
            const storeId = contract.Store__c || contract.Opportunity__r?.Store__c;
            const key = storeId || 'unassigned';
            if (!groups.has(key)) groups.set(key, {
                key, storeName: contract.Store__r?.Name || contract.Opportunity__r?.Store__r?.Name || 'Account contracts · No store assigned', contracts: []
            });
            groups.get(key).contracts.push(contract);
        }
        return groups;
    }

    get additionalContractGroups() {
        const storeKeys = new Set((this.data?.stores || []).map((store) => store.storeId).filter(Boolean));
        return [...this.contractGroups.values()].filter((group) => !storeKeys.has(group.key));
    }

    @wire(getDashboard, { callId: '$recordId' })
    wiredDashboard(result) {
        this.wiredResult = result;
        if (result.data) {
            this.data = result.data;
            this.error = undefined;
            this.loading = false;
        } else if (result.error) {
            this.data = undefined;
            this.error = result.error.body?.message || result.error.message || 'Unable to load case dashboard.';
            this.loading = false;
        }
    }

    get metrics() {
        return [
            { key: 'open', label: 'Open cases', value: this.data.openCount, className: 'metric open' },
            { key: 'closed', label: 'Closed / resolved', value: this.data.closedCount, className: 'metric closed' },
            { key: 'aging', label: 'Aging · over 7 days', value: this.data.agingCount, className: 'metric aging' },
            { key: 'overdue', label: 'Aging · over 14 days', value: this.data.overdueCount, className: 'metric overdue' }
        ];
    }

    get stores() {
        return (this.data?.stores || []).map((store) => {
            const total = store.openCount + store.closedCount;
            // Three exclusive segments: recent open, aging open, and closed.
            const segments = [
                { key: 'recent', label: 'Open, 7 days or less', count: store.openCount - store.agingCount, className: 'segment recent' },
                { key: 'aging', label: 'Open, over 7 days', count: store.agingCount, className: 'segment aged' },
                { key: 'closed', label: 'Closed / resolved', count: store.closedCount, className: 'segment resolved' }
            ].filter((segment) => segment.count > 0).map((segment) => ({
                ...segment,
                style: `width: ${(segment.count / total) * 100}%`,
                title: `${segment.label}: ${segment.count}`
            }));
            return {
                ...store,
                key: store.storeId || 'unassigned',
                total,
                contracts: store.storeId ? (this.contractGroups.get(store.storeId)?.contracts || []) : [],
                showContracts: Boolean(store.storeId) && !this.contractsLoading && !this.contractsError,
                segments,
                chartLabel: `${store.storeName}: ${store.openCount} open, ${store.closedCount} closed or resolved, ${store.agingCount} open over 7 days, ${store.overdueCount} open over 14 days.`,
                breakdowns: store.breakdowns.map((row, index) => ({ ...row, key: `${index}`, total: row.openCount + row.closedCount }))
            };
        });
    }

    get empty() {
        return this.data && this.data.openCount + this.data.closedCount === 0;
    }

    async handleCountClick(event) {
        const { metric, store: storeKey, row: rowKey } = event.currentTarget.dataset;
        const store = this.stores.find((item) => item.key === storeKey);
        const row = store?.breakdowns.find((item) => item.key === rowKey);
        const labels = { all: 'All cases', open: 'Open cases', closed: 'Closed / resolved cases',
            aging: 'Open cases over 7 days', overdue: 'Open cases over 14 days' };
        const title = [labels[metric], store?.storeName, row ? `${row.caseType} / ${row.category}` : null]
            .filter(Boolean).join(' · ');
        await CsmCaseListModal.open({
            size: 'large', label: title, heading: title, callId: this.recordId,
            metric, filterStore: Boolean(store), storeId: store?.storeId || null,
            filterBreakdown: Boolean(row), caseType: row?.caseTypeValue || null,
            category: row?.categoryValue || null
        });
    }

    async handleRefresh() {
        this.loading = true;
        try {
            await Promise.all([refreshApex(this.wiredResult), refreshApex(this.wiredContractsResult)]);
        } catch (error) {
            this.data = undefined;
            this.error = error.body?.message || error.message || 'Unable to refresh case dashboard.';
        } finally {
            this.loading = false;
        }
    }
}