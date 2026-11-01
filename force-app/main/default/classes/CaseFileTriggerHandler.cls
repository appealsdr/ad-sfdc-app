/******************************************************************************
@author:      Pradeep Kumar
@date:        02 Sep 2025
@description: Trigger Handler for Case_File__c
*******************************************************************************/
public class CaseFileTriggerHandler extends TriggerFrameworkService {

    private List<Case_File__c> lstNewCaseFiles;
    private Map<Id, Case_File__c> mapOldCaseFiles;
    public static String TRIGGER_HANDLER_NAME = 'CaseFileTriggerHandler';

    public CaseFileTriggerHandler() {
        this.lstNewCaseFiles = (Trigger.new != null) ? (List<Case_File__c>) Trigger.new : new List<Case_File__c>();
        this.mapOldCaseFiles = (Trigger.oldMap != null) ? (Map<Id, Case_File__c>) Trigger.oldMap : new Map<Id, Case_File__c>();
    }

    /* Before Insert */
    public override void beforeInsert() {
        try {
            processBeforeInsert(lstNewCaseFiles);
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /* After Insert */
    public override void afterInsert() {
        try {
            processAfterInsert(lstNewCaseFiles);
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /* After Update */
    public override void afterUpdate() {
        try {
            processAfterUpdate(lstNewCaseFiles, mapOldCaseFiles);
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /***
     * Method Name: processBeforeInsert
     * Params: List<Case_File__c> caseFiles
     * Description: method to check if owner can be updated.
     ***/
    private void processBeforeInsert(List<Case_File__c> caseFiles) {
        // TODO: Add logic here
    }

    /***
     * Method Name: processAfterInsert
     * Params: List<Case_File__c> caseFiles
     * Description: method to check sharing eligibility.
     ***/
    private void processAfterInsert(List<Case_File__c> caseFiles) {

        // TODO: Add logic here
        for(Case_File__c csf : caseFiles){
            if(csf.id != null){
                Set<Id>csFileId = new Set<Id>();
                csFileId.add(csf.id); 
                callcaseFileApi(csFileId);
            }
         
        }
        
    }
    @future(callout= true)
    public Static void callcaseFileApi(Set<Id>cSFileId){
        CaseFileDataSenderApi.sendCaseFileDataFromTrigger(cSFileId,'Create');
    }

    /***
     * Method Name: processAfterUpdate
     * Params: List<Case_File__c> newList, Map<Id, Case_File__c> oldMap
     * Description: method to check if Case_File__c fields updated.
     ***/
    private void processAfterUpdate(List<Case_File__c> newList, Map<Id, Case_File__c> oldMap) {
        // TODO: Add logic here
    }
}