/******************************************************************************
@author:      Pradeep Kumar
@date:        02 Sep 2025
@description: Trigger Handler for Case_Team_Member__c
*******************************************************************************/
public class CaseTeamMemberHandler extends TriggerFrameworkService {

    private List<Case_Team_Member__c> lstNewTeamMember;
    private List<Case_Team_Member__c> lstOldTeamMember;

    public static String TRIGGER_HANDLER_NAME = 'CaseTeamMemberHandler';

    public CaseTeamMemberHandler() {
        this.lstNewTeamMember = (Trigger.new != null) ? (List<Case_Team_Member__c>) Trigger.new : new List<Case_Team_Member__c>();
        this.lstOldTeamMember = (Trigger.old != null) ? (List<Case_Team_Member__c>) Trigger.old : new List<Case_Team_Member__c>();
    }

    /* Before Insert */
    public override void beforeInsert() {
        try {
            processBeforeInsert(lstNewTeamMember);
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /* After Insert */
    public override void afterInsert() {
        try {
            processAfterInsert(lstNewTeamMember);
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /* Before Delete */
    public override void beforeDelete() {
        try {
            processBeforeDelete(lstOldTeamMember);
        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        } finally {
            Logger.flushLogs();
        }
    }

    /*******************************************************
     * Validate duplicate assignments before insert
    *******************************************************/
    public static void processBeforeInsert(List<Case_Team_Member__c> newAssignments) {
        //  System.debug('processBeforeInsert==>'+newAssignments);
        if (newAssignments.isEmpty()) return;

        // Build sets of Case and User IDs
        Set<Id> caseIds = new Set<Id>(); 
        Set<Id> userIds = new Set<Id>(); 
        for (Case_Team_Member__c rec : newAssignments) { 
            if (rec.Case__c != null && rec.User__c != null) {
                 caseIds.add(rec.Case__c); 
                 userIds.add(rec.User__c); 
            } 
        } 
        // System.debug('caseIds==>'+caseIds.size());
       // System.debug('userIds==>'+userIds.size());
        if (caseIds.isEmpty() || userIds.isEmpty()) return;

        Set<String> existingKeys = new Set<String>();
        for (Case_Team_Member__c rec : [
            SELECT Case__c, User__c, Member_Role__c FROM Case_Team_Member__c
            WHERE Case__c IN :caseIds
            AND User__c IN :userIds
        ]) {
            existingKeys.add(rec.Case__c + '-' + rec.User__c + '-' + rec.Member_Role__c);
        }
        //System.debug('existingKeys==>'+existingKeys);
        for (Case_Team_Member__c rec : newAssignments) {
            String key = rec.Case__c + '-' + rec.User__c+ '-' + rec.Member_Role__c;
           // System.debug('key==>'+key);
            if (existingKeys.contains(key)) {
                rec.addError('This User is already assigned to this Case.');
            }
        }
    }

    /*******************************************************
     * Share Cases and related Opportunities after insert
    *******************************************************/
    public static void processAfterInsert(List<Case_Team_Member__c> newAssignments) {
        if (newAssignments.isEmpty()) return;

        try {
            List<CaseShare> caseShares = new List<CaseShare>();
            List<OpportunityShare> oppShares = new List<OpportunityShare>();

            Set<Id> caseIds = new Set<Id>();
            Map<Id, Set<Id>> caseToUsers = new Map<Id, Set<Id>>();

            for (Case_Team_Member__c assignment : newAssignments) {
                if (assignment.Case__c != null && assignment.User__c != null) {
                    caseIds.add(assignment.Case__c);
                    if (!caseToUsers.containsKey(assignment.Case__c)) {
                        caseToUsers.put(assignment.Case__c, new Set<Id>());
                    }
                    caseToUsers.get(assignment.Case__c).add(assignment.User__c);
                }
            }
            if (caseIds.isEmpty()) return;

            Map<Id, Id> caseToAccount = new Map<Id, Id>();
            Set<Id> accountIds = new Set<Id>();
            for (Case c : [SELECT Id, AccountId FROM Case WHERE Id IN :caseIds AND AccountId != null]) {
                caseToAccount.put(c.Id, c.AccountId);
                accountIds.add(c.AccountId);
            }

            Map<Id, List<Opportunity>> accountToOpps = new Map<Id, List<Opportunity>>();
            for (Opportunity opp : [SELECT Id, AccountId FROM Opportunity WHERE AccountId IN :accountIds]) {
                if (!accountToOpps.containsKey(opp.AccountId)) {
                    accountToOpps.put(opp.AccountId, new List<Opportunity>());
                }
                accountToOpps.get(opp.AccountId).add(opp);
            }

            for (Id caseId : caseToUsers.keySet()) {
                for (Id userId : caseToUsers.get(caseId)) {
                    caseShares.add(new CaseShare(
                        CaseId = caseId,
                        UserOrGroupId = userId,
                        CaseAccessLevel = 'Edit',
                        RowCause = Schema.CaseShare.RowCause.Manual
                    ));

                    Id accId = caseToAccount.get(caseId);
                    if (accId != null && accountToOpps.containsKey(accId)) {
                        for (Opportunity opp : accountToOpps.get(accId)) {
                            oppShares.add(new OpportunityShare(
                                OpportunityId = opp.Id,
                                UserOrGroupId = userId,
                                OpportunityAccessLevel = 'Edit',
                                RowCause = Schema.OpportunityShare.RowCause.Manual
                            ));
                        }
                    }
                }
            }

            if (!caseShares.isEmpty()) insert caseShares;
            if (!oppShares.isEmpty()) insert oppShares;

        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        }
    }

    /*******************************************************
     * Remove Case and Opportunity shares on delete
    *******************************************************/
    public static void processBeforeDelete(List<Case_Team_Member__c> oldAssignments) {
        if (oldAssignments.isEmpty()) return;

        try {
            Set<Id> caseIds = new Set<Id>();
            Map<Id, Set<Id>> caseToUsers = new Map<Id, Set<Id>>();

            for (Case_Team_Member__c assignment : oldAssignments) {
                if (assignment.CreatedById != UserInfo.getUserId()) {
                    assignment.addError('Only the record owner can delete this Case Team Member record.');
                }
                if (assignment.Case__c != null && assignment.User__c != null) {
                    caseIds.add(assignment.Case__c);
                    if (!caseToUsers.containsKey(assignment.Case__c)) {
                        caseToUsers.put(assignment.Case__c, new Set<Id>());
                    }
                    caseToUsers.get(assignment.Case__c).add(assignment.User__c);
                }
            }
            if (caseIds.isEmpty()) return;

            Map<Id, Id> caseToAccount = new Map<Id, Id>();
            Set<Id> accountIds = new Set<Id>();
            for (Case c : [SELECT Id, AccountId FROM Case WHERE Id IN :caseIds AND AccountId != null]) {
                caseToAccount.put(c.Id, c.AccountId);
                accountIds.add(c.AccountId);
            }

            Map<Id, List<Opportunity>> accountToOpps = new Map<Id, List<Opportunity>>();
            for (Opportunity opp : [SELECT Id, AccountId FROM Opportunity WHERE AccountId IN :accountIds]) {
                if (!accountToOpps.containsKey(opp.AccountId)) {
                    accountToOpps.put(opp.AccountId, new List<Opportunity>());
                }
                accountToOpps.get(opp.AccountId).add(opp);
            }

            List<CaseShare> caseSharesToDelete = new List<CaseShare>();
            List<OpportunityShare> oppSharesToDelete = new List<OpportunityShare>();

            for (Id caseId : caseToUsers.keySet()) {
                for (Id userId : caseToUsers.get(caseId)) {
                    caseSharesToDelete.addAll([SELECT Id FROM CaseShare WHERE CaseId = :caseId AND UserOrGroupId = :userId]);

                    Id accId = caseToAccount.get(caseId);
                    if (accId != null && accountToOpps.containsKey(accId)) {
                        oppSharesToDelete.addAll([
                            SELECT Id FROM OpportunityShare
                            WHERE OpportunityId IN :accountToOpps.get(accId)
                            AND UserOrGroupId = :userId
                        ]);
                    }
                }
            }

            if (!caseSharesToDelete.isEmpty()) delete caseSharesToDelete;
            if (!oppSharesToDelete.isEmpty()) delete oppSharesToDelete;

        } catch (Exception ex) {
            Logger.logException(ex, TRIGGER_HANDLER_NAME);
        }
    }
}