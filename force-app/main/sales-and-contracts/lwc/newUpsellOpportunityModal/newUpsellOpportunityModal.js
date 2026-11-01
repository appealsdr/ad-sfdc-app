import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContext from '@salesforce/apex/RelatedOpportunitiesController.getContext';
import getProducts from '@salesforce/apex/RelatedOpportunitiesController.getProducts';
import createOpportunity from '@salesforce/apex/RelatedOpportunitiesController.createOpportunity';

const PRODUCT_COLUMNS = [
    { label: 'Product', fieldName: 'productName', wrapText: true },
    { label: 'Code', fieldName: 'productCode' },
    { label: 'Family', fieldName: 'family' },
    { label: 'Unit Price', fieldName: 'unitPrice', type: 'currency', cellAttributes: { alignment: 'left' } }
];

const STEP_SELECT = 'select';
const STEP_QUANTITY = 'quantity';

export default class NewUpsellOpportunityModal extends LightningModal {
    @api recordId;
    @api pricebookName;

    productColumns = PRODUCT_COLUMNS;
    context;
    products = [];
    loadError;
    searchTerm = '';
    opportunityName = '';
    storeId = null;
    description = '';
    step = STEP_SELECT;
    isSaving = false;

    // pricebookEntryId -> { ...product, quantity }; survives searching and going Back.
    selected = new Map();

    @wire(getContext, { recordId: '$recordId', pricebookName: '$pricebookName' })
    wiredContext({ data, error }) {
        if (data) {
            this.context = data;
            if (!this.opportunityName) {
                this.opportunityName = data.defaultOpportunityName;
            }
            if (!this.storeId && data.defaultStoreId) {
                this.storeId = data.defaultStoreId;
            }
        } else if (error) {
            this.loadError = this.message(error);
        }
    }

    @wire(getProducts, { pricebookName: '$pricebookName' })
    wiredProducts({ data, error }) {
        if (data) {
            this.products = data;
        } else if (error) {
            this.loadError = this.message(error);
        }
    }

    // ----- view state

    get isLoading() {
        return !this.loadError && (!this.context || !this.products);
    }

    get isSelectStep() {
        return this.step === STEP_SELECT;
    }

    get isQuantityStep() {
        return this.step === STEP_QUANTITY;
    }

    get sourceLabel() {
        return this.context ? `${this.context.objectLabel}: ${this.context.sourceName}` : '';
    }

    // Only the account's own stores are offered (same rule as the Opportunity.Store__c lookup filter).
    // A store is required whenever the account has one.
    get storeOptions() {
        return (this.context?.stores || []).map((s) => ({ label: s.label, value: s.storeId }));
    }

    get hasStores() {
        return (this.context?.stores || []).length > 0;
    }

    get storePlaceholder() {
        return this.hasStores ? 'Select a store' : 'This account has no stores';
    }

    get noStoreChoice() {
        return this.missingAccount || !this.hasStores;
    }

    get selectedStore() {
        return (this.context?.stores || []).find((s) => s.storeId === this.storeId);
    }

    get missingAccount() {
        return this.context && !this.context.accountId;
    }

    get filteredProducts() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) {
            return this.products;
        }
        return this.products.filter((p) =>
            [p.productName, p.productCode, p.family].some((v) => v && v.toLowerCase().includes(term))
        );
    }

    get selectedRowKeys() {
        return [...this.selected.keys()];
    }

    get selectedCount() {
        return this.selected.size;
    }

    get nextDisabled() {
        return this.selected.size === 0 || this.missingAccount;
    }

    get lines() {
        return [...this.selected.values()].map((p) => ({
            ...p,
            lineTotal: (Number(p.quantity) || 0) * (p.unitPrice || 0)
        }));
    }

    get grandTotal() {
        return this.lines.reduce((sum, l) => sum + l.lineTotal, 0);
    }

    get saveDisabled() {
        return this.isSaving || this.selected.size === 0 || this.missingAccount;
    }

    // ----- step 1: select products

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleRowSelection(event) {
        // The table only reports rows that are currently visible, so keep selections hidden by the search.
        const visibleIds = new Set(this.filteredProducts.map((p) => p.pricebookEntryId));
        const selectedVisible = new Map(event.detail.selectedRows.map((r) => [r.pricebookEntryId, r]));
        const next = new Map();
        for (const [id, line] of this.selected) {
            if (!visibleIds.has(id) || selectedVisible.has(id)) {
                next.set(id, line);
            }
        }
        for (const [id, row] of selectedVisible) {
            if (!next.has(id)) {
                next.set(id, { ...row, quantity: 1 });
            }
        }
        this.selected = next;
    }

    handleNext() {
        // Check the details box (store, description) before moving on to quantities.
        const fields = [...this.template.querySelectorAll('.summary lightning-combobox, .summary lightning-textarea')];
        const valid = fields.reduce((ok, f) => f.reportValidity() && ok, true);
        if (!valid) {
            return;
        }
        this.step = STEP_QUANTITY;
    }

    // ----- step 2: quantities

    handleQuantity(event) {
        const id = event.target.dataset.id;
        const line = this.selected.get(id);
        if (line) {
            const next = new Map(this.selected);
            next.set(id, { ...line, quantity: event.target.value });
            this.selected = next;
        }
    }

    handleRemove(event) {
        const next = new Map(this.selected);
        next.delete(event.currentTarget.dataset.id);
        this.selected = next;
        if (next.size === 0) {
            this.step = STEP_SELECT;
        }
    }

    handleBack() {
        this.step = STEP_SELECT;
    }

    handleName(event) {
        this.opportunityName = event.target.value;
    }

    handleDescription(event) {
        this.description = event.target.value;
    }

    handleStore(event) {
        this.storeId = event.detail.value || null;
    }

    handleCancel() {
        this.close();
    }

    async handleSave() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea')];
        const valid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        if (!valid) {
            return;
        }
        this.isSaving = true;
        try {
            const opportunityId = await createOpportunity({
                recordId: this.recordId,
                pricebookName: this.pricebookName,
                opportunityName: this.opportunityName,
                storeId: this.storeId,
                description: this.description,
                lines: this.lines.map((l) => ({ pricebookEntryId: l.pricebookEntryId, quantity: Number(l.quantity) }))
            });
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Opportunity created', message: this.opportunityName, variant: 'success' })
            );
            this.close(opportunityId);
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not create Opportunity', message: this.message(error), variant: 'error', mode: 'sticky' }));
        } finally {
            this.isSaving = false;
        }
    }

    message(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}