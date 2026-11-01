public with sharing class StoreCaseSummaryController {
    private static final String CLOSED_STATUS = 'Closed';
    private static final String RESOLVED_BY_TECH_REASON = 'Resolved by tech';
    private static final Set<String> NEW_STATUSES = new Set<String>{ 'New', 'Draft' };
    private static final Set<String> IN_PROGRESS_STATUSES = new Set<String>{
        'In Progress - Tech',
        'Assigned',
        'Draft'
    };
    private static final Set<String> RESOLVED_STATUSES = new Set<String>{
        'Resolved - Tech',
        'Resolved - Client'
    };

    @AuraEnabled(cacheable=true)
    public static CaseSummary getCaseSummary(Id storeId) {
        CaseSummary summary = new CaseSummary();

        if (storeId == null) {
            return summary;
        }

        List<Case> newCase = [SELECT ID FROM Case WHERE Store__c = :storeId AND Status = 'New'];
        List<Case> resolvedCases = [SELECT ID FROM Case WHERE Store__c = :storeId AND IsClosed = True AND Closed_Reason__c = 'Resolved - Tech'];
        List<Case> inProgressCase = [SELECT ID FROM Case WHERE Store__c = :storeId AND Status IN : IN_PROGRESS_STATUSES];
        List<Case> closedCases = [SELECT ID FROM Case WHERE Store__c = :storeId AND  IsClosed = True AND Closed_Reason__c != 'Resolved - Tech'];
        List<Case> waitingOnClientCases = [SELECT ID FROM Case WHERE Store__c = :storeId AND Status = 'Waiting on Client'];
        List<Case> waitingOnAmazonCases = [SELECT ID FROM Case WHERE Store__c = :storeId AND Status = 'Waiting on Amazon'];
        summary.newCases = newCase.size();
        summary.resolvedCases = resolvedCases.size();
        summary.inProgressCases = inProgressCase.size();
        summary.closedCases = closedCases.size();
        summary.waitingOnClientCases = waitingOnClientCases.size();
        summary.waitingOnAmazonCases = waitingOnAmazonCases.size();
        return summary;
    }


    public class CaseSummary {
        @AuraEnabled public Integer newCases { get; set; }
        @AuraEnabled public Integer inProgressCases { get; set; }
        @AuraEnabled public Integer resolvedCases { get; set; }
        @AuraEnabled public Integer closedCases { get; set; }
        @AuraEnabled public Integer waitingOnClientCases { get; set; }
        @AuraEnabled public Integer waitingOnAmazonCases { get; set; }

        public CaseSummary() {
            this.newCases = 0;
            this.inProgressCases = 0;
            this.resolvedCases = 0;
            this.closedCases = 0;
        }
    }
}