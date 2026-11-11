trigger CaseTrigger on Case (before insert, before update, after insert, after update, after delete, after undelete){
    
    /*  Custom Setting */
    if (!CaseTriggerControl.isCaseTriggerEnabled()) {
        return;
    }
    /* --------------------------
       BEFORE LOGIC
    ---------------------------*/
    if (Trigger.isBefore && Trigger.isInsert) {
        CaseTriggerHandler.copyProductOnboardingConfig(Trigger.new);
        if (CaseTriggerControl.isValidateCaseLimitEnabled()){
            StoreToRetainerCaseHandler.validateCaseLimit(Trigger.new,Trigger.isUpdate ? Trigger.oldMap : null);     
        }
    }
    /* --------------------------
       AFTER LOGIC
    ---------------------------*/
    if (Trigger.isAfter) {
        if (CaseTriggerControl.isUpdateTotalCaseEnabled()) {
            List<Case> caseList = Trigger.isDelete ? Trigger.old : Trigger.new;
            Map<Id, Case> oldMap =Trigger.isInsert || Trigger.isUndelete ? null: Trigger.oldMap;
            CaseTriggerHandler.updateTotalCases(caseList, oldMap); 
            CaseTriggerHandler.updateStoreCaseCounts(caseList, oldMap);
        }
    }
}
