/******************************************************************************
@author:      Pradeep Kumar
@date:        2 Sept 2025
@description: Trigger for Case_File__c
*******************************************************************************/
trigger CaseFileTrigger on Case_File__c (before insert, before update, before delete, after insert, after Update, after delete, after undelete) {
    TriggerFrameworkService.triggerObj = 'CaseFile';
    new CaseFileTriggerHandler().run();
}