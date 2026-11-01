trigger CSMCallLifecycle on CSM_Call__c (after delete, after undelete) {
    CSMAccountSummaryService.refreshCalls(Trigger.isDelete ? Trigger.old : Trigger.new);
}