/******************************************************************************
@description: Trigger Handler for Event. Keeps Lead.Total_Events__c and
              Lead.Last_Event__c in sync via LeadActivityRollupService whenever
              an Event related to a Lead is inserted, updated, deleted, or
              undeleted.
*******************************************************************************/
public class EventTriggerHandler extends TriggerFrameworkService {

    private List<Event> lstNewEvents;
    private Map<Id, Event> mapOldEvents;
    public static String TRIGGER_HANDLER_NAME = 'EventTriggerHandler';

    public EventTriggerHandler() {
        this.lstNewEvents = (Trigger.new != null) ? (List<Event>) Trigger.new : new List<Event>();
        this.mapOldEvents = (Trigger.oldMap != null) ? (Map<Id, Event>) Trigger.oldMap : new Map<Id, Event>();
    }

    public override void afterInsert() {
        try {
            LeadActivityRollupService.recalculateForLeads(collectLeadIds(lstNewEvents, null));
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    public override void afterUpdate() {
        try {
            LeadActivityRollupService.recalculateForLeads(collectLeadIds(lstNewEvents, mapOldEvents));
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    public override void afterDelete() {
        try {
            LeadActivityRollupService.recalculateForLeads(collectLeadIds(Trigger.old, null));
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    public override void afterUndelete() {
        try {
            LeadActivityRollupService.recalculateForLeads(collectLeadIds(lstNewEvents, null));
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /* Collects Lead Ids referenced by Event.WhoId, including the prior WhoId on
       update so an Event reassigned away from a Lead still triggers a recount. */
    private Set<Id> collectLeadIds(List<Event> events, Map<Id, Event> oldMap) {
        Set<Id> leadIds = new Set<Id>();
        for (Event e : events) {
            addIfLead(leadIds, e.WhoId);
            if (oldMap != null && oldMap.containsKey(e.Id)) {
                addIfLead(leadIds, oldMap.get(e.Id).WhoId);
            }
        }
        return leadIds;
    }

    private void addIfLead(Set<Id> leadIds, Id whoId) {
        if (whoId != null && whoId.getSObjectType() == Lead.SObjectType) {
            leadIds.add(whoId);
        }
    }
}