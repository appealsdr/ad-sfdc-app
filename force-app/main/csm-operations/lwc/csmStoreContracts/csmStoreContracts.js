import { LightningElement, api } from 'lwc';

export default class CsmStoreContracts extends LightningElement {
    @api contracts = [];

    get hasContracts() { return this.contracts.length > 0; }

    get items() {
        return this.contracts.map((contract) => ({ ...contract,
            url: `/lightning/r/ServiceContract/${contract.Id}/view`,
            products: (contract.ContractLineItems || []).map((line) => ({
                id: line.Id, name: line.PricebookEntry?.Product2?.Name || 'Unnamed product',
                quantity: line.Quantity,
                url: `/lightning/r/ContractLineItem/${line.Id}/view`
            })),
            hasProducts: (contract.ContractLineItems || []).length > 0
        }));
    }
}