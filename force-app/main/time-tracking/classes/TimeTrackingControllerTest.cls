@IsTest
private class TimeTrackingControllerTest {

    @TestSetup
    static void setupData() {
        Account account = TestDataFactory.createAccounts(1)[0];
        Opportunity opportunity = TestDataFactory.createOpportunities(new List<Account>{ account }, 1)[0];
        Store__c store = TestDataFactory.createStores(opportunity.Id, 1)[0];
        Store__c otherStore = TestDataFactory.createStores(opportunity.Id, 1)[0];
        store.Name = 'Primary Store';
        otherStore.Name = 'Secondary Store';
        update new List<Store__c>{ store, otherStore };

        insert new List<Case>{
            new Case(
                Subject = 'Time Tracking Case',
                Origin = 'Phone',
                Status = 'New',
                Store__c = store.Id
            ),
            new Case(
                Subject = 'Other Case',
                Origin = 'Phone',
                Status = 'New',
                Store__c = otherStore.Id
            )
        };

        User adminUser = TestDataFactory.createUsers(1)[0];
        PermissionSet adminPermSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Time_Tracking_Admin'
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = adminUser.Id,
            PermissionSetId = adminPermSet.Id
        );
    }

    private static User getAdminUser() {
        return [SELECT Id FROM User WHERE LastName = 'User 0' AND FirstName = 'Test' LIMIT 1];
    }

    private static Case getPrimaryCase() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];
        return [SELECT Id, Store__c FROM Case WHERE Store__c = :store.Id LIMIT 1];
    }

    private static Case getOtherCase() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Secondary Store' LIMIT 1];
        return [SELECT Id FROM Case WHERE Store__c = :store.Id LIMIT 1];
    }

    @IsTest
    static void testGetTimeTrackingDataForStore() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];
        Store__c otherStore = [SELECT Id FROM Store__c WHERE Name = 'Secondary Store' LIMIT 1];
        Case testCase = getPrimaryCase();
        Datetime endTime = System.now();

        Time_Tracking__c storeEntry = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Store__c = store.Id,
            Start_Time__c = endTime.addMinutes(-15),
            End_Time__c = endTime,
            Status__c = TimeTrackingController.STATUS_COMPLETED,
            Comments__c = 'Store work'
        );
        insert new List<Time_Tracking__c>{
            storeEntry,
            new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Store__c = store.Id,
                Case__c = testCase.Id,
                Start_Time__c = endTime.addMinutes(-30),
                End_Time__c = endTime,
                Status__c = TimeTrackingController.STATUS_COMPLETED,
                Comments__c = 'Case work'
            ),
            new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Store__c = store.Id,
                Case__c = testCase.Id,
                Start_Time__c = endTime.addMinutes(-10),
                Status__c = TimeTrackingController.STATUS_IN_PROGRESS
            ),
            new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Store__c = otherStore.Id,
                Start_Time__c = endTime.addMinutes(-45),
                End_Time__c = endTime,
                Status__c = TimeTrackingController.STATUS_COMPLETED,
                Comments__c = 'Other store work'
            )
        };

        Test.startTest();
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(store.Id);
        TimeTrackingController.TimeTrackingData caseData = TimeTrackingController.getTimeTrackingData(testCase.Id);
        Test.stopTest();

        System.assertEquals('Store__c', data.objectType);
        System.assertEquals(1, data.records.size());
        System.assertEquals(storeEntry.Id, data.records[0].id);
        System.assertEquals('Primary Store', data.records[0].relatedRecordName);
        System.assertEquals(15, data.totalMinutes, 'Store totals must exclude case entries and other stores.');
        System.assertEquals(null, data.activeTimer, 'A case timer must not appear as an active store timer.');
        System.assertEquals(2, caseData.records.size(), 'Case entries should remain visible on their case.');
        System.assertNotEquals(null, caseData.activeTimer);
    }

    @IsTest
    static void testStartTimerOnStore() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];

        Test.startTest();
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(store.Id);
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(store.Id);
        TimeTrackingController.StartTimerResult resumed = TimeTrackingController.startTimer(store.Id);
        Test.stopTest();

        Time_Tracking__c record = [
            SELECT Case__c, Store__c
            FROM Time_Tracking__c
            WHERE Id = :result.timeTrackingId
        ];
        System.assertEquals(true, result.success);
        System.assertEquals(store.Id, record.Store__c);
        System.assertEquals(null, record.Case__c);
        System.assertEquals(1, data.records.size());
        System.assertNotEquals(null, data.activeTimer);
        System.assertEquals(result.timeTrackingId, data.activeTimer.id);
        System.assertEquals(true, resumed.success);
        System.assertEquals(result.timeTrackingId, resumed.timeTrackingId);
    }

    @IsTest
    static void testCaseTimerBlocksTimerOnSameStore() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c caseTimer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Store__c = testCase.Store__c,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert caseTimer;

        Test.startTest();
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(testCase.Store__c);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.timeTrackingId);
        System.assertNotEquals(null, result.blockingTimer);
        System.assertEquals(caseTimer.Id, result.blockingTimer.id);
        System.assertEquals(1, [SELECT COUNT() FROM Time_Tracking__c]);
    }

    @IsTest
    static void testGetTimeTrackingDataNullRecordId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.getTimeTrackingData(null);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testGetTimeTrackingDataInvalidObjectType() {
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.getTimeTrackingData(opportunity.Id);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testStartTimerNullRecordId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.startTimer(null);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testStartTimerInvalidObjectType() {
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.startTimer(opportunity.Id);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testStartTimerResumesExistingTimerOnSameRecord() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c existing = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Store__c = testCase.Store__c,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert existing;

        Test.startTest();
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(testCase.Id);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(existing.Id, result.timeTrackingId);
    }

    @IsTest
    static void testCreateManualEntryNullRecordId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.createManualEntry(null, System.now().addHours(-1), System.now(), 'Entry');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCreateManualEntryNullTimes() {
        Case testCase = getPrimaryCase();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.createManualEntry(testCase.Id, null, null, 'Entry');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCreateManualEntryBlankComments() {
        Case testCase = getPrimaryCase();
        Datetime endTime = System.now().addHours(-1);
        List<String> blankComments = new List<String>{ null, '', ' \t ' };
        Set<Id> createdIds = new Set<Id>();

        Test.startTest();
        for (String comments : blankComments) {
            createdIds.add(TimeTrackingController.createManualEntry(
                testCase.Id,
                endTime.addHours(-1),
                endTime,
                comments
            ));
        }
        Test.stopTest();

        System.assertEquals(3, createdIds.size(), 'Null, empty, and whitespace comments must allow creation.');
        for (Time_Tracking__c record : [
            SELECT Comments__c, Status__c, Start_Time__c, End_Time__c, Case__c, Store__c
            FROM Time_Tracking__c
            WHERE Id IN :createdIds
        ]) {
            System.assertEquals(null, record.Comments__c, 'Blank comments should be stored as null.');
            System.assertEquals(TimeTrackingController.STATUS_COMPLETED, record.Status__c);
            System.assertEquals(endTime.addHours(-1), record.Start_Time__c);
            System.assertEquals(endTime, record.End_Time__c);
            System.assertEquals(testCase.Id, record.Case__c);
            System.assertEquals(testCase.Store__c, record.Store__c);
        }
    }

    @IsTest
    static void testCreateManualEntryInvalidObjectType() {
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.createManualEntry(
                opportunity.Id,
                System.now().addHours(-1),
                System.now(),
                'Entry'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testUpdateTimeTrackingNullId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.updateTimeTracking(null, System.now().addHours(-1), System.now(), 'Updated');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testUpdateTimeTrackingNullTimes() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c record = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Start_Time__c = System.now().addHours(-1),
            End_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_COMPLETED,
            Comments__c = 'Original'
        );
        insert record;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.updateTimeTracking(record.Id, null, null, 'Updated');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testUpdateTimeTrackingBlankComments() {
        Case testCase = getPrimaryCase();
        Datetime newEnd = System.now().addHours(-2);
        Datetime newStart = newEnd.addHours(-1);
        List<String> blankComments = new List<String>{ null, '', ' \t ' };
        List<Time_Tracking__c> records = new List<Time_Tracking__c>();
        for (String comments : blankComments) {
            records.add(new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Case__c = testCase.Id,
                Start_Time__c = System.now().addHours(-1),
                End_Time__c = System.now(),
                Status__c = TimeTrackingController.STATUS_COMPLETED,
                Comments__c = 'Original'
            ));
        }
        insert records;

        User adminUser = getAdminUser();
        Test.startTest();
        System.runAs(adminUser) {
            for (Integer index = 0; index < blankComments.size(); index++) {
                TimeTrackingController.updateTimeTracking(records[index].Id, newStart, newEnd, blankComments[index]);
            }
        }
        Test.stopTest();

        for (Time_Tracking__c record : [
            SELECT Comments__c, Start_Time__c, End_Time__c, Status__c
            FROM Time_Tracking__c
            WHERE Id IN :records
        ]) {
            System.assertEquals(null, record.Comments__c, 'Blank comments must clear an existing comment.');
            System.assertEquals(newStart, record.Start_Time__c);
            System.assertEquals(newEnd, record.End_Time__c);
            System.assertEquals(TimeTrackingController.STATUS_COMPLETED, record.Status__c);
        }
    }

    @IsTest
    static void testDeleteTimeTrackingNullId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.deleteTimeTracking(null, 'Removing');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testDeleteTimeTrackingBlankComments() {
        Case testCase = getPrimaryCase();
        List<String> blankComments = new List<String>{ null, '', ' \t ' };
        List<Time_Tracking__c> records = new List<Time_Tracking__c>();
        for (String comments : blankComments) {
            records.add(new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Case__c = testCase.Id,
                Start_Time__c = System.now().addHours(-1),
                End_Time__c = System.now(),
                Status__c = TimeTrackingController.STATUS_COMPLETED,
                Comments__c = 'Original comment'
            ));
        }
        insert records;

        User adminUser = getAdminUser();
        Test.startTest();
        System.runAs(adminUser) {
            for (Integer index = 0; index < blankComments.size(); index++) {
                TimeTrackingController.deleteTimeTracking(records[index].Id, blankComments[index]);
            }
        }
        Test.stopTest();

        List<Time_Tracking__c> deletedRecords = [
            SELECT IsDeleted, Comments__c
            FROM Time_Tracking__c
            WHERE Id IN :records
            ALL ROWS
        ];
        System.assertEquals(3, deletedRecords.size());
        for (Time_Tracking__c record : deletedRecords) {
            System.assertEquals(true, record.IsDeleted, 'Blank comments must not block an authorized deletion.');
            System.assertEquals('Original comment', record.Comments__c, 'Deleting without a comment must not update the existing comment.');
        }
    }

    @IsTest
    static void testCompleteTimerBlockedForNonOwner() {
        Case testCase = getPrimaryCase();
        User adminUser = getAdminUser();
        Time_Tracking__c record = new Time_Tracking__c(
            Assignee__c = adminUser.Id,
            Case__c = testCase.Id,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert record;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.completeTimer(record.Id, 'Trying to complete someone else timer');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCompleteTimerAlreadyCompleted() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c record = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Start_Time__c = System.now().addHours(-1),
            End_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_COMPLETED,
            Comments__c = 'Already done'
        );
        insert record;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.completeTimer(record.Id, 'Trying again');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testGetTimeTrackingDataForCase() {
        Case testCase = getPrimaryCase();

        insert new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Start_Time__c = System.now().addMinutes(-30),
            End_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_COMPLETED,
            Comments__c = 'Completed work'
        );

        Test.startTest();
        TimeTrackingController.TimeTrackingData data =
            TimeTrackingController.getTimeTrackingData(testCase.Id);
        Test.stopTest();

        System.assertEquals('Case', data.objectType);
        System.assertEquals(1, data.records.size());
        System.assert(data.totalMinutes > 0, 'Total minutes should include completed record duration.');
    }

    @IsTest
    static void testStartAndCompleteTimerOnCase() {
        Case testCase = getPrimaryCase();

        Test.startTest();
        TimeTrackingController.StartTimerResult startResult =
            TimeTrackingController.startTimer(testCase.Id);
        System.assertEquals(true, startResult.success);

        TimeTrackingController.completeTimer(startResult.timeTrackingId, '  Finished task  ');
        Test.stopTest();

        Time_Tracking__c completedRecord = [
            SELECT Status__c, End_Time__c, Comments__c, Case__c, Store__c
            FROM Time_Tracking__c
            WHERE Id = :startResult.timeTrackingId
        ];
        System.assertEquals(TimeTrackingController.STATUS_COMPLETED, completedRecord.Status__c);
        System.assertNotEquals(null, completedRecord.End_Time__c);
        System.assertEquals('Finished task', completedRecord.Comments__c);
        System.assertEquals(testCase.Id, completedRecord.Case__c);
        System.assertEquals(testCase.Store__c, completedRecord.Store__c);
    }

    @IsTest
    static void testBlockingTimerOnDifferentCase() {
        Case primaryCase = getPrimaryCase();
        Case otherCase = getOtherCase();

        insert new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = primaryCase.Id,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );

        Test.startTest();
        TimeTrackingController.StartTimerResult startResult =
            TimeTrackingController.startTimer(otherCase.Id);
        Test.stopTest();

        System.assertEquals(false, startResult.success);
        System.assertNotEquals(null, startResult.blockingTimer);
    }

    @IsTest
    static void testDeleteTimeTrackingRequiresAdminPermission() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c record = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert record;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.deleteTimeTracking(record.Id, null);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Delete should be blocked without Time Tracking Admin access.');
        System.assertEquals(1, [SELECT COUNT() FROM Time_Tracking__c WHERE Id = :record.Id]);
    }

    @IsTest
    static void testDeleteTimeTrackingWithAdminPermission() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c record = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert record;

        User adminUser = getAdminUser();
        Test.startTest();
        System.runAs(adminUser) {
            TimeTrackingController.deleteTimeTracking(record.Id, '  Removing incorrect entry  ');
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Time_Tracking__c WHERE Id = :record.Id]);
        Time_Tracking__c deletedRecord = [
            SELECT Comments__c
            FROM Time_Tracking__c
            WHERE Id = :record.Id
            ALL ROWS
        ];
        System.assertEquals('Removing incorrect entry', deletedRecord.Comments__c);
    }

    @IsTest
    static void testCreateManualEntry() {
        Case testCase = getPrimaryCase();
        Datetime startTime = System.now().addHours(-2);
        Datetime endTime = System.now().addHours(-1);

        Test.startTest();
        Id newId = TimeTrackingController.createManualEntry(testCase.Id, startTime, endTime, '  Manual entry  ');
        Test.stopTest();

        Time_Tracking__c record = [
            SELECT Status__c, Start_Time__c, End_Time__c, Comments__c, Assignee__c, Case__c, Store__c
            FROM Time_Tracking__c
            WHERE Id = :newId
        ];
        System.assertEquals(TimeTrackingController.STATUS_COMPLETED, record.Status__c);
        System.assertEquals('Manual entry', record.Comments__c);
        System.assertEquals(UserInfo.getUserId(), record.Assignee__c);
        System.assertEquals(testCase.Id, record.Case__c);
        System.assertEquals(testCase.Store__c, record.Store__c);
    }

    @IsTest
    static void testCreateManualEntryOnStore() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];
        Datetime endTime = System.now();

        Test.startTest();
        Id newId = TimeTrackingController.createManualEntry(store.Id, endTime.addMinutes(-20), endTime, 'Store work');
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(store.Id);
        Test.stopTest();

        Time_Tracking__c record = [
            SELECT Case__c, Store__c
            FROM Time_Tracking__c
            WHERE Id = :newId
        ];
        System.assertEquals(store.Id, record.Store__c);
        System.assertEquals(null, record.Case__c);
        System.assertEquals(1, data.records.size());
        System.assertEquals(newId, data.records[0].id);
        System.assertEquals(20, data.totalMinutes);
    }

    @IsTest
    static void testCreateManualEntryValidatesEndAfterStart() {
        Case testCase = getPrimaryCase();
        Datetime startTime = System.now();
        Datetime endTime = System.now().addHours(-1);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.createManualEntry(testCase.Id, startTime, endTime, 'Bad entry');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testCreateManualEntryValidatesMaxDuration() {
        Case testCase = getPrimaryCase();
        Datetime startTime = System.now().addHours(-30);
        Datetime endTime = System.now();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.createManualEntry(testCase.Id, startTime, endTime, 'Too long entry');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testUpdateTimeTrackingRequiresAdminPermission() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c record = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Start_Time__c = System.now().addHours(-1),
            End_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_COMPLETED,
            Comments__c = 'Original comment'
        );
        insert record;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.updateTimeTracking(
                record.Id,
                System.now().addHours(-2),
                System.now().addHours(-1),
                null
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Update should be blocked without Time Tracking Admin access.');
    }

    @IsTest
    static void testUpdateTimeTrackingWithAdminPermission() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c record = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Start_Time__c = System.now().addHours(-1),
            End_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_COMPLETED,
            Comments__c = 'Original comment'
        );
        insert record;

        Datetime newStart = System.now().addHours(-3);
        Datetime newEnd = System.now().addHours(-2);

        User adminUser = getAdminUser();
        Test.startTest();
        System.runAs(adminUser) {
            TimeTrackingController.updateTimeTracking(record.Id, newStart, newEnd, '  Updated comment  ');
        }
        Test.stopTest();

        Time_Tracking__c updated = [
            SELECT Comments__c, Start_Time__c, End_Time__c, Status__c
            FROM Time_Tracking__c
            WHERE Id = :record.Id
        ];
        System.assertEquals('Updated comment', updated.Comments__c);
        System.assertEquals(TimeTrackingController.STATUS_COMPLETED, updated.Status__c);
    }

    @IsTest
    static void testIsAdminFlagOnTimeTrackingData() {
        Case testCase = getPrimaryCase();
        User adminUser = getAdminUser();

        Test.startTest();
        TimeTrackingController.TimeTrackingData dataBefore =
            TimeTrackingController.getTimeTrackingData(testCase.Id);
        System.assertEquals(false, dataBefore.isAdmin);

        System.runAs(adminUser) {
            TimeTrackingController.TimeTrackingData dataAfter =
                TimeTrackingController.getTimeTrackingData(testCase.Id);
            System.assertEquals(true, dataAfter.isAdmin);
        }
        Test.stopTest();
    }

    @IsTest
    static void testCompleteTimerBlankComments() {
        Case testCase = getPrimaryCase();
        List<String> blankComments = new List<String>{ null, '', ' \t ' };
        Set<Id> completedIds = new Set<Id>();

        Test.startTest();
        for (String comments : blankComments) {
            Time_Tracking__c record = new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Case__c = testCase.Id,
                Start_Time__c = System.now().addMinutes(-5),
                Status__c = TimeTrackingController.STATUS_IN_PROGRESS,
                Comments__c = 'Original comment'
            );
            insert record;
            TimeTrackingController.completeTimer(record.Id, comments);
            completedIds.add(record.Id);
        }
        Test.stopTest();

        System.assertEquals(3, completedIds.size(), 'Null, empty, and whitespace comments must allow completion.');
        for (Time_Tracking__c record : [
            SELECT Comments__c, Status__c, Start_Time__c, End_Time__c
            FROM Time_Tracking__c
            WHERE Id IN :completedIds
        ]) {
            System.assertEquals(null, record.Comments__c, 'Completing without comments must clear an existing comment.');
            System.assertEquals(TimeTrackingController.STATUS_COMPLETED, record.Status__c);
            System.assertNotEquals(null, record.End_Time__c);
            System.assert(record.End_Time__c > record.Start_Time__c, 'The completed timer must retain a valid duration.');
        }
    }

    @IsTest
    static void testCompleteBlockingTimerThenStartOnOtherCase() {
        Case primaryCase = getPrimaryCase();
        Case otherCase = getOtherCase();

        Time_Tracking__c blockingRecord = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = primaryCase.Id,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert blockingRecord;

        Test.startTest();
        TimeTrackingController.completeTimer(blockingRecord.Id, 'Finished on other case');
        TimeTrackingController.StartTimerResult startResult =
            TimeTrackingController.startTimer(otherCase.Id);
        Test.stopTest();

        System.assertEquals(true, startResult.success);
        System.assertNotEquals(null, startResult.timeTrackingId);

        Time_Tracking__c newRecord = [
            SELECT Case__c, Status__c
            FROM Time_Tracking__c
            WHERE Id = :startResult.timeTrackingId
        ];
        System.assertEquals(otherCase.Id, newRecord.Case__c);
        System.assertEquals(TimeTrackingController.STATUS_IN_PROGRESS, newRecord.Status__c);
    }
}
