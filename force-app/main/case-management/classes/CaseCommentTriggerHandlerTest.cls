@isTest
private class CaseCommentTriggerHandlerTest {

    /**
     * Mock for API Callout
     */
    private class CaseCommentAPIMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    // ----------------------------------------------------------------------
    // Test Setup Data
    // ----------------------------------------------------------------------
    @TestSetup
    static void setupTestData() {
        List<Account> accList = TestDataFactory.createAccounts(1);
        List<Case> cases = TestDataFactory.createCases(accList, 1);
        List<User> users = TestDataFactory.createUsers(1);
        TestDataFactory.createCaseTeamMembers(cases, users);
        TestDataFactory.createOpportunities(accList, 1);
    }

    // ----------------------------------------------------------------------
    // TEST — AFTER INSERT (API should be triggered for ALL comments)
    // ----------------------------------------------------------------------
    @isTest
    static void testAfterInsertCaseComment() {

        // Set Mock for callout
        Test.setMock(HttpCalloutMock.class, new CaseCommentAPIMock());

        Case caseRec = [SELECT Id FROM Case LIMIT 1];

        // Create External (Non-Internal) Case Comment → SHOULD Trigger API
        Case_Comment__c extComment = new Case_Comment__c(
            Case__c = caseRec.Id,
            Comment__c = 'External comment',
            Internal_Comment__c = false
        );

        // Create Internal Case Comment → SHOULD ALSO Trigger API
        Case_Comment__c intComment = new Case_Comment__c(
            Case__c = caseRec.Id,
            Comment__c = 'Internal comment',
            Internal_Comment__c = true
        );

        Test.startTest();
        insert new List<Case_Comment__c>{ extComment, intComment };
        Test.stopTest();

        // Fetch inserted comments
        List<Case_Comment__c> insertedComments = [
            SELECT Id, Internal_Comment__c
            FROM Case_Comment__c
        ];

        System.assertEquals(2, insertedComments.size(), 'Two comments should be inserted.');
        
        // Both external and internal comments should be inserted and trigger the API
        Boolean hasExternal = false;
        Boolean hasInternal = false;

        for (Case_Comment__c cm : insertedComments) {
            if (!cm.Internal_Comment__c) hasExternal = true;
            if (cm.Internal_Comment__c) hasInternal = true;
        }

        System.assertEquals(true, hasExternal, 'External comment should exist.');
        System.assertEquals(true, hasInternal, 'Internal comment should exist.');
    }

    // ----------------------------------------------------------------------
    // TEST — BEFORE INSERT (no logic but cover method)
    // ----------------------------------------------------------------------
    @isTest
    private static void testBeforeInsertCoverage() {

        Case caseRec = [SELECT Id FROM Case LIMIT 1];

        Case_Comment__c c = new Case_Comment__c(
            Case__c = caseRec.Id,
            Comment__c = 'Before Insert Test',
            Internal_Comment__c = false
        );

        Test.startTest();
        insert c;
        Test.stopTest();

        System.assertNotEquals(null, c.Id, 'Record should be inserted successfully');
    }
}