/** System-context automation keeps parent summaries complete even when callers have restricted field access. */
// Derived rollups intentionally run in system context; callers cannot supply summary field values.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class CSMAccountSummaryService {
    /** Account identifier supplied by the record-triggered flow. */
    public class Request {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    /**
     * Refreshes all Account IDs supplied in the bulk flow invocation.
     * @param requests Flow inputs.
     */
    @InvocableMethod(label='Refresh CSM Account Summary' description='Updates each Account from its latest call, ordered by call date, creation time, then record ID.')
    public static void refreshFromFlow(List<Request> requests) {
        Set<Id> accountIds = new Set<Id>();
        for (Request request : requests) {
            if (request.accountId != null) {
                accountIds.add(request.accountId);
            }
        }
        refresh(accountIds);
    }

    /**
     * Repairs summaries after call deletion or restoration.
     * @param calls Changed call records.
     */
    public static void refreshCalls(List<CSM_Call__c> calls) {
        Set<Id> accountIds = new Set<Id>();
        for (CSM_Call__c callRecord : calls) {
            accountIds.add(callRecord.Account__c);
        }
        refresh(accountIds);
    }

    /**
     * Locks parents and applies current summaries in one bulk update.
     * @param accountIds Accounts to refresh.
     */
    public static void refresh(Set<Id> accountIds) {
        if (accountIds.isEmpty()) {
            return;
        }
        // Serialize changes per Account before reading the winning call.
        List<Account> lockedAccounts = [SELECT Id FROM Account WHERE Id IN :accountIds FOR UPDATE];
        Set<Id> existingIds = new Map<Id, Account>(lockedAccounts).keySet();
        List<Account> updates = new List<Account>();
        for (Account parent : [
            SELECT Id, CSM_Health__c, Priority__c, Latest_CSM_Notes__c,
                (SELECT Client_Health__c, Priority__c, Call_Notes__c
                 FROM CSM_Calls__r ORDER BY Call_Date__c DESC, CreatedDate DESC, Id DESC LIMIT 1)
            FROM Account WHERE Id IN :existingIds
        ]) {
            Account changed = summaryChange(parent);
            if (changed != null) {
                updates.add(changed);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static Account summaryChange(Account parent) {
        CSM_Call__c latest = parent.CSM_Calls__r.isEmpty() ? new CSM_Call__c() : parent.CSM_Calls__r[0];
        String notes = latest.Call_Notes__c == null ? null : latest.Call_Notes__c.left(255);
        if (parent.CSM_Health__c == latest.Client_Health__c && parent.Priority__c == latest.Priority__c && parent.Latest_CSM_Notes__c == notes) {
            return null;
        }
        return new Account(Id = parent.Id, CSM_Health__c = latest.Client_Health__c,
            Priority__c = latest.Priority__c, Latest_CSM_Notes__c = notes); 
    }

}