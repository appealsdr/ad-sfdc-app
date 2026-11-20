public with sharing class TimeTrackingActiveUserService {

    /**
     * Keeps Active_User_Key__c consistent with Status__c/Assignee__c on every
     * insert or update, regardless of the write path (Apex, Data Loader,
     * standard UI edit). Combined with the field's unique constraint, this is
     * what guarantees a user can never hold two active/paused records at once.
     */
    public static void applyActiveUserKey(List<Time_Tracking__c> records) {
        for (Time_Tracking__c record : records) {
            if (TimeTrackingConstants.ACTIVE_OR_PAUSED_STATUSES.contains(record.Status__c) && record.Assignee__c != null) {
                record.Active_User_Key__c = String.valueOf(record.Assignee__c);
            } else {
                record.Active_User_Key__c = null;
            }
        }
    }
}
