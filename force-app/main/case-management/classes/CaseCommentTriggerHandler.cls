/******************************************************************************
@author:      Pradeep Kumar
@date:        02 Sep 2025
@description: Trigger Handler for Case_Comment__c
*******************************************************************************/
public class CaseCommentTriggerHandler extends TriggerFrameworkService {

    private List<Case_Comment__c> lstNewCaseComments;
    private Map<Id, Case_Comment__c> mapOldCaseComments;
    public static String TRIGGER_HANDLER_NAME = 'CaseCommentTriggerHandler';

    public CaseCommentTriggerHandler() {
        this.lstNewCaseComments = (Trigger.new != null) ? (List<Case_Comment__c>) Trigger.new : new List<Case_Comment__c>();
       // this.mapOldCaseComments = (Trigger.oldMap != null) ? (Map<Id, Case_Comment__c>) Trigger.oldMap : new Map<Id, Case_Comment__c>();
    }

    /* Before Insert */
    public override void beforeInsert() {
        try {
          //  processBeforeInsert(lstNewCaseComments);
        } catch (Exception ex) {
           // Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            //Logger.flushLogs();
        }
    }

    /* After Insert */
    public override void afterInsert() {
        try {
            processAfterInsert(lstNewCaseComments);
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /* After Update */
    public override void afterUpdate() {
      /*  try {
            processAfterUpdate(lstNewCaseComments, mapOldCaseComments);
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }*/
    }

    /***
     * Method Name: processBeforeInsert
     * Params: List<Case_Comment__c> caseComments
     * Description: method to check if owner can be updated.
     ***/
    private void processBeforeInsert(List<Case_Comment__c> caseComments) {
        // TODO: Add logic here
    }

    /***
     * Method Name: processAfterInsert
     * Params: List<Case_Comment__c> caseComments
     * Description: method to check sharing eligibility.
     ***/
    private void processAfterInsert(List<Case_Comment__c> caseComments) {
        Set<Id>ComId = new Set<Id>();
        for(Case_Comment__c cm : caseComments){
            if(cm.Id != null){
              ComId.add(cm.Id);
            }
        }
        if(!ComId.isEmpty()) {
            callCaseCommentApi(ComId);
        }
        // TODO: Add logic here
        
    }
    public Static Void callCaseCommentApi(Set<Id> CommIdSet){
        CaseCommentDataSenderApi.SendCaseCommentDataFromTrigger(CommIdSet,'Create');
    }

    /***
     * Method Name: processAfterUpdate
     * Params: List<Case_Comment__c> newList, Map<Id, Case_Comment__c> oldMap
     * Description: method to check if Case_Comment__c fields updated.
     ***/
    /*private void processAfterUpdate(List<Case_Comment__c> newList, Map<Id, Case_Comment__c> oldMap) {
        // TODO: Add logic here
    }*/
}