trigger ContractLineItemTotalsTrigger on ContractLineItem (
    after insert, after update, after delete, after undelete
) {
    Set<Id> contractIds = new Set<Id>();
    if (Trigger.new != null) {
        for (ContractLineItem line : Trigger.new) {
            contractIds.add(line.ServiceContractId);
        }
    }
    if (Trigger.old != null) {
        for (ContractLineItem line : Trigger.old) {
            contractIds.add(line.ServiceContractId);
        }
    }
    OnDemandLineItemTotals.updateContracts(contractIds);
}
