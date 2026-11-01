/******************************************************************************
@author:      Pradeep Kumar
@date:        2 Sept 2025
@description: Trigger for Case_Comment__c
*******************************************************************************///before insert
trigger CaseCommentTrigger on Case_Comment__c (before insert,after insert) {
    TriggerFrameworkService.triggerObj = 'CaseComments';
    new CaseCommentTriggerHandler().run();
}