trigger CaseTrigger on Case(
  before insert,
  before update,
  after insert,
  after update,
  after delete,
  after undelete
) {
  try {
    /*  Custom Setting */
    if (!CaseTriggerControl.isCaseTriggerEnabled()) {
      return;
    }
    /* --------------------------
         BEFORE LOGIC
      ---------------------------*/
    if (Trigger.isBefore && Trigger.isInsert) {
      CaseTriggerHandler.copyProductOnboardingConfig(Trigger.new);
    }
    /* --------------------------
         AFTER LOGIC
      ---------------------------*/
    if (Trigger.isAfter) {
      if (Trigger.isInsert) {
        ProductRequiredFileService.createForCases(Trigger.new);
      }
      if (CaseTriggerControl.isUpdateTotalCaseEnabled()) {
        List<Case> caseList = Trigger.isDelete ? Trigger.old : Trigger.new;
        Map<Id, Case> oldMap = Trigger.isInsert || Trigger.isUndelete
          ? null
          : Trigger.oldMap;
        CaseTriggerHandler.updateStoreCaseCounts(caseList, oldMap);
      }
    }
  } catch (Exception ex) {
    ApplicationErrorLogger.capture(ex, 'CaseTrigger');
    throw ex;
  }
}
