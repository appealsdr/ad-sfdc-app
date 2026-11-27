/**
 * Covers the Time Tracking fixes for TC-03/04 (paused minutes), TC-08 (tab or
 * browser closed while a timer runs), TC-09/10 (manual entry flag) and
 * TC-11/12 (admin edit/delete through the Time Tracking Admin permission set).
 */
@IsTest
private class TimeTrackingReliabilityTest {

    private static final String INSTANCE_A = 'browser-a';
    private static final String INSTANCE_B = 'browser-b';
    private static final String TEST_STORE_NAME = 'Time Tracking Reliability Store';

    @TestSetup
    static void setupData() {
        Account account = TestDataFactory.createAccounts(1)[0];
        Opportunity opportunity = TestDataFactory.createOpportunities(new List<Account>{ account }, 1)[0];
        Store__c store = TestDataFactory.createStores(opportunity.Id, 1)[0];
        store.Name = TEST_STORE_NAME;
        update store;
        insert new Case(Subject = 'Reliability Case', Origin = 'Phone', Status = 'New', Store__c = store.Id);

        List<User> users = TestDataFactory.createUsers(2);
        PermissionSet adminPermSet = [SELECT Id FROM PermissionSet WHERE Name = 'Time_Tracking_Admin' LIMIT 1];
        PermissionSet userPermSet = [SELECT Id FROM PermissionSet WHERE Name = 'Time_Tracking_User' LIMIT 1];
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetId = adminPermSet.Id),
            new PermissionSetAssignment(AssigneeId = users[1].Id, PermissionSetId = userPermSet.Id)
        };
    }

    private static User adminUser() {
        return [SELECT Id FROM User WHERE FirstName = 'Test' AND LastName = 'User 0' LIMIT 1];
    }

    private static User regularUser() {
        return [SELECT Id FROM User WHERE FirstName = 'Test' AND LastName = 'User 1' LIMIT 1];
    }

    private static Case testCase() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = :TEST_STORE_NAME];
        return [SELECT Id FROM Case WHERE Store__c = :store.Id];
    }

    private static Time_Tracking__c runningTimer(Integer startedMinutesAgo, Integer lastHeartbeatSecondsAgo, String instanceId) {
        Time_Tracking__c timer = new Time_Tracking__c(
            Assignee__c = UserInfo.getUserId(),
            Start_Time__c = System.now().addMinutes(-startedMinutesAgo),
            Status__c = TimeTrackingConstants.STATUS_IN_PROGRESS,
            Type__c = TimeTrackingConstants.TYPE_INTERNAL_TASK,
            Timer_Instance_Id__c = instanceId,
            Paused_Duration_Minutes__c = 0,
            Last_Heartbeat__c = lastHeartbeatSecondsAgo == null ? null : System.now().addSeconds(-lastHeartbeatSecondsAgo)
        );
        insert timer;
        return timer;
    }

    private static Time_Tracking__c reload(Id timerId) {
        return [
            SELECT Id, Status__c, Pause_Started_At__c, Paused_Duration_Minutes__c, Last_Heartbeat__c,
                   Is_Manual_Entry__c, Duration__c, Active_User_Key__c
            FROM Time_Tracking__c
            WHERE Id = :timerId
        ];
    }

    // ---------- TC-08: tab / browser closed ----------

    @IsTest
    static void reconcilePausesOfflineAtTheMomentTheLastTabWasClosed() {
        // Last heartbeat 40s ago; the only tab was closed 30s ago (reported by the reopened tab).
        Time_Tracking__c timer = runningTimer(10, 40, INSTANCE_A);

        Test.startTest();
        Boolean paused = TimeTrackingController.reconcileTimer(INSTANCE_A, timer.Id, 30);
        Test.stopTest();

        System.assertEquals(true, paused, 'A timer whose last tab was closed must be auto-paused on reopen.');
        Time_Tracking__c record = reload(timer.Id);
        System.assertEquals(TimeTrackingConstants.STATUS_PAUSED_OFFLINE, record.Status__c);
        Long secondsAgo = (System.now().getTime() - record.Pause_Started_At__c.getTime()) / 1000;
        System.assert(secondsAgo >= 25 && secondsAgo <= 40, 'Pause must start when the tab was closed, was ' + secondsAgo + 's ago.');
        System.assertNotEquals(null, record.Active_User_Key__c, 'A paused timer still blocks a second timer.');
    }

    @IsTest
    static void reconcileIgnoresTabCloseWhenAnotherTabKeptTheTimerAlive() {
        // Another tab heartbeated 5s ago, after the reported close 60s ago.
        Time_Tracking__c timer = runningTimer(10, 5, INSTANCE_A);

        Test.startTest();
        Boolean paused = TimeTrackingController.reconcileTimer(INSTANCE_A, timer.Id, 60);
        Test.stopTest();

        System.assertEquals(false, paused, 'Closing one of several tabs must not pause the timer.');
        System.assertEquals(TimeTrackingConstants.STATUS_IN_PROGRESS, reload(timer.Id).Status__c);
    }

    @IsTest
    static void reconcileIgnoresTabCloseReportedByAnotherBrowser() {
        Time_Tracking__c timer = runningTimer(10, 40, INSTANCE_A);

        Test.startTest();
        Boolean paused = TimeTrackingController.reconcileTimer(INSTANCE_B, timer.Id, 30);
        Test.stopTest();

        System.assertEquals(false, paused, 'Only the browser that owns the timer can report its tab closing.');
        System.assertEquals(TimeTrackingConstants.STATUS_IN_PROGRESS, reload(timer.Id).Status__c);
    }

    @IsTest
    static void reconcilePausesTimerWithStaleHeartbeat() {
        Time_Tracking__c timer = runningTimer(30, 600, INSTANCE_A);

        Test.startTest();
        Boolean paused = TimeTrackingController.reconcileTimer(INSTANCE_B, null, null);
        Test.stopTest();

        System.assertEquals(true, paused);
        Time_Tracking__c record = reload(timer.Id);
        System.assertEquals(TimeTrackingConstants.STATUS_PAUSED_OFFLINE, record.Status__c);
        System.assertEquals(
            [SELECT Last_Heartbeat__c FROM Time_Tracking__c WHERE Id = :timer.Id].Last_Heartbeat__c,
            record.Pause_Started_At__c,
            'Unobserved time after the last heartbeat must not count.'
        );
        System.assert(record.Duration__c >= 20 && record.Duration__c <= 21,
            'Only the ~20 observed minutes count toward the duration, got ' + record.Duration__c);
    }

    @IsTest
    static void reconcileLeavesHealthyAndMissingTimersAlone() {
        Test.startTest();
        System.assertEquals(false, TimeTrackingController.reconcileTimer(INSTANCE_A, null, null), 'No timer: nothing to do.');
        Time_Tracking__c timer = runningTimer(10, 10, INSTANCE_A);
        System.assertEquals(false, TimeTrackingController.reconcileTimer(INSTANCE_A, null, null));
        Test.stopTest();

        System.assertEquals(TimeTrackingConstants.STATUS_IN_PROGRESS, reload(timer.Id).Status__c);
    }

    @IsTest
    static void lateHeartbeatPausesInsteadOfRevivingAnAbandonedTimer() {
        Time_Tracking__c timer = runningTimer(30, 300, INSTANCE_A);

        Test.startTest();
        String status = TimeTrackingController.heartbeat(timer.Id, INSTANCE_A);
        Test.stopTest();

        System.assertEquals(TimeTrackingConstants.STATUS_PAUSED_OFFLINE, status);
        Time_Tracking__c record = reload(timer.Id);
        System.assertEquals(TimeTrackingConstants.STATUS_PAUSED_OFFLINE, record.Status__c);
    }

    @IsTest
    static void freshHeartbeatKeepsTimerRunning() {
        Time_Tracking__c timer = runningTimer(5, 15, INSTANCE_A);

        Test.startTest();
        String status = TimeTrackingController.heartbeat(timer.Id, INSTANCE_A);
        String ignored = TimeTrackingController.heartbeat(null, INSTANCE_A);
        Test.stopTest();

        System.assertEquals(TimeTrackingConstants.STATUS_IN_PROGRESS, status);
        System.assertEquals(null, ignored);
        Time_Tracking__c record = reload(timer.Id);
        System.assertEquals(TimeTrackingConstants.STATUS_IN_PROGRESS, record.Status__c);
        System.assert(record.Last_Heartbeat__c > System.now().addSeconds(-10), 'Heartbeat must be refreshed.');
    }

    @IsTest
    static void resumeAfterOfflinePauseExcludesOfflineTime() {
        Time_Tracking__c timer = runningTimer(30, 600, INSTANCE_A);
        TimeTrackingController.reconcileTimer(INSTANCE_A, null, null);

        Test.startTest();
        TimeTrackingController.TimeTrackingWrapper resumed = TimeTrackingController.resumeTimer(timer.Id, INSTANCE_A, true);
        TimeTrackingController.completeTimer(timer.Id, 'Done');
        Test.stopTest();

        System.assertEquals(TimeTrackingConstants.STATUS_IN_PROGRESS, resumed.status);
        Time_Tracking__c record = reload(timer.Id);
        System.assert(record.Paused_Duration_Minutes__c >= 9.9, 'Offline gap must be recorded as paused minutes.');
        System.assert(record.Duration__c <= 21, 'Offline gap must be excluded from the duration.');
    }

    @IsTest
    static void cleanupJobPausesStaleTimersAndReschedulesItself() {
        Time_Tracking__c stale = runningTimer(30, 600, INSTANCE_A);
        Time_Tracking__c healthy;
        System.runAs(regularUser()) {
            healthy = new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Start_Time__c = System.now().addMinutes(-10),
                Status__c = TimeTrackingConstants.STATUS_IN_PROGRESS,
                Type__c = TimeTrackingConstants.TYPE_INTERNAL_TASK,
                Last_Heartbeat__c = System.now().addSeconds(-20)
            );
            insert healthy;
        }

        Test.startTest();
        new TimeTrackingCleanupScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(TimeTrackingConstants.STATUS_PAUSED_OFFLINE, reload(stale.Id).Status__c);
        System.assertEquals(TimeTrackingConstants.STATUS_IN_PROGRESS, reload(healthy.Id).Status__c);
        String runNamePattern = TimeTrackingCleanupScheduler.RUN_NAME_PREFIX + '%';
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :runNamePattern],
            'The cleanup job must schedule its next run.');
    }

    @IsTest
    static void unscheduleAllRemovesCleanupJobs() {
        Test.startTest();
        TimeTrackingCleanupScheduler.scheduleRecurringJob();
        TimeTrackingCleanupScheduler.unscheduleAll();
        String runNamePattern = TimeTrackingCleanupScheduler.RUN_NAME_PREFIX + '%';
        Integer remaining = [
            SELECT COUNT() FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :runNamePattern OR CronJobDetail.Name = :TimeTrackingCleanupScheduler.WATCHDOG_JOB_NAME
        ];
        Test.stopTest();
        System.assertEquals(0, remaining);
    }

    // ---------- TC-03 / TC-04: paused minutes ----------

    @IsTest
    static void pausedMinutesAreRecordedAndReturnedForLoggedTime() {
        Case c = testCase();
        TimeTrackingController.StartTimerResult started = TimeTrackingController.startTimer(c.Id, null, INSTANCE_A);
        TimeTrackingController.pauseTimer(started.timeTrackingId, TimeTrackingConstants.STATUS_PAUSED_LUNCH, INSTANCE_A);
        // Simulate a 3 minute lunch break.
        update new Time_Tracking__c(Id = started.timeTrackingId, Pause_Started_At__c = System.now().addMinutes(-3));

        Test.startTest();
        TimeTrackingController.resumeTimer(started.timeTrackingId, INSTANCE_A, false);
        TimeTrackingController.completeTimer(started.timeTrackingId, null);
        TimeTrackingController.TimeTrackingData data = TimeTrackingController.getTimeTrackingData(c.Id);
        Test.stopTest();

        System.assertEquals(1, data.records.size());
        Decimal paused = data.records[0].pausedDurationMinutes;
        System.assert(paused >= 2.9 && paused <= 3.1, 'Logged Time must expose the paused minutes, got ' + paused);
        System.assertEquals(false, data.records[0].isManualEntry, 'Timer entries are not manual.');
    }

    // ---------- TC-09 / TC-10: manual entries ----------

    @IsTest
    static void manualEntriesAreFlaggedOnRecordsAndInternalTime() {
        Case c = testCase();
        Datetime endTime = System.now().addHours(-1);

        Test.startTest();
        Id clientEntry = TimeTrackingController.createManualEntry(c.Id, null, endTime.addMinutes(-30), endTime, 'Client call');
        Id internalEntry = TimeTrackingController.createManualEntry(null, TimeTrackingConstants.TYPE_INTERNAL_MEETING,
            endTime.addMinutes(-15), endTime, null);
        TimeTrackingController.TimeTrackingData caseData = TimeTrackingController.getTimeTrackingData(c.Id);
        TimeTrackingController.TimeTrackingData internalData = TimeTrackingController.getTimeTrackingData(null);
        Test.stopTest();

        System.assertEquals(true, reload(clientEntry).Is_Manual_Entry__c);
        System.assertEquals(true, reload(internalEntry).Is_Manual_Entry__c);
        System.assertEquals(true, caseData.records[0].isManualEntry);
        System.assertEquals(TimeTrackingConstants.TYPE_CLIENT, caseData.records[0].type);
        System.assertEquals(TimeTrackingConstants.STATUS_COMPLETED, caseData.records[0].status);
        System.assertEquals(true, internalData.records[0].isManualEntry);
        System.assertEquals(TimeTrackingConstants.TYPE_INTERNAL_MEETING, internalData.records[0].type);
        System.assertEquals(null, internalData.records[0].relatedRecordId);
    }

    // ---------- TC-11 / TC-12: admin edit and delete ----------

    @IsTest
    static void adminPermissionSetGrantsCustomPermission() {
        Boolean adminHasAccess;
        Boolean adminHasCustomPermission;
        Boolean userHasAccess;
        Test.startTest();
        System.runAs(adminUser()) {
            adminHasAccess = TimeTrackingController.getTimeTrackingData(null).isAdmin;
            adminHasCustomPermission = FeatureManagement.checkPermission(TimeTrackingConstants.ADMIN_CUSTOM_PERMISSION);
        }
        System.runAs(regularUser()) {
            userHasAccess = TimeTrackingController.getTimeTrackingData(null).isAdmin;
        }
        Test.stopTest();

        System.assertEquals(true, adminHasAccess, 'Time Tracking Admin users must see Edit/Delete row actions.');
        System.assertEquals(true, adminHasCustomPermission, 'Time Tracking Admin must include Time_Tracking_Admin_Access.');
        System.assertEquals(false, userHasAccess, 'Time Tracking User must not get admin actions.');
    }

    @IsTest
    static void adminCanEditAnotherUsersEntryAndStatusStaysCompleted() {
        Id entryId;
        Datetime endTime = System.now().addHours(-2);
        System.runAs(regularUser()) {
            entryId = TimeTrackingController.createManualEntry(
                null, TimeTrackingConstants.TYPE_INTERNAL_TASK, endTime.addMinutes(-30), endTime, 'Original');
        }
        // A paused interval longer than the edited range must not push the duration negative.
        update new Time_Tracking__c(Id = entryId, Paused_Duration_Minutes__c = 25);

        Test.startTest();
        System.runAs(adminUser()) {
            TimeTrackingController.updateTimeTracking(entryId, endTime.addMinutes(-20), endTime, '  Corrected  ');
        }
        Test.stopTest();

        Time_Tracking__c record = [
            SELECT Status__c, Comments__c, Start_Time__c, End_Time__c, Duration__c, Paused_Duration_Minutes__c, Is_Manual_Entry__c
            FROM Time_Tracking__c WHERE Id = :entryId
        ];
        System.assertEquals(TimeTrackingConstants.STATUS_COMPLETED, record.Status__c);
        System.assertEquals('Corrected', record.Comments__c);
        System.assertEquals(endTime.addMinutes(-20), record.Start_Time__c);
        System.assertEquals(0, record.Paused_Duration_Minutes__c);
        System.assertEquals(20, record.Duration__c);
        System.assertEquals(true, record.Is_Manual_Entry__c, 'Editing keeps the manual flag.');
    }

    @IsTest
    static void regularUserCannotEditOrDelete() {
        Datetime endTime = System.now().addHours(-2);
        Id entryId = TimeTrackingController.createManualEntry(testCase().Id, null, endTime.addMinutes(-30), endTime, null);
        Integer failures = 0;

        Test.startTest();
        System.runAs(regularUser()) {
            try {
                TimeTrackingController.updateTimeTracking(entryId, endTime.addMinutes(-10), endTime, null);
            } catch (AuraHandledException ex) {
                failures++;
            }
            try {
                TimeTrackingController.deleteTimeTracking(entryId, null);
            } catch (AuraHandledException ex) {
                failures++;
            }
        }
        Test.stopTest();

        System.assertEquals(2, failures);
        System.assertEquals(1, [SELECT COUNT() FROM Time_Tracking__c WHERE Id = :entryId]);
    }

    @IsTest
    static void adminDeleteRemovesEntryAndUpdatesTotal() {
        Case c = testCase();
        Datetime endTime = System.now().addHours(-2);
        Id keep = TimeTrackingController.createManualEntry(c.Id, null, endTime.addMinutes(-30), endTime, null);
        Id remove = TimeTrackingController.createManualEntry(c.Id, null, endTime.addMinutes(-90), endTime.addMinutes(-60), null);

        TimeTrackingController.TimeTrackingData before;
        TimeTrackingController.TimeTrackingData afterDelete;
        Test.startTest();
        System.runAs(adminUser()) {
            before = TimeTrackingController.getTimeTrackingData(c.Id);
            TimeTrackingController.deleteTimeTracking(remove, 'Duplicate entry');
            afterDelete = TimeTrackingController.getTimeTrackingData(c.Id);
        }
        Test.stopTest();

        System.assertEquals(60, before.totalMinutes);
        System.assertEquals(30, afterDelete.totalMinutes);
        System.assertEquals(1, afterDelete.records.size());
        System.assertEquals(keep, afterDelete.records[0].id);
    }

    @IsTest
    static void editAndDeleteReportMissingRecords() {
        Datetime endTime = System.now().addHours(-2);
        Id entryId = TimeTrackingController.createManualEntry(testCase().Id, null, endTime.addMinutes(-30), endTime, null);
        delete new Time_Tracking__c(Id = entryId);
        Integer failures = 0;

        Test.startTest();
        System.runAs(adminUser()) {
            try {
                TimeTrackingController.updateTimeTracking(entryId, endTime.addMinutes(-10), endTime, null);
            } catch (AuraHandledException ex) {
                failures++;
            }
            try {
                TimeTrackingController.deleteTimeTracking(entryId, null);
            } catch (AuraHandledException ex) {
                failures++;
            }
        }
        Test.stopTest();
        System.assertEquals(2, failures);
    }
}
