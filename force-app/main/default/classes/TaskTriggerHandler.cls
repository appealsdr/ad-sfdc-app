/******************************************************************************
@description: Trigger Handler for Task. Keeps Lead.Total_Calls__c and
              Lead.Last_Call__c in sync via LeadActivityRollupService whenever
              a logged-call Task (TaskSubtype = Call) related to a Lead is
              inserted, updated, deleted, or undeleted.
*******************************************************************************/
public class TaskTriggerHandler extends TriggerFrameworkService {

    private List<Task> lstNewTasks;
    private Map<Id, Task> mapOldTasks;
    public static String TRIGGER_HANDLER_NAME = 'TaskTriggerHandler';

    public TaskTriggerHandler() {
        this.lstNewTasks = (Trigger.new != null) ? (List<Task>) Trigger.new : new List<Task>();
        this.mapOldTasks = (Trigger.oldMap != null) ? (Map<Id, Task>) Trigger.oldMap : new Map<Id, Task>();
    }

    public override void afterInsert() {
        try {
            LeadActivityRollupService.recalculateForLeads(collectLeadIds(lstNewTasks, null));
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    public override void afterUpdate() {
        try {
            LeadActivityRollupService.recalculateForLeads(collectLeadIds(lstNewTasks, mapOldTasks));
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
            LeadActivityRollupService.recalculateForLeads(collectLeadIds(lstNewTasks, null));
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /* Collects Lead Ids referenced by Task.WhoId, including the prior WhoId on
       update so a Task reassigned away from a Lead still triggers a recount. */
    private Set<Id> collectLeadIds(List<Task> tasks, Map<Id, Task> oldMap) {
        Set<Id> leadIds = new Set<Id>();
        for (Task t : tasks) {
            addIfLead(leadIds, t.WhoId);
            if (oldMap != null && oldMap.containsKey(t.Id)) {
                addIfLead(leadIds, oldMap.get(t.Id).WhoId);
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