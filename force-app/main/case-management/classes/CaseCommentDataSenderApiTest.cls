@isTest
public class CaseCommentDataSenderApiTest {

    // ------------------------------------------------------
    // Mock Class for HTTP Callout
    // ------------------------------------------------------
    private class MockWebhookResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"message": "Success"}');
            return res;
        }
    }

    // ------------------------------------------------------
    // Create Test Data
    // ------------------------------------------------------
    private static Case_Comment__c createTestCaseComment() {
        Case c = new Case(Status = 'New');
        insert c;

        Case_Comment__c cm = new Case_Comment__c(
            Case__c = c.Id,
            Comment__c = 'Test Comment'
            
        );
        insert cm;

        return cm;
    }

    // ------------------------------------------------------
    // Create Custom Setting
    // ------------------------------------------------------
    private static void createWebhookConfig() {
        Appeals_WebhookApi__c config = Appeals_WebhookApi__c.getInstance();
        config.EndPoint_URL__c = 'https://test-endpoint.com/api';
        config.Api_Key__c = 'TESTKEY123';
        upsert config;
    }

    // ------------------------------------------------------
    // Test sendCaseCommentData (Core Logic)
    // ------------------------------------------------------
    @isTest
    static void testSendCaseCommentData() {

        createWebhookConfig();
        Case_Comment__c cm = createTestCaseComment();

        Test.startTest();

        Test.setMock(HttpCalloutMock.class, new MockWebhookResponse());

        CaseCommentDataSenderApi.sendCaseCommentData(
            new Set<Id>{cm.Id},
            'CREATE'
        );

        Test.stopTest();

        // Validate Application_Log__c
        Application_Log__c log = [SELECT Id, Body__c, Response__c FROM Application_Log__c LIMIT 1];
        System.assertNotEquals(null, log, 'Log must be created');
       // System.assert(log.Body__c.contains('"object_type"'), 'Payload must contain object_type');
        System.assert(log.Response__c.contains('Success'), 'Response must be stored');
    }

    // ------------------------------------------------------
    // Test sendCaseCommentDataFromFlow
    // ------------------------------------------------------
    @isTest
    static void testFlowMethod() {

        createWebhookConfig();
        Case_Comment__c cm = createTestCaseComment();

        CaseCommentDataSenderApi.InputParams input = new CaseCommentDataSenderApi.InputParams();
        input.commentId = cm.Id;
        input.action = 'UPDATE';

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockWebhookResponse());

        CaseCommentDataSenderApi.sendCaseCommentDataFromFlow(
            new List<CaseCommentDataSenderApi.InputParams>{input}
        );

        Test.stopTest();

        Integer logs = [SELECT COUNT() FROM Application_Log__c];
        System.assertEquals(2, logs, 'Log should be created from trigger insert and Flow Method');
    }

    // ------------------------------------------------------
    // Test sendCaseCommentDataFromTrigger
    // ------------------------------------------------------
    @isTest
    static void testTriggerMethod() {

        createWebhookConfig();
        Case_Comment__c cm = createTestCaseComment();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockWebhookResponse());

        CaseCommentDataSenderApi.SendCaseCommentDataFromTrigger(
            new Set<Id>{cm.Id},
            'CREATE'
        );

        Test.stopTest();

        //Integer logs = [SELECT COUNT() FROM Application_Log__c];
        //System.assertEquals(1, logs, 'Log must be generated from Trigger Method');
    }

    // ------------------------------------------------------
    // Test for Null / Empty Inputs
    // ------------------------------------------------------
    @isTest
    static void testNullInputs() {

        Test.startTest();
        CaseCommentDataSenderApi.sendCaseCommentDataFromFlow(new List<CaseCommentDataSenderApi.InputParams>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Application_Log__c]);
    }
}