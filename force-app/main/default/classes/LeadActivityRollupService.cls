/******************************************************************************
@description: Recalculates Lead activity rollup fields (Total_Calls__c,
              Last_Call__c, Total_Events__c, Last_Event__c) from the Task and
              Event records related to each Lead via WhoId. Called by
              TaskTriggerHandler and EventTriggerHandler.
*******************************************************************************/
public with sharing class LeadActivityRollupService {

    public static void recalculateForLeads(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> callCountByLead = new Map<Id, Integer>();
        Map<Id, Datetime> lastCallByLead = new Map<Id, Datetime>();
        for (Task t : [
            SELECT WhoId, CreatedDate
            FROM Task
            WHERE WhoId IN :leadIds AND TaskSubtype = 'Call'
        ]) {
            callCountByLead.put(t.WhoId, (callCountByLead.containsKey(t.WhoId) ? callCountByLead.get(t.WhoId) : 0) + 1);
            if (lastCallByLead.get(t.WhoId) == null || t.CreatedDate > lastCallByLead.get(t.WhoId)) {
                lastCallByLead.put(t.WhoId, t.CreatedDate);
            }
        }

        Map<Id, Integer> eventCountByLead = new Map<Id, Integer>();
        Map<Id, Datetime> lastEventByLead = new Map<Id, Datetime>();
        for (Event e : [
            SELECT WhoId, StartDateTime
            FROM Event
            WHERE WhoId IN :leadIds
        ]) {
            eventCountByLead.put(e.WhoId, (eventCountByLead.containsKey(e.WhoId) ? eventCountByLead.get(e.WhoId) : 0) + 1);
            if (e.StartDateTime != null &&
                (lastEventByLead.get(e.WhoId) == null || e.StartDateTime > lastEventByLead.get(e.WhoId))) {
                lastEventByLead.put(e.WhoId, e.StartDateTime);
            }
        }

        List<Lead> leadsToUpdate = new List<Lead>();
        for (Id leadId : leadIds) {
            leadsToUpdate.add(new Lead(
                Id = leadId,
                Total_Calls__c = callCountByLead.containsKey(leadId) ? callCountByLead.get(leadId) : 0,
                Last_Call__c = lastCallByLead.get(leadId),
                Total_Events__c = eventCountByLead.containsKey(leadId) ? eventCountByLead.get(leadId) : 0,
                Last_Event__c = lastEventByLead.get(leadId)
            ));
        }

        update leadsToUpdate;
    }
}