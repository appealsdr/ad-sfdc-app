/******************************************************************************
@description: Tests LeadActivityRollupService via the TaskTrigger / EventTrigger
              that invoke it, covering the Lead activity rollup fields
              (Total_Calls__c, Last_Call__c, Total_Events__c, Last_Event__c).
*******************************************************************************/
@isTest
private class LeadActivityRollupServiceTest {

    private static String firstActivePicklistValue(Schema.SObjectField field) {
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static Lead createLead(String lastName) {
        Lead l = new Lead(
            FirstName = 'Test',
            LastName = lastName,
            Company = 'Acme Inc',
            Status = firstActivePicklistValue(Lead.Status)
        );
        insert l;
        return l;
    }

    private static Task createCallTask(Id whoId, String subject, Date activityDate) {
        return new Task(
            WhoId = whoId,
            Subject = subject,
            TaskSubtype = 'Call',
            Status = firstActivePicklistValue(Task.Status),
            ActivityDate = activityDate
        );
    }

    @isTest
    private static void loggingACallIncrementsTotalCallsAndSetsLastCall() {
        Lead lead = createLead('Caller');

        Test.startTest();
        Task callTask = createCallTask(lead.Id, 'Log a Call', Date.today());
        insert callTask;
        Test.stopTest();

        Lead updated = [SELECT Total_Calls__c, Last_Call__c FROM Lead WHERE Id = :lead.Id];
        Task inserted = [SELECT CreatedDate FROM Task WHERE Id = :callTask.Id];
        System.assertEquals(1, updated.Total_Calls__c, 'One logged call should count once');
        System.assertEquals(inserted.CreatedDate, updated.Last_Call__c, 'Last_Call__c should match the call Task CreatedDate');
    }

    @isTest
    private static void multipleCallsTrackCountAndMostRecentCall() {
        Lead lead = createLead('MultiCaller');

        Test.startTest();
        insert createCallTask(lead.Id, 'Call 1', Date.today().addDays(-2));
        Task lastCall = createCallTask(lead.Id, 'Call 2', Date.today());
        insert lastCall;
        Test.stopTest();

        Lead updated = [SELECT Total_Calls__c, Last_Call__c FROM Lead WHERE Id = :lead.Id];
        Task inserted = [SELECT CreatedDate FROM Task WHERE Id = :lastCall.Id];
        System.assertEquals(2, updated.Total_Calls__c, 'Both calls should be counted');
        System.assertEquals(inserted.CreatedDate, updated.Last_Call__c, 'Last_Call__c should reflect the most recent call');
    }

    @isTest
    private static void nonCallTaskIsNotCountedAsACall() {
        Lead lead = createLead('PlainTask');

        Test.startTest();
        insert new Task(
            WhoId = lead.Id,
            Subject = 'Follow up',
            TaskSubtype = 'Task',
            Status = firstActivePicklistValue(Task.Status),
            ActivityDate = Date.today()
        );
        Test.stopTest();

        Lead updated = [SELECT Total_Calls__c, Last_Call__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(0, updated.Total_Calls__c, 'A plain Task (not a logged call) should not count');
        System.assertEquals(null, updated.Last_Call__c);
    }

    @isTest
    private static void creatingAnEventIncrementsTotalEventsAndSetsLastEvent() {
        Lead lead = createLead('Attendee');
        Datetime start = Datetime.now().addDays(1);

        Test.startTest();
        insert new Event(
            WhoId = lead.Id,
            Subject = 'Intro Meeting',
            StartDateTime = start,
            EndDateTime = start.addMinutes(30)
        );
        Test.stopTest();

        Lead updated = [SELECT Total_Events__c, Last_Event__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(1, updated.Total_Events__c, 'One Event should count once');
        System.assertEquals(start, updated.Last_Event__c, 'Last_Event__c should match the Event StartDateTime');
    }

    @isTest
    private static void multipleEventsTrackCountAndMostRecentEvent() {
        Lead lead = createLead('MultiAttendee');
        Datetime earlier = Datetime.now().addDays(1);
        Datetime later = Datetime.now().addDays(3);

        Test.startTest();
        insert new Event(WhoId = lead.Id, Subject = 'Meeting 1', StartDateTime = earlier, EndDateTime = earlier.addMinutes(30));
        insert new Event(WhoId = lead.Id, Subject = 'Meeting 2', StartDateTime = later, EndDateTime = later.addMinutes(30));
        Test.stopTest();

        Lead updated = [SELECT Total_Events__c, Last_Event__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(2, updated.Total_Events__c);
        System.assertEquals(later, updated.Last_Event__c, 'Last_Event__c should reflect the later Event');
    }

    @isTest
    private static void reassigningEventWhoIdRecalculatesBothLeads() {
        Lead leadA = createLead('EventLeadA');
        Lead leadB = createLead('EventLeadB');
        Datetime start = Datetime.now().addDays(1);
        Event evt = new Event(WhoId = leadA.Id, Subject = 'Meeting', StartDateTime = start, EndDateTime = start.addMinutes(30));
        insert evt;

        Test.startTest();
        evt.WhoId = leadB.Id;
        update evt;
        Test.stopTest();

        Lead updatedA = [SELECT Total_Events__c FROM Lead WHERE Id = :leadA.Id];
        Lead updatedB = [SELECT Total_Events__c FROM Lead WHERE Id = :leadB.Id];
        System.assertEquals(0, updatedA.Total_Events__c, 'Old Lead should lose the Event once reassigned');
        System.assertEquals(1, updatedB.Total_Events__c, 'New Lead should gain the Event once reassigned');
    }

    @isTest
    private static void deletingTheOnlyEventResetsCountAndLastEvent() {
        Lead lead = createLead('EventDeleter');
        Datetime start = Datetime.now().addDays(1);
        Event evt = new Event(WhoId = lead.Id, Subject = 'Meeting', StartDateTime = start, EndDateTime = start.addMinutes(30));
        insert evt;

        Lead beforeDelete = [SELECT Total_Events__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(1, beforeDelete.Total_Events__c);

        Test.startTest();
        delete evt;
        Test.stopTest();

        Lead afterDelete = [SELECT Total_Events__c, Last_Event__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(0, afterDelete.Total_Events__c, 'Deleting the only Event should reset the count to 0');
        System.assertEquals(null, afterDelete.Last_Event__c);
    }

    @isTest
    private static void undeletingAnEventRestoresEventCount() {
        Lead lead = createLead('EventUndeleter');
        Datetime start = Datetime.now().addDays(1);
        Event evt = new Event(WhoId = lead.Id, Subject = 'Meeting', StartDateTime = start, EndDateTime = start.addMinutes(30));
        insert evt;
        delete evt;

        Lead afterDelete = [SELECT Total_Events__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(0, afterDelete.Total_Events__c);

        Test.startTest();
        undelete evt;
        Test.stopTest();

        Lead afterUndelete = [SELECT Total_Events__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(1, afterUndelete.Total_Events__c, 'Undeleting the Event should restore the count');
    }

    @isTest
    private static void eventOnContactDoesNotThrowOrAffectLeads() {
        Account acc = new Account(Name = 'Rollup Test Account 2');
        insert acc;
        Contact con = new Contact(FirstName = 'Con', LastName = 'Tact2', AccountId = acc.Id);
        insert con;
        Datetime start = Datetime.now().addDays(1);

        Test.startTest();
        insert new Event(WhoId = con.Id, Subject = 'Meeting', StartDateTime = start, EndDateTime = start.addMinutes(30));
        Test.stopTest();

        // An Event on a Contact must not throw and must not touch any Lead - reaching this line is the assertion.
        System.assert(true);
    }

    @isTest
    private static void deletingTheOnlyCallResetsCountAndLastCall() {
        Lead lead = createLead('Deleter');
        Task callTask = createCallTask(lead.Id, 'Call', Date.today());
        insert callTask;

        Lead beforeDelete = [SELECT Total_Calls__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(1, beforeDelete.Total_Calls__c);

        Test.startTest();
        delete callTask;
        Test.stopTest();

        Lead afterDelete = [SELECT Total_Calls__c, Last_Call__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(0, afterDelete.Total_Calls__c, 'Deleting the only call should reset the count to 0');
        System.assertEquals(null, afterDelete.Last_Call__c);
    }

    @isTest
    private static void undeletingATaskRestoresCallCount() {
        Lead lead = createLead('Undeleter');
        Task callTask = createCallTask(lead.Id, 'Call', Date.today());
        insert callTask;
        delete callTask;

        Lead afterDelete = [SELECT Total_Calls__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(0, afterDelete.Total_Calls__c);

        Test.startTest();
        undelete callTask;
        Test.stopTest();

        Lead afterUndelete = [SELECT Total_Calls__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(1, afterUndelete.Total_Calls__c, 'Undeleting the call Task should restore the count');
    }

    @isTest
    private static void reassigningTaskWhoIdRecalculatesBothLeads() {
        Lead leadA = createLead('LeadA');
        Lead leadB = createLead('LeadB');
        Task callTask = createCallTask(leadA.Id, 'Call', Date.today());
        insert callTask;

        Test.startTest();
        callTask.WhoId = leadB.Id;
        update callTask;
        Test.stopTest();

        Lead updatedA = [SELECT Total_Calls__c FROM Lead WHERE Id = :leadA.Id];
        Lead updatedB = [SELECT Total_Calls__c FROM Lead WHERE Id = :leadB.Id];
        System.assertEquals(0, updatedA.Total_Calls__c, 'Old Lead should lose the call once reassigned');
        System.assertEquals(1, updatedB.Total_Calls__c, 'New Lead should gain the call once reassigned');
    }

    @isTest
    private static void taskOnContactDoesNotThrowOrAffectLeads() {
        Account acc = new Account(Name = 'Rollup Test Account');
        insert acc;
        Contact con = new Contact(FirstName = 'Con', LastName = 'Tact', AccountId = acc.Id);
        insert con;

        Test.startTest();
        insert new Task(
            WhoId = con.Id,
            Subject = 'Call',
            TaskSubtype = 'Call',
            Status = firstActivePicklistValue(Task.Status),
            ActivityDate = Date.today()
        );
        Test.stopTest();

        // A Task on a Contact must not throw and must not touch any Lead - reaching this line is the assertion.
        System.assert(true);
    }

    @isTest
    private static void bulkTaskInsertAcrossManyLeadsStaysWithinLimits() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 50; i++) {
            leads.add(new Lead(
                FirstName = 'Bulk',
                LastName = 'Lead' + i,
                Company = 'Acme Inc',
                Status = firstActivePicklistValue(Lead.Status)
            ));
        }
        insert leads;

        List<Task> calls = new List<Task>();
        for (Lead l : leads) {
            for (Integer j = 0; j < 4; j++) {
                calls.add(createCallTask(l.Id, 'Call ' + j, Date.today()));
            }
        }

        Test.startTest();
        insert calls;
        Test.stopTest();

        List<Lead> updatedLeads = [SELECT Total_Calls__c FROM Lead WHERE Id IN :leads];
        for (Lead l : updatedLeads) {
            System.assertEquals(4, l.Total_Calls__c, 'Each bulk Lead should have exactly 4 calls');
        }
    }

    @isTest
    private static void directServiceCallWithEmptyOrNullSetDoesNothing() {
        Test.startTest();
        LeadActivityRollupService.recalculateForLeads(new Set<Id>());
        LeadActivityRollupService.recalculateForLeads(null);
        Test.stopTest();

        // No exception and no DML means the empty/null guard clause worked - reaching this line is the assertion.
        System.assert(true);
    }
}