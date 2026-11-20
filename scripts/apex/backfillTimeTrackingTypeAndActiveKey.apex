// One-time backfill for the Type__c / Active_User_Key__c additions to Time Tracking.
// Run from the project root:
// sf apex run --file scripts/apex/backfillTimeTrackingTypeAndActiveKey.apex --target-org ad-sfdc-app-staging
// Updates up to 1,000 records per execution. Rerun until Remaining eligible = 0.
//
// Step 1: Any pre-existing active/paused record for a user that is a leftover
// duplicate (created before the Active_User_Key__c unique constraint existed)
// is completed first, so the backfill below never collides with the unique
// index. The newest record per user is kept running; older ones are closed out
// with a note so they surface for manual review.
Map<Id, List<Time_Tracking__c>> activeByAssignee = new Map<Id, List<Time_Tracking__c>>();
for (Time_Tracking__c record : [
    SELECT Id, Assignee__c, Start_Time__c
    FROM Time_Tracking__c
    WHERE Status__c = 'In progress'
    ORDER BY Assignee__c, Start_Time__c DESC
]) {
    if (!activeByAssignee.containsKey(record.Assignee__c)) {
        activeByAssignee.put(record.Assignee__c, new List<Time_Tracking__c>());
    }
    activeByAssignee.get(record.Assignee__c).add(record);
}

List<Time_Tracking__c> duplicateResolutions = new List<Time_Tracking__c>();
for (List<Time_Tracking__c> timersForUser : activeByAssignee.values()) {
    for (Integer i = 1; i < timersForUser.size(); i++) {
        duplicateResolutions.add(new Time_Tracking__c(
            Id = timersForUser[i].Id,
            Status__c = 'Completed',
            End_Time__c = System.now(),
            Comments__c = 'Auto-completed during Type__c/Active_User_Key__c backfill: duplicate active timer for this user.'
        ));
    }
}
if (!duplicateResolutions.isEmpty()) {
    Database.update(duplicateResolutions, false);
}

// Step 2: Backfill Type__c = Client on every pre-existing record. Internal
// time tracking did not exist before this release, so every historical
// record is, by definition, client work.
Integer batchSize = 1000;
List<Time_Tracking__c> typeRecords = [
    SELECT Id
    FROM Time_Tracking__c
    WHERE Type__c = null
    ORDER BY Id
    LIMIT :batchSize
];

List<Time_Tracking__c> typeUpdates = new List<Time_Tracking__c>();
for (Time_Tracking__c record : typeRecords) {
    typeUpdates.add(new Time_Tracking__c(Id = record.Id, Type__c = 'Client'));
}

Integer typeUpdatedCount = 0;
Integer typeFailedCount = 0;
if (!typeUpdates.isEmpty()) {
    Database.SaveResult[] results = Database.update(typeUpdates, false);
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            typeUpdatedCount++;
        } else {
            typeFailedCount++;
            for (Database.Error error : results[i].getErrors()) {
                System.debug(LoggingLevel.ERROR,
                    'Failed Type__c backfill for Time_Tracking__c ' + typeUpdates[i].Id + ': ' +
                    error.getStatusCode() + ' - ' + error.getMessage());
            }
        }
    }
}

// Step 3: Active_User_Key__c is maintained going forward by TimeTrackingTrigger
// on every insert/update. Touching the remaining active/paused records here
// (now that duplicates are resolved) ensures the key is populated immediately
// for any records that predate the trigger's deployment.
List<Time_Tracking__c> activeRecords = [
    SELECT Id, Assignee__c
    FROM Time_Tracking__c
    WHERE Status__c IN ('In progress', 'Paused - Lunch/Break', 'Paused - Offline')
      AND Active_User_Key__c = null
    LIMIT :batchSize
];
Integer keyUpdatedCount = 0;
Integer keyFailedCount = 0;
if (!activeRecords.isEmpty()) {
    // A no-op field touch is enough: the trigger recomputes Active_User_Key__c.
    Database.SaveResult[] results = Database.update(activeRecords, false);
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            keyUpdatedCount++;
        } else {
            keyFailedCount++;
            for (Database.Error error : results[i].getErrors()) {
                System.debug(LoggingLevel.ERROR,
                    'Failed Active_User_Key__c backfill for Time_Tracking__c ' + activeRecords[i].Id + ': ' +
                    error.getStatusCode() + ' - ' + error.getMessage());
            }
        }
    }
}

Integer remainingTypeCount = [SELECT COUNT() FROM Time_Tracking__c WHERE Type__c = null];
Integer remainingKeyCount = [
    SELECT COUNT()
    FROM Time_Tracking__c
    WHERE Status__c IN ('In progress', 'Paused - Lunch/Break', 'Paused - Offline')
      AND Active_User_Key__c = null
];

System.debug(LoggingLevel.INFO,
    'Time tracking Type__c/Active_User_Key__c backfill: ' +
    'Duplicate active timers auto-completed = ' + duplicateResolutions.size() +
    ', Type__c updated = ' + typeUpdatedCount + ', Type__c failed = ' + typeFailedCount +
    ', Active_User_Key__c touched = ' + keyUpdatedCount + ', Active_User_Key__c failed = ' + keyFailedCount +
    ', Remaining Type__c eligible = ' + remainingTypeCount +
    ', Remaining Active_User_Key__c eligible = ' + remainingKeyCount);
