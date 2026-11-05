// Backfill missing stores on case-linked time tracking records.
// Run from the project root:
// sf apex run --file scripts/apex/backfillTimeTrackingStores.apex --target-org ad-sfdc-app-staging
// Updates up to 1,000 records per execution. Rerun until Remaining eligible = 0.
// Resolve any logged update failures before rerunning; failed rows remain eligible.
// Records whose related case has no store are skipped.

Integer batchSize = 1000;
List<Time_Tracking__c> records = [
    SELECT Id, Case__r.Store__c
    FROM Time_Tracking__c
    WHERE Case__c != null
      AND Store__c = null
      AND Case__r.Store__c != null
    ORDER BY Id
    LIMIT :batchSize
];

List<Time_Tracking__c> updates = new List<Time_Tracking__c>();
for (Time_Tracking__c record : records) {
    updates.add(new Time_Tracking__c(
        Id = record.Id,
        Store__c = record.Case__r.Store__c
    ));
}

Integer updatedCount = 0;
Integer failedCount = 0;
if (!updates.isEmpty()) {
    Database.SaveResult[] results = Database.update(updates, false);
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            updatedCount++;
        } else {
            failedCount++;
            for (Database.Error error : results[i].getErrors()) {
                System.debug(LoggingLevel.ERROR,
                    'Failed Time_Tracking__c ' + updates[i].Id + ': ' +
                    error.getStatusCode() + ' - ' + error.getMessage());
            }
        }
    }
}

Integer remainingCount = [
    SELECT COUNT()
    FROM Time_Tracking__c
    WHERE Case__c != null
      AND Store__c = null
      AND Case__r.Store__c != null
];
Integer skippedCount = [
    SELECT COUNT()
    FROM Time_Tracking__c
    WHERE Case__c != null
      AND Store__c = null
      AND Case__r.Store__c = null
];

System.debug(LoggingLevel.INFO,
    'Time tracking store backfill: Updated = ' + updatedCount +
    ', Failed = ' + failedCount +
    ', Remaining eligible = ' + remainingCount +
    ', Skipped (case has no store) = ' + skippedCount);
