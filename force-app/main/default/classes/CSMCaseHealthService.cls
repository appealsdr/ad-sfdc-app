/** Separate nightly case signal; does not overwrite the CSM's assessment. */
// Scheduled rollups must see all cases, regardless of the scheduling user's field visibility.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class CSMCaseHealthService {
    /** Account identifier supplied by the scheduled flow. */
    public class Request {
        @InvocableVariable(required=true)
        public Id accountId;
    }
    /**
     * Calculates case-only health for all Accounts in a schedule batch.
     * @param requests Flow inputs.
     */
    @InvocableMethod(label='Refresh CSM Case Health Signal')
    public static void refreshFromFlow(List<Request> requests) {
        Set<Id> accountIds = new Set<Id>();
        for (Request request : requests) {
            if (request.accountId != null) {
                accountIds.add(request.accountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }
        Map<Id, String> signals = new Map<Id, String>();
        Datetime nowTime = System.now();
        for (AggregateResult stats : [
            SELECT AccountId accountId, COUNT(Id) openCount, MIN(CreatedDate) oldest
            FROM Case WHERE AccountId IN :accountIds AND IsClosed = false GROUP BY AccountId
        ]) {
            Integer countOpen = (Integer)stats.get('openCount');
            Datetime oldest = (Datetime)stats.get('oldest');
            signals.put((Id)stats.get('accountId'), signalFor(countOpen, oldest, nowTime));
        }
        List<Account> updates = new List<Account>();
        for (Account parent : [SELECT Id FROM Account WHERE Id IN :accountIds]) {
            updates.add(new Account(Id = parent.Id,
                Case_Health_Signal__c = signals.containsKey(parent.Id) ? signals.get(parent.Id) : 'Green',
                Case_Health_Checked_At__c = nowTime));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static String signalFor(Integer countOpen, Datetime oldest, Datetime nowTime) {
        if (countOpen >= 5 || oldest < nowTime.addDays(-14)) {
            return 'Red';
        }
        if (countOpen >= 3 || oldest < nowTime.addDays(-7)) {
            return 'Yellow';
        }
        return 'Green';
    }

}