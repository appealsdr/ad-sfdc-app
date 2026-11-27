public without sharing class OnDemandLineItemTotals {
    public static void updateContracts(Set<Id> contractIds) {
        contractIds.remove(null);
        if (contractIds.isEmpty()) {
            return;
        }

        Map<Id, ServiceContract> contracts = new Map<Id, ServiceContract>([
            SELECT Id, Pricebook2.Name, Total_Deposit_Payment__c, Total_Balance__c
            FROM ServiceContract
            WHERE Id IN :contractIds
            FOR UPDATE
        ]);
        Map<Id, Totals> totalsById = new Map<Id, Totals>();
        for (ServiceContract contract : contracts.values()) {
            if (isOnDemand(contract.Pricebook2?.Name)) {
                totalsById.put(contract.Id, new Totals());
            }
        }
        if (totalsById.isEmpty()) {
            return;
        }

        for (ContractLineItem line : [
            SELECT ServiceContractId, TotalPrice, Total_Deposit__c
            FROM ContractLineItem
            WHERE ServiceContractId IN :totalsById.keySet()
        ]) {
            totalsById.get(line.ServiceContractId).add(line.TotalPrice, line.Total_Deposit__c);
        }
        saveChanges(contracts.values(), totalsById);
    }

    public static void updateOpportunities(Set<Id> opportunityIds) {
        opportunityIds.remove(null);
        if (opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> opportunities = new Map<Id, Opportunity>([
            SELECT Id, Pricebook2.Name, Total_Deposit_Payment__c, Total_Balance__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            FOR UPDATE
        ]);
        Map<Id, Totals> totalsById = new Map<Id, Totals>();
        for (Opportunity opportunity : opportunities.values()) {
            if (isOnDemand(opportunity.Pricebook2?.Name)) {
                totalsById.put(opportunity.Id, new Totals());
            }
        }
        if (totalsById.isEmpty()) {
            return;
        }

        for (OpportunityLineItem line : [
            SELECT OpportunityId, TotalPrice, Deposit__c, Quantity, Discount
            FROM OpportunityLineItem
            WHERE OpportunityId IN :totalsById.keySet()
        ]) {
            Decimal deposit = line.Deposit__c == null
                ? 0
                : line.Deposit__c * line.Quantity * (1 - (line.Discount ?? 0) / 100);
            totalsById.get(line.OpportunityId).add(line.TotalPrice, deposit.setScale(2, RoundingMode.HALF_UP));
        }
        saveChanges(opportunities.values(), totalsById);
    }

    private static Boolean isOnDemand(String pricebookName) {
        // The payment schedule treats regular price books as on-demand.
        return pricebookName != 'Reccuring' && pricebookName != 'Recurring'
            && pricebookName != 'Subscriptions'
            && pricebookName != 'White Glove' && pricebookName != 'White Gloves';
    }

    private static void saveChanges(List<SObject> parents, Map<Id, Totals> totalsById) {
        List<SObject> updates = new List<SObject>();
        for (SObject parent : parents) {
            Totals totals = totalsById.get(parent.Id);
            if (totals == null) {
                continue;
            }
            Decimal deposit = totals.deposit.setScale(2, RoundingMode.HALF_UP);
            Decimal balance = (totals.amount - deposit).setScale(2, RoundingMode.HALF_UP);
            if (parent.get('Total_Deposit_Payment__c') != deposit
                || parent.get('Total_Balance__c') != balance) {
                SObject change = parent.getSObjectType().newSObject(parent.Id);
                change.put('Total_Deposit_Payment__c', deposit);
                change.put('Total_Balance__c', balance);
                updates.add(change);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private class Totals {
        Decimal amount = 0;
        Decimal deposit = 0;

        void add(Decimal lineAmount, Decimal lineDeposit) {
            amount += lineAmount ?? 0;
            deposit += lineDeposit ?? 0;
        }
    }
}
