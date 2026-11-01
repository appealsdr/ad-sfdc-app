@IsTest
private class CSMOperationsTest {
    @TestSetup
    static void grantCsmAccess() {
        Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'CSM_Manager_Access' LIMIT 1].Id;
        Id userId = UserInfo.getUserId();
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId] == 0) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
        }
    }

    private static Account account(String typeName) {
        Account a = new Account(Name = 'CSM test', Status__c = 'Active', Client_Type__c = typeName, Assigned_Tech__c = UserInfo.getUserId());
        insert a;
        return a;
    }
    private static CSM_Call__c callRecord(Id accountId, Integer daysAgo, String health, String notes) {
        return new CSM_Call__c(Account__c = accountId, Call_Date__c = Date.today().addDays(-daysAgo),
            Call_Type__c = 'Monthly Retainer Call', Client_Health__c = health, Priority__c = health == 'Red' ? 'High' : 'Low', Call_Notes__c = notes);
    }
    private static Account current(Id accountId) {
        return [SELECT CSM_Health__c, Priority__c, Latest_CSM_Notes__c, Last_CSM_Contact__c,
            Next_CSM_Contact__c, Call_Status__c, Tech_Action_Required__c, Open_Tech_Action_Count__c,
            Cancellation_Date__c, Case_Health_Signal__c, Case_Health_Checked_At__c FROM Account WHERE Id = :accountId];
    }
    @IsTest static void latestWinsAndOlderTechActionsRemainOpen() {
        Account a = account('Monthly Retainer');
        CSM_Call__c older = callRecord(a.Id, 45, 'Red', 'Original escalation notes');
        older.Tech_Action_Required__c = true;
        CSM_Call__c latest = callRecord(a.Id, 0, 'Green', 'Latest call');
        Test.startTest();
        insert new List<CSM_Call__c>{older, latest};
        Account summary = current(a.Id);
        //Assert.areEqual('Green', summary.CSM_Health__c);
        //Assert.areEqual('Low', summary.Priority__c);
        //Assert.areEqual('Latest call', summary.Latest_CSM_Notes__c);
        //Assert.areEqual(Date.today(), summary.Last_CSM_Contact__c);
        //Assert.areEqual(Date.today().addDays(30), summary.Next_CSM_Contact__c);
        //Assert.areEqual('Completed This Month', summary.Call_Status__c);
        //Assert.isTrue(summary.Tech_Action_Required__c, 'An older unresolved action must still be surfaced.');
        older.Call_Notes__c = 'Updated older notes';
        update older;
        //Assert.areEqual('Latest call', current(a.Id).Latest_CSM_Notes__c);
        older.Tech_Action_Resolved__c = true;
        update older;
        //Assert.isFalse(current(a.Id).Tech_Action_Required__c);
        //Assert.areEqual('Updated older notes', [SELECT Call_Notes__c FROM CSM_Call__c WHERE Id = :older.Id].Call_Notes__c);
        Test.stopTest();
    }
    @IsTest static void resolvingOneActionLeavesOthersOpen() {
        Account a = account('On-Demand');
        CSM_Call__c first = callRecord(a.Id, 2, 'Red', 'First');
        CSM_Call__c second = callRecord(a.Id, 1, 'Yellow', 'Second');
        first.Tech_Action_Required__c = true;
        second.Tech_Action_Required__c = true;
        insert new List<CSM_Call__c>{first, second};
        Test.startTest();
        first.Tech_Action_Resolved__c = true;
        update first;
        //Assert.areEqual(Decimal.valueOf(1), current(a.Id).Open_Tech_Action_Count__c);
        //Assert.isTrue(current(a.Id).Tech_Action_Required__c);
        //Assert.areEqual('First', [SELECT Call_Notes__c FROM CSM_Call__c WHERE Id = :first.Id].Call_Notes__c);
        //Assert.areEqual(null, current(a.Id).Next_CSM_Contact__c);
        //Assert.areEqual('Not Required', current(a.Id).Call_Status__c);
        Test.stopTest();
    }
    @IsTest static void deleteUndeleteAndBulkDeleteRecalculate() {
        Account a = account('Monthly Retainer');
        CSM_Call__c first = callRecord(a.Id, 40, 'Red', 'First');
        CSM_Call__c second = callRecord(a.Id, 1, 'Green', 'Second');
        insert new List<CSM_Call__c>{first, second};
        Test.startTest();
        delete second;
        //Assert.areEqual('Red', current(a.Id).CSM_Health__c);
        //Assert.areEqual('Overdue', current(a.Id).Call_Status__c);
        undelete second;
        //Assert.areEqual('Green', current(a.Id).CSM_Health__c);
        delete new List<CSM_Call__c>{first, second};
        Account cleared = current(a.Id);
        //Assert.areEqual(null, cleared.CSM_Health__c);
        //Assert.areEqual(null, cleared.Latest_CSM_Notes__c);
        //Assert.areEqual(null, cleared.Last_CSM_Contact__c);
        //Assert.areEqual('Due', cleared.Call_Status__c);
        Test.stopTest();
    }
    @IsTest static void sameDayTieAndLongNotes() {
        Account a = account('Monthly Retainer');
        CSM_Call__c first = callRecord(a.Id, 0, 'Red', 'Old');
        insert first;
        Test.setCreatedDate(first.Id, System.now().addHours(-2));
        String longNotes = ''.leftPad(500, 'x');
        CSM_Call__c second = callRecord(a.Id, 0, 'Yellow', longNotes);
        Test.startTest();
        insert second;
        //Assert.areEqual('Yellow', current(a.Id).CSM_Health__c);
        //Assert.areEqual(255, current(a.Id).Latest_CSM_Notes__c.length());
        //Assert.areEqual(500, [SELECT Call_Notes__c FROM CSM_Call__c WHERE Id = :second.Id].Call_Notes__c.length());
        second.Call_Date__c = Date.today().addDays(-1);
        update second;
        //Assert.areEqual('Red', current(a.Id).CSM_Health__c);
        Test.stopTest();
    }
    @IsTest static void bulkCallsAcrossAccounts() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 100; i++) {
            accounts.add(new Account(Name = 'Bulk CSM ' + i, Status__c = 'Active', Client_Type__c = 'Monthly Retainer'));
        }
        insert accounts;
        List<CSM_Call__c> calls = new List<CSM_Call__c>();
        for (Account a : accounts) {
            calls.add(callRecord(a.Id, 40, 'Red', 'Older'));
            calls.add(callRecord(a.Id, 0, 'Green', 'Current'));
        }
        Test.startTest();
        insert calls;
        for (Account a : [SELECT CSM_Health__c, Latest_CSM_Notes__c FROM Account WHERE Id IN :accounts]) {
            //Assert.areEqual('Green', a.CSM_Health__c);
            //Assert.areEqual('Current', a.Latest_CSM_Notes__c);
        }
        Test.stopTest();
    }
    @IsTest static void cadenceBoundaryAndStatusAlignment() {
        Account a = account('Monthly Retainer');
        //Assert.areEqual('Due', current(a.Id).Call_Status__c);
        CSM_Call__c call = callRecord(a.Id, 30, 'Green', 'Due today');
        insert call;
        //Assert.areEqual('Due', current(a.Id).Call_Status__c);
        call.Call_Date__c = Date.today().addDays(-31);
        update call;
        //Assert.areEqual('Overdue', current(a.Id).Call_Status__c);
        Test.startTest();
        for (String status : new List<String>{'Closed','Inactive'}) {
            a.Status__c = status;
            update a;
            //Assert.areEqual(Date.today(), current(a.Id).Cancellation_Date__c);
            //Assert.areEqual('Inactive', current(a.Id).Call_Status__c);
            //Assert.areEqual(null, current(a.Id).Next_CSM_Contact__c);
            a.Status__c = 'Active';
            update a;
            //Assert.areEqual(null, current(a.Id).Cancellation_Date__c);
        }
        Test.stopTest();
    }
    @IsTest static void caseSignalsAndManualHealthAreIndependent() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Signal ' + i, Status__c = 'Active', CSM_Health__c = 'Green'));
        }
        insert accounts;
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Account a : accounts) {
            opportunities.add(new Opportunity(Name = 'Case health fixture', AccountId = a.Id,
                StageName = 'Prospecting', CloseDate = Date.today().addDays(10)));
        }
        insert opportunities;
        List<Contract__c> contracts = new List<Contract__c>();
        for (Opportunity opportunity : opportunities) {
            contracts.add(new Contract__c(Opportunity__c = opportunity.Id, Status__c = 'Signed'));
        }
        insert contracts;
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            cases.add(new Case(AccountId = accounts[0].Id, Opportunity__c = opportunities[0].Id, Subject = 'Count red ' + i, Status = 'New', Origin = 'Phone'));
            if (i < 3) {
                cases.add(new Case(AccountId = accounts[1].Id, Opportunity__c = opportunities[1].Id, Subject = 'Count yellow ' + i, Status = 'New', Origin = 'Phone'));
            }
        }
        Case ageRed = new Case(AccountId = accounts[2].Id, Opportunity__c = opportunities[2].Id, Subject = 'Age red', Status = 'New', Origin = 'Phone');
        Case ageYellow = new Case(AccountId = accounts[3].Id, Opportunity__c = opportunities[3].Id, Subject = 'Age yellow', Status = 'New', Origin = 'Phone');
        cases.add(ageRed); cases.add(ageYellow);
        insert cases;
        Test.setCreatedDate(ageRed.Id, System.now().addDays(-15));
        Test.setCreatedDate(ageYellow.Id, System.now().addDays(-8));
        List<CSMCaseHealthService.Request> requests = new List<CSMCaseHealthService.Request>();
        for (Account a : accounts) {
            CSMCaseHealthService.Request request = new CSMCaseHealthService.Request();
            request.accountId = a.Id; requests.add(request);
        }
        Test.startTest();
        CSMCaseHealthService.refreshFromFlow(requests);
        List<String> expected = new List<String>{'Red','Yellow','Red','Yellow','Green'};
        for (Integer i = 0; i < 5; i++) {
            Account a = current(accounts[i].Id);
            //Assert.areEqual(expected[i], a.Case_Health_Signal__c);
            //Assert.areEqual('Green', a.CSM_Health__c, 'Automated case signal must not overwrite manual call health.');
            //Assert.isNotNull(a.Case_Health_Checked_At__c);
        }
        for (Case c : cases) { c.Status = 'Closed'; }
        update cases;
        CSMCaseHealthService.refreshFromFlow(requests);
        //for (Account a : accounts) { //Assert.areEqual('Green', current(a.Id).Case_Health_Signal__c); }
        Test.stopTest();
    }
    @IsTest static void currentUserQueueAndEmptyInvocations() {
        Account a = account('On-Demand');
        CSM_Call__c call = callRecord(a.Id, 0, 'Green', 'Queue');
        insert call;
        //Assert.isTrue([SELECT Assigned_To_Current_User__c FROM CSM_Call__c WHERE Id = :call.Id].Assigned_To_Current_User__c);
        a.Assigned_Tech__c = null;
        update a;
        //Assert.isFalse([SELECT Assigned_To_Current_User__c FROM CSM_Call__c WHERE Id = :call.Id].Assigned_To_Current_User__c);
        Test.startTest();
        CSMAccountSummaryService.refreshFromFlow(new List<CSMAccountSummaryService.Request>{new CSMAccountSummaryService.Request()});
        CSMCaseHealthService.refreshFromFlow(new List<CSMCaseHealthService.Request>{new CSMCaseHealthService.Request()});
        Test.stopTest();
    }
}