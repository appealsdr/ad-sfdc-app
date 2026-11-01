/**
 * Backs the csmCallQuestions LWC on the CSM_Call__c record page.
 * Answers live in CSM_Call_Answer__c (one row per question per call).
 * Question 1 also mirrors to CSM_Call__c.Client_Health__c so the Account health rollup keeps working.
 */
public with sharing class CSMCallQuestionsController {

    public class CSMQuestionsException extends Exception {}

    public class AnswerDto {
        @AuraEnabled public Integer questionNumber;
        @AuraEnabled public String response;
        @AuraEnabled public String comment;
    }

    @TestVisible private static final Map<String, String> HEALTH_BY_RESPONSE = new Map<String, String>{
        'Happy' => 'Green',
        'Assistance Needed' => 'Yellow',
        'High Risk' => 'Red'
    };

    @AuraEnabled(cacheable=false)
    public static List<AnswerDto> getAnswers(Id callId) {
        List<AnswerDto> result = new List<AnswerDto>();
        for (CSM_Call_Answer__c a : [
            SELECT Question_Number__c, Response__c, Comment__c
            FROM CSM_Call_Answer__c WHERE CSM_Call__c = :callId
            WITH USER_MODE
        ]) {
            AnswerDto d = new AnswerDto();
            d.questionNumber = Integer.valueOf(a.Question_Number__c);
            d.response = a.Response__c;
            d.comment = a.Comment__c;
            result.add(d);
        }
        return result;
    }

    @AuraEnabled
    public static void saveAnswers(Id callId, List<AnswerDto> answers, List<String> questionTexts) {
        try {
            Map<Integer, CSM_Call_Answer__c> existing = new Map<Integer, CSM_Call_Answer__c>();
            for (CSM_Call_Answer__c a : [
                SELECT Id, Question_Number__c FROM CSM_Call_Answer__c WHERE CSM_Call__c = :callId
                WITH USER_MODE
            ]) {
                existing.put(Integer.valueOf(a.Question_Number__c), a);
            }
            List<CSM_Call_Answer__c> upserts = new List<CSM_Call_Answer__c>();
            List<CSM_Call_Answer__c> deletes = new List<CSM_Call_Answer__c>();
            String q1Response;
            for (AnswerDto d : answers) {
                Boolean blank = String.isBlank(d.response) && String.isBlank(d.comment);
                CSM_Call_Answer__c row = existing.get(d.questionNumber);
                if (d.questionNumber == 1) {
                    q1Response = d.response;
                }
                if (blank) {
                    if (row != null) {
                        deletes.add(row);
                    }
                    continue;
                }
                if (row == null) {
                    row = new CSM_Call_Answer__c(CSM_Call__c = callId, Question_Number__c = d.questionNumber);
                }
                Integer idx = d.questionNumber - 1;
                row.Question__c = (questionTexts != null && idx < questionTexts.size()) ? questionTexts[idx] : null;
                row.Response__c = String.isBlank(d.response) ? null : d.response;
                row.Comment__c = String.isBlank(d.comment) ? null : d.comment;
                upserts.add(row);
            }
            if (!upserts.isEmpty()) {
                upsert as user upserts;
            }
            if (!deletes.isEmpty()) {
                delete as user deletes;
            }
            if (q1Response != null && HEALTH_BY_RESPONSE.containsKey(q1Response)) {
                update as user new CSM_Call__c(Id = callId, Client_Health__c = HEALTH_BY_RESPONSE.get(q1Response));
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Supplies defaults for the standard New Task form without creating a record. */
    @AuraEnabled
    public static Map<String, String> getFollowUpTaskDefaults(Id callId) {
        try {
            CSM_Call__c call = [
                SELECT Account__c, Account__r.Assigned_Tech__c
                FROM CSM_Call__c WHERE Id = :callId WITH USER_MODE
            ];
            Id ownerId = call.Account__r.Assigned_Tech__c;
            if (ownerId == null) {
                List<Store__c> stores = [
                    SELECT OwnerId FROM Store__c WHERE Account__c = :call.Account__c
                    WITH USER_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT 1
                ];
                if (!stores.isEmpty()) ownerId = stores[0].OwnerId;
            }
            return new Map<String, String>{
                'OwnerId' => String.valueOf(ownerId == null ? UserInfo.getUserId() : ownerId),
                'WhatId' => String.valueOf(call.Account__c),
                'CSM_Call__c' => String.valueOf(call.Id)
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}