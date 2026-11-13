public with sharing class ContractLineItemPaymentService {
    private static final String TOTAL_TYPE = 'First Payment';

    public static void createInitialPayments(List<ContractLineItem> insertedLines) {
        if (insertedLines.isEmpty() || isFormAppUser()) return;

        Set<Id> contractIds = new Set<Id>();
        for (ContractLineItem line : insertedLines) {
            if (line.ServiceContractId != null) contractIds.add(line.ServiceContractId);
        }
        if (contractIds.isEmpty()) return;

        // A Salesforce user may add a line to a contract originally created by
        // the Form app. Keep that contract excluded as well.
        Map<Id, Id> creatorByContract = new Map<Id, Id>();
        Set<Id> creatorIds = new Set<Id>();
        for (ServiceContract contract : [
            SELECT Id, CreatedById FROM ServiceContract WHERE Id IN :contractIds
        ]) {
            creatorByContract.put(contract.Id, contract.CreatedById);
            creatorIds.add(contract.CreatedById);
        }
        Set<Id> formAppUserIds = new Set<Id>();
        for (PermissionSetAssignment assignment : [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE AssigneeId IN :creatorIds
            AND PermissionSet.Name = 'DrApp_Integration_API_User'
        ]) {
            formAppUserIds.add(assignment.AssigneeId);
        }
        for (Id contractId : creatorByContract.keySet()) {
            if (formAppUserIds.contains(creatorByContract.get(contractId))) {
                contractIds.remove(contractId);
            }
        }
        if (contractIds.isEmpty()) return;

        Map<Id, List<ContractLineItem>> linesByContract = new Map<Id, List<ContractLineItem>>();
        Set<Id> depositContractIds = new Set<Id>();
        for (ContractLineItem line : [
            SELECT Id, ServiceContractId, Quantity, UnitPrice, Deposit__c,
                   PricebookEntry.Payment_type__c, PricebookEntry.Deposit__c
            FROM ContractLineItem WHERE ServiceContractId IN :contractIds
        ]) {
            if (!linesByContract.containsKey(line.ServiceContractId)) {
                linesByContract.put(line.ServiceContractId, new List<ContractLineItem>());
            }
            linesByContract.get(line.ServiceContractId).add(line);
            if (line.PricebookEntry.Payment_type__c == 'Deposit') {
                depositContractIds.add(line.ServiceContractId);
            }
        }
        if (depositContractIds.isEmpty()) return;

        Map<Id, Payment__c> existingByLine = new Map<Id, Payment__c>();
        Map<Id, Payment__c> existingTotals = new Map<Id, Payment__c>();
        for (Payment__c payment : [
            SELECT Id, Service_Contract__c, Contract_Line_Item__c, Amount__c, Status__c, Payment_Type__c
            FROM Payment__c WHERE Service_Contract__c IN :depositContractIds
        ]) {
            if (payment.Contract_Line_Item__c != null) {
                existingByLine.put(payment.Contract_Line_Item__c, payment);
            } else if (payment.Payment_Type__c == TOTAL_TYPE) {
                existingTotals.put(payment.Service_Contract__c, payment);
            }
        }

        List<Payment__c> toInsert = new List<Payment__c>();
        List<Payment__c> toUpdate = new List<Payment__c>();
        for (Id contractId : depositContractIds) {
            Decimal total = 0;
            for (ContractLineItem line : linesByContract.get(contractId)) {
                String type = line.PricebookEntry.Payment_type__c;
                if (type != 'Full Price' && type != 'Deposit') continue;
                Decimal price = type == 'Deposit'
                    ? (line.Deposit__c == null ? line.PricebookEntry.Deposit__c : line.Deposit__c)
                    : line.UnitPrice;
                if (price == null || line.Quantity == null) continue;
                Decimal amount = price * line.Quantity;
                total += amount;
                if (!existingByLine.containsKey(line.Id)) {
                    toInsert.add(new Payment__c(
                        Service_Contract__c = contractId,
                        Contract_Line_Item__c = line.Id,
                        Payment_Type__c = type,
                        Amount__c = amount,
                        Status__c = 'Pending'
                    ));
                }
            }
            Payment__c totalPayment = existingTotals.get(contractId);
            if (totalPayment == null) {
                toInsert.add(new Payment__c(
                    Service_Contract__c = contractId,
                    Payment_Type__c = TOTAL_TYPE,
                    Amount__c = total,
                    Status__c = 'Pending'
                ));
            } else if (totalPayment.Status__c == 'Pending' && totalPayment.Amount__c != total) {
                totalPayment.Amount__c = total;
                toUpdate.add(totalPayment);
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    // The Dr App API user is assigned this existing permission set. Checking the
    // integration identity keeps API-created contracts out of this automation.
    private static Boolean isFormAppUser() {
        return ![
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = 'DrApp_Integration_API_User'
            LIMIT 1
        ].isEmpty();
    }
}