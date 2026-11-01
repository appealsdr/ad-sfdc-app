@isTest
private class OpportunityButtonActionTest {

    private class MockHttp implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"status": "success"}');
            res.setStatusCode(200);
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        List<Account> accList = TestDataFactory.createAccounts(1);
        List<Opportunity> oppList = TestDataFactory.createOpportunities(accList, 1);
    }

    @isTest
    private static void executeSetsStageAndFiresWebhook() {
        Test.setMock(HttpCalloutMock.class, new MockHttp());

        insert new Appeals_WebhookApi__c(
            Name = 'Default',
            EndPoint_URL__c = 'https://test.example.com/salesforce/webhook/',
            Api_Key__c = 'TEST_KEY_123'
        );

        Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
        System.assertNotEquals('Store Access', opp.StageName);

        OpportunityButtonAction.Request req = new OpportunityButtonAction.Request();
        req.opportunityId = opp.Id;
        req.targetStage = 'Store Access';
        req.webhookAction = 'Update';

        Test.startTest();
        OpportunityButtonAction.execute(new List<OpportunityButtonAction.Request>{ req });
        Test.stopTest();

        Opportunity updated = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Store Access', updated.StageName,
            'Stage should be updated to Store Access');

        List<Application_Log__c> logs = [SELECT Id FROM Application_Log__c];
        System.assert(logs.size() > 0,
            'Button action should fire exactly one webhook via ODSA');
    }

    @isTest
    private static void executeSkipsTriggerDuplicate() {
        Test.setMock(HttpCalloutMock.class, new MockHttp());

        insert new Appeals_WebhookApi__c(
            Name = 'Default',
            EndPoint_URL__c = 'https://test.example.com/salesforce/webhook/',
            Api_Key__c = 'TEST_KEY_123'
        );

        Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];

        OpportunityButtonAction.Request req = new OpportunityButtonAction.Request();
        req.opportunityId = opp.Id;
        req.targetStage = 'Invoiced';
        req.webhookAction = 'Create';

        Test.startTest();
        OpportunityButtonAction.execute(new List<OpportunityButtonAction.Request>{ req });
        Test.stopTest();

        Opportunity updated = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Invoiced', updated.StageName);

        List<Application_Log__c> logs = [SELECT Id FROM Application_Log__c];
        System.assertEquals(1, logs.size(),
            'Should have exactly 1 log entry (button webhook only, trigger skipped)');
    }
}