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

        // User 0 = Time Tracking Admin, User 1 = regular user without admin access.
        // Admin checks run as User 1 so they do not depend on whether the
        // user running the tests happens to hold the admin permission set.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User adminUser = TestDataFactory.createUsers(2)[0];
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
    }

    private static User getAdminUser() {
        return [SELECT Id FROM User WHERE LastName = 'User 0' AND FirstName = 'Test' LIMIT 1];
    }

    private static User getNonAdminUser() {
        return [SELECT Id FROM User WHERE LastName = 'User 1' AND FirstName = 'Test' LIMIT 1];
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
        System.assertNotEquals(null, data.blockingTimer, 'A case timer must be reported while viewing its store.');
        System.assertEquals(caseData.activeTimer.id, data.blockingTimer.id);
        System.assertEquals(testCase.Id, data.blockingTimer.relatedRecordId, 'A case timer must link to the case, not its store.');
        System.assertEquals(null, caseData.blockingTimer, 'The same case timer must not block itself.');
    }

    @IsTest
    static void testGetDataFindsOtherCaseTimerWithoutMixingTotals() {
        Case primaryCase = getPrimaryCase();
        Case otherCase = getOtherCase();
        User otherUser = getAdminUser();
        Datetime now = System.now();
        Time_Tracking__c localEntry = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = primaryCase.Id,
            Start_Time__c = now.addMinutes(-15),
            End_Time__c = now,
            Status__c = TimeTrackingController.STATUS_COMPLETED
        );
        Time_Tracking__c otherTimer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = otherCase.Id,
            Start_Time__c = now.addMinutes(-20),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert new List<Time_Tracking__c>{
            localEntry,
            otherTimer,
            new Time_Tracking__c(
                Assignee__c = otherUser.Id,
                Case__c = otherCase.Id,
                Start_Time__c = now.addMinutes(-1),
                Status__c = TimeTrackingController.STATUS_IN_PROGRESS
            ),
            new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Case__c = otherCase.Id,
                Start_Time__c = now.addMinutes(-5),
                End_Time__c = now,
                Status__c = TimeTrackingController.STATUS_COMPLETED
            )
        };

        Test.startTest();
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(primaryCase.Id);
        Test.stopTest();

        System.assertEquals(1, data.records.size(), 'The table must contain only records for the viewed case.');
        System.assertEquals(localEntry.Id, data.records[0].id);
        System.assertEquals(15, data.totalMinutes, 'A timer on another case must not inflate the viewed case total.');
        System.assertEquals(null, data.activeTimer);
        System.assertNotEquals(null, data.blockingTimer);
        System.assertEquals(otherTimer.Id, data.blockingTimer.id, 'Only the current user\'s in-progress timer should be reported.');
        System.assertEquals(otherCase.Id, data.blockingTimer.relatedRecordId);
        System.assertEquals([SELECT CaseNumber FROM Case WHERE Id = :otherCase.Id].CaseNumber,
            data.blockingTimer.relatedRecordName);
    }

    @IsTest
    static void testGetDataShowsDirectStoreTimerWhileViewingCase() {
        Case primaryCase = getPrimaryCase();
        Time_Tracking__c storeTimer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Store__c = primaryCase.Store__c,
            Start_Time__c = System.now().addMinutes(-10),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert storeTimer;

        Test.startTest();
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(primaryCase.Id);
        Test.stopTest();

        System.assertEquals(0, data.records.size());
        System.assertEquals(0, data.totalMinutes);
        System.assertEquals(null, data.activeTimer);
        System.assertNotEquals(null, data.blockingTimer);
        System.assertEquals(storeTimer.Id, data.blockingTimer.id);
        System.assertEquals(primaryCase.Store__c, data.blockingTimer.relatedRecordId);
        System.assertEquals('Primary Store', data.blockingTimer.relatedRecordName);
    }

    @IsTest
    static void testGetDataIgnoresSameCaseOtherUsersAndCompletedTimers() {
        Case primaryCase = getPrimaryCase();
        Case otherCase = getOtherCase();
        User otherUser = getAdminUser();
        Datetime now = System.now();
        Time_Tracking__c localTimer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = primaryCase.Id,
            Store__c = primaryCase.Store__c,
            Start_Time__c = now.addMinutes(-10),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert new List<Time_Tracking__c>{
            localTimer,
            new Time_Tracking__c(
                Assignee__c = otherUser.Id,
                Case__c = otherCase.Id,
                Start_Time__c = now.addMinutes(-1),
                Status__c = TimeTrackingController.STATUS_IN_PROGRESS
            ),
            new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Case__c = otherCase.Id,
                Start_Time__c = now.addMinutes(-5),
                End_Time__c = now,
                Status__c = TimeTrackingController.STATUS_COMPLETED
            )
        };

        Test.startTest();
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(primaryCase.Id);
        Test.stopTest();

        System.assertEquals(localTimer.Id, data.activeTimer.id);
        System.assertEquals(primaryCase.Id, data.activeTimer.relatedRecordId);
        System.assertEquals(null, data.blockingTimer, 'A current timer on this case, other users\' timers, and completed timers must not block it.');
    }

    @IsTest
    static void testActiveUserKeyUniquenessBlocksSecondActiveTimerForSameUser() {
        Store__c otherStore = [SELECT Id FROM Store__c WHERE Name = 'Secondary Store' LIMIT 1];
        Store__c primaryStore = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];
        insert new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Store__c = otherStore.Id,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );

        Boolean duplicateBlocked = false;
        Test.startTest();
        try {
            insert new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Store__c = primaryStore.Id,
                Start_Time__c = System.now(),
                Status__c = TimeTrackingController.STATUS_IN_PROGRESS
            );
        } catch (DmlException ex) {
            duplicateBlocked = ex.getMessage().contains('DUPLICATE_VALUE');
        }
        Test.stopTest();

        System.assertEquals(true, duplicateBlocked,
            'The unique Active_User_Key__c invariant must prevent a second active/paused record for the same user.');
        System.assertEquals(1, [SELECT COUNT() FROM Time_Tracking__c WHERE Assignee__c = :UserInfo.getUserId()]);
    }

    @IsTest
    static void testStartTimerBlocksOnExistingPausedTimerInDifferentContext() {
        Store__c otherStore = [SELECT Id FROM Store__c WHERE Name = 'Secondary Store' LIMIT 1];
        Store__c primaryStore = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];
        Time_Tracking__c existing = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Store__c = otherStore.Id,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingConstants.STATUS_PAUSED_OFFLINE,
            Pause_Started_At__c = System.now()
        );
        insert existing;

        Test.startTest();
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(primaryStore.Id, null, null);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'A paused timer on another record must block starting a brand new timer rather than being silently replaced.');
        System.assertNotEquals(null, result.blockingTimer);
        System.assertEquals(existing.Id, result.blockingTimer.id);
    }

    @IsTest
    static void testStartTimerOnAccount() {
        Account account = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(account.Id, null, 'instance-a');
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(account.Id);
        Test.stopTest();

        Time_Tracking__c record = [SELECT Account__c, Case__c, Store__c, Type__c FROM Time_Tracking__c WHERE Id = :result.timeTrackingId];
        System.assertEquals(true, result.success);
        System.assertEquals(account.Id, record.Account__c);
        System.assertEquals('Client', record.Type__c);
        System.assertEquals('Account', data.objectType);
        System.assertNotEquals(null, data.activeTimer);
        System.assertEquals(result.timeTrackingId, data.activeTimer.id);
    }

    @IsTest
    static void testInternalTimerRequiresValidTypeAndNoContext() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.startTimer(null, 'Bogus Type', 'instance-a');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testStartInternalMeetingTimerAndFetchUtilityBarData() {
        Test.startTest();
        TimeTrackingController.StartTimerResult result =
            TimeTrackingController.startTimer(null, 'Internal Meeting', 'instance-a');
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(null);
        Test.stopTest();

        System.assertEquals(true, result.success);
        Time_Tracking__c record = [SELECT Account__c, Case__c, Store__c, Type__c FROM Time_Tracking__c WHERE Id = :result.timeTrackingId];
        System.assertEquals('Internal Meeting', record.Type__c);
        System.assertEquals(null, record.Account__c);
        System.assertEquals(null, record.Case__c);
        System.assertEquals(null, record.Store__c);
        System.assertNotEquals(null, data.activeTimer);
        System.assertEquals(result.timeTrackingId, data.activeTimer.id);
    }

    @IsTest
    static void testClientContextOnDifferentInstanceBlocksRatherThanAttaches() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];
        TimeTrackingController.startTimer(store.Id, null, 'instance-a');

        Test.startTest();
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(store.Id, null, 'instance-b');
        Test.stopTest();

        System.assertEquals(false, result.success,
            'A different browser instance must not silently attach to another device\'s running timer, even on the same record.');
        System.assertNotEquals(null, result.blockingTimer);
    }

    @IsTest
    static void testPauseAndResumeExcludePausedTimeFromDuration() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];
        Datetime start = System.now().addMinutes(-30);
        Time_Tracking__c timer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Store__c = store.Id,
            Start_Time__c = start,
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS,
            Timer_Instance_Id__c = 'instance-a'
        );
        insert timer;

        Test.startTest();
        TimeTrackingController.TimeTrackingWrapper paused =
            TimeTrackingController.pauseTimer(timer.Id, TimeTrackingConstants.STATUS_PAUSED_LUNCH, 'instance-a');
        System.assertEquals(TimeTrackingConstants.STATUS_PAUSED_LUNCH, paused.status);

        // Simulate ten minutes on break before resuming.
        Time_Tracking__c duringPause = [SELECT Pause_Started_At__c FROM Time_Tracking__c WHERE Id = :timer.Id];
        update new Time_Tracking__c(Id = timer.Id, Pause_Started_At__c = duringPause.Pause_Started_At__c.addMinutes(-10));

        TimeTrackingController.TimeTrackingWrapper resumed =
            TimeTrackingController.resumeTimer(timer.Id, 'instance-a', false);
        Test.stopTest();

        System.assertEquals(TimeTrackingController.STATUS_IN_PROGRESS, resumed.status);
        Time_Tracking__c record = [
            SELECT Status__c, Pause_Started_At__c, Paused_Duration_Minutes__c, Duration__c
            FROM Time_Tracking__c
            WHERE Id = :timer.Id
        ];
        System.assertEquals(null, record.Pause_Started_At__c);
        System.assert(record.Paused_Duration_Minutes__c >= 9.9, 'Resuming must accumulate the pause interval.');
        System.assert(record.Duration__c < 30, 'Active duration must exclude the paused interval.');
    }

    @IsTest
    static void testCompletingWhilePausedExcludesFinalPauseInterval() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];
        Datetime start = System.now().addMinutes(-20);
        Time_Tracking__c timer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Store__c = store.Id,
            Start_Time__c = start,
            Status__c = TimeTrackingConstants.STATUS_PAUSED_OFFLINE,
            Pause_Started_At__c = System.now().addMinutes(-5)
        );
        insert timer;

        Test.startTest();
        TimeTrackingController.completeTimer(timer.Id, 'Done');
        Test.stopTest();

        Time_Tracking__c record = [
            SELECT Status__c, Pause_Started_At__c, Paused_Duration_Minutes__c, Duration__c
            FROM Time_Tracking__c
            WHERE Id = :timer.Id
        ];
        System.assertEquals(TimeTrackingController.STATUS_COMPLETED, record.Status__c);
        System.assertEquals(null, record.Pause_Started_At__c);
        System.assert(record.Paused_Duration_Minutes__c >= 4.9);
        System.assert(record.Duration__c <= 16, 'The final pause interval must be excluded from the logged duration.');
    }

    @IsTest
    static void testPauseRejectsNonOwnerAndInvalidStatus() {
        User adminUser = getAdminUser();
        Time_Tracking__c timer = new Time_Tracking__c(
            Assignee__c = adminUser.Id,
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS,
            Type__c = 'Internal Task'
        );
        insert timer;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.pauseTimer(timer.Id, TimeTrackingConstants.STATUS_PAUSED_LUNCH, 'instance-a');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'A user must not be able to pause another user\'s timer.');
    }

    @IsTest
    static void testHeartbeatOnlyUpdatesForOwningInstance() {
        Time_Tracking__c timer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Start_Time__c = System.now(),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS,
            Type__c = 'Internal Task',
            Timer_Instance_Id__c = 'instance-a'
        );
        insert timer;

        Test.startTest();
        TimeTrackingController.heartbeat(timer.Id, 'instance-b');
        Time_Tracking__c afterWrongInstance = [SELECT Last_Heartbeat__c FROM Time_Tracking__c WHERE Id = :timer.Id];
        System.assertEquals(null, afterWrongInstance.Last_Heartbeat__c, 'A heartbeat from a non-owning instance must be ignored.');

        TimeTrackingController.heartbeat(timer.Id, 'instance-a');
        Test.stopTest();

        Time_Tracking__c afterOwningInstance = [SELECT Last_Heartbeat__c FROM Time_Tracking__c WHERE Id = :timer.Id];
        System.assertNotEquals(null, afterOwningInstance.Last_Heartbeat__c);
    }

    @IsTest
    static void testCleanupServicePausesStaleInProgressTimers() {
        Time_Tracking__c staleTimer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Start_Time__c = System.now().addMinutes(-20),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS,
            Type__c = 'Internal Task',
            Last_Heartbeat__c = System.now().addMinutes(-10)
        );
        insert staleTimer;

        Test.startTest();
        Integer cleanedUp = TimeTrackingCleanupService.cleanupStaleTimers();
        Test.stopTest();

        System.assertEquals(1, cleanedUp);
        Time_Tracking__c record = [SELECT Status__c, Pause_Started_At__c FROM Time_Tracking__c WHERE Id = :staleTimer.Id];
        System.assertEquals(TimeTrackingConstants.STATUS_PAUSED_OFFLINE, record.Status__c);
        System.assertNotEquals(null, record.Pause_Started_At__c);
    }

    @IsTest
    static void testCleanupServiceLeavesFreshAndHealthyTimersAlone() {
        Time_Tracking__c freshTimer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Start_Time__c = System.now().addMinutes(-1),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS,
            Type__c = 'Internal Task',
            Last_Heartbeat__c = System.now()
        );
        insert freshTimer;

        Test.startTest();
        Integer cleanedUp = TimeTrackingCleanupService.cleanupStaleTimers();
        Test.stopTest();

        System.assertEquals(0, cleanedUp);
        Time_Tracking__c record = [SELECT Status__c FROM Time_Tracking__c WHERE Id = :freshTimer.Id];
        System.assertEquals(TimeTrackingController.STATUS_IN_PROGRESS, record.Status__c);
    }

    @IsTest
    static void testCleanupSchedulerSchedulesOnlyOneRunAndWatchdog() {
        Test.startTest();
        Id firstRun = TimeTrackingCleanupScheduler.scheduleRecurringJob();
        Id secondRun = TimeTrackingCleanupScheduler.scheduleRecurringJob();
        System.assertEquals(firstRun, secondRun, 'Scheduling twice must not create a duplicate run.');
        String runNamePattern = TimeTrackingCleanupScheduler.RUN_NAME_PREFIX + '%';
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :runNamePattern],
            'Exactly one one-minute cleanup run must be pending.');
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :TimeTrackingCleanupScheduler.WATCHDOG_JOB_NAME],
            'Exactly one hourly watchdog job must be scheduled.');
        Test.stopTest();
    }

    @IsTest
    static void testStartTimerOnStore() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Primary Store' LIMIT 1];

        Test.startTest();
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(store.Id, null, null);
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(store.Id);
        TimeTrackingController.StartTimerResult resumed = TimeTrackingController.startTimer(store.Id, null, null);
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
        System.assertEquals(store.Id, data.activeTimer.relatedRecordId);
        System.assertEquals(null, data.blockingTimer, 'The same direct store timer must not block itself.');
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
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(testCase.Store__c, null, null);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.timeTrackingId);
        System.assertNotEquals(null, result.blockingTimer);
        System.assertEquals(caseTimer.Id, result.blockingTimer.id);
        System.assertEquals(1, [SELECT COUNT() FROM Time_Tracking__c]);
    }

    @IsTest
    static void testGetTimeTrackingDataNullRecordIdReturnsInternalUtilityBarView() {
        Test.startTest();
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(null);
        Test.stopTest();

        System.assertEquals(null, data.objectType, 'A null record Id means the context-free utility bar view.');
        System.assertEquals(0, data.records.size());
        System.assertEquals(null, data.activeTimer);
        System.assertEquals(null, data.blockingTimer);
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
            TimeTrackingController.startTimer(null, null, null);
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
            TimeTrackingController.startTimer(opportunity.Id, null, null);
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
        TimeTrackingController.StartTimerResult result = TimeTrackingController.startTimer(testCase.Id, null, null);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(existing.Id, result.timeTrackingId);
    }

    @IsTest
    static void testCreateManualEntryNullRecordId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.createManualEntry(null, null, System.now().addHours(-1), System.now(), 'Entry');
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
            TimeTrackingController.createManualEntry(testCase.Id, null, null, null, 'Entry');
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
                null,
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
                null,
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
            TimeTrackingController.startTimer(testCase.Id, null, null);
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
            TimeTrackingController.startTimer(otherCase.Id, null, null);
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
        System.runAs(getNonAdminUser()) {
            try {
                TimeTrackingController.deleteTimeTracking(record.Id, null);
            } catch (AuraHandledException ex) {
                exceptionThrown = true;
            }
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
        Id newId = TimeTrackingController.createManualEntry(testCase.Id, null, startTime, endTime, '  Manual entry  ');
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
        Id newId = TimeTrackingController.createManualEntry(store.Id, null, endTime.addMinutes(-20), endTime, 'Store work');
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
    static void testManualEntryRoundsEveryPartialMinuteUp() {
        Case testCase = getPrimaryCase();
        Datetime startTime = Datetime.newInstanceGMT(2026, 1, 15, 10, 0, 0);
        List<Integer> durationsInSeconds = new List<Integer>{ 1, 29, 30, 59, 60, 61, 119, 120 };
        List<Decimal> expectedMinutes = new List<Decimal>{ 1, 1, 1, 1, 1, 2, 2, 2 };
        Map<Id, Decimal> expectedById = new Map<Id, Decimal>();
        Map<Id, Datetime> expectedEndTimes = new Map<Id, Datetime>();

        Test.startTest();
        for (Integer index = 0; index < durationsInSeconds.size(); index++) {
            Datetime endTime = startTime.addSeconds(durationsInSeconds[index]);
            Id entryId = TimeTrackingController.createManualEntry(testCase.Id, null, startTime, endTime, null);
            expectedById.put(entryId, expectedMinutes[index]);
            expectedEndTimes.put(entryId, endTime);
        }
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(testCase.Id);
        Test.stopTest();

        List<Time_Tracking__c> entries = [
            SELECT Id, Start_Time__c, End_Time__c, Duration__c
            FROM Time_Tracking__c
            WHERE Id IN :expectedById.keySet()
        ];
        System.assertEquals(durationsInSeconds.size(), entries.size());
        for (Time_Tracking__c entry : entries) {
            System.assertEquals(startTime, entry.Start_Time__c, 'Rounding duration must preserve the entered start time.');
            System.assertEquals(expectedEndTimes.get(entry.Id), entry.End_Time__c,
                'Rounding duration must preserve the entered end time.');
            System.assertEquals(expectedById.get(entry.Id), entry.Duration__c,
                'Each partial minute must round up, while exact minutes must stay unchanged.');
        }

        System.assertEquals(durationsInSeconds.size(), data.records.size());
        Decimal displayedTotal = 0;
        for (TimeTrackingController.TimeTrackingWrapper entry : data.records) {
            System.assertEquals(expectedById.get(entry.id), entry.durationMinutes,
                'The component must receive the same rounded duration as the formula field.');
            displayedTotal += entry.durationMinutes;
        }
        System.assertEquals(11, displayedTotal, 'Round each entry before adding the logged total.');
        System.assertEquals(displayedTotal, data.totalMinutes, 'The total must match the sum of the rounded entries.');
    }

    @IsTest
    static void testCompletingShortTimerLogsAtLeastOneMinute() {
        Case testCase = getPrimaryCase();
        Time_Tracking__c timer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Case__c = testCase.Id,
            Start_Time__c = System.now().addSeconds(-1),
            Status__c = TimeTrackingController.STATUS_IN_PROGRESS
        );
        insert timer;

        Test.startTest();
        TimeTrackingController.completeTimer(timer.Id, null);
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(testCase.Id);
        Test.stopTest();

        Time_Tracking__c completed = [
            SELECT Status__c, Duration__c
            FROM Time_Tracking__c
            WHERE Id = :timer.Id
        ];
        System.assertEquals(TimeTrackingController.STATUS_COMPLETED, completed.Status__c);
        System.assert(completed.Duration__c >= 1, 'A completed timer with any elapsed seconds must log at least one minute.');
        System.assertEquals(1, data.records.size());
        System.assertEquals(completed.Duration__c, data.records[0].durationMinutes);
        System.assertEquals(completed.Duration__c, data.totalMinutes);
    }

    @IsTest
    static void testEditingManualEntryRoundsPartialMinuteUp() {
        Case testCase = getPrimaryCase();
        Datetime startTime = Datetime.newInstanceGMT(2026, 1, 15, 10, 0, 0);
        Id entryId = TimeTrackingController.createManualEntry(testCase.Id, null, startTime, startTime.addMinutes(1), null);
        User adminUser = getAdminUser();
        TimeTrackingController.TimeTrackingData data;

        Test.startTest();
        System.runAs(adminUser) {
            TimeTrackingController.updateTimeTracking(entryId, startTime, startTime.addSeconds(61), null);
            data = TimeTrackingController.getTimeTrackingData(testCase.Id);
        }
        Test.stopTest();

        Time_Tracking__c updated = [
            SELECT Start_Time__c, End_Time__c, Duration__c
            FROM Time_Tracking__c
            WHERE Id = :entryId
        ];
        System.assertEquals(startTime, updated.Start_Time__c);
        System.assertEquals(startTime.addSeconds(61), updated.End_Time__c);
        System.assertEquals(2, updated.Duration__c, 'Editing an entry to 61 seconds must log two minutes.');
        System.assertEquals(1, data.records.size());
        System.assertEquals(2, data.records[0].durationMinutes);
        System.assertEquals(2, data.totalMinutes);
    }

    @IsTest
    static void testCreateManualEntryValidatesEndAfterStart() {
        Case testCase = getPrimaryCase();
        Datetime startTime = System.now();
        Datetime endTime = System.now().addHours(-1);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            TimeTrackingController.createManualEntry(testCase.Id, null, startTime, endTime, 'Bad entry');
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
            TimeTrackingController.createManualEntry(testCase.Id, null, startTime, endTime, 'Too long entry');
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
        System.runAs(getNonAdminUser()) {
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
        System.runAs(getNonAdminUser()) {
            TimeTrackingController.TimeTrackingData dataBefore =
                TimeTrackingController.getTimeTrackingData(testCase.Id);
            System.assertEquals(false, dataBefore.isAdmin);
        }

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
            TimeTrackingController.startTimer(otherCase.Id, null, null);
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
