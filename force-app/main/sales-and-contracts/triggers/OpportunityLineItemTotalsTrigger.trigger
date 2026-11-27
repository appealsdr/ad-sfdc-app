trigger OpportunityLineItemTotalsTrigger on OpportunityLineItem (
    after insert, after update, after delete, after undelete
) {
    Set<Id> opportunityIds = new Set<Id>();
    if (Trigger.new != null) {
        for (OpportunityLineItem line : Trigger.new) {
            opportunityIds.add(line.OpportunityId);
        }
    }
    if (Trigger.old != null) {
        for (OpportunityLineItem line : Trigger.old) {
            opportunityIds.add(line.OpportunityId);
        }
    }
    OnDemandLineItemTotals.updateOpportunities(opportunityIds);
}
