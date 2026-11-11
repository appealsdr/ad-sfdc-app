@isTest
private class OpportunityTriggerHandlerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create multiple test accounts using factory
        List<Account> accList =  TestDataFactory.createAccounts(1);
        List<Case> Cases =  TestDataFactory.createCases(accList, 1);
        List<User> users = TestDataFactory.createUsers(1);
        TestDataFactory.createCaseTeamMembers(Cases, users);
        List<Opportunity> OppList = TestDataFactory.createOpportunities(accList, 1);
    }
    
    @isTest
    private static void beforeInsertTest() {
        Opportunity opp = [SELECT Id from Opportunity LIMIT 1];
        User usr = [SELECT Id FROM User LIMIT 1];
        
        List<OpportunityShare> sharesBefore = [
            SELECT Id FROM OpportunityShare
            WHERE OpportunityId = :opp.Id AND UserOrGroupId = :usr.Id
        ];
        System.assertEquals(true, opp != null);
        
    }
    @isTest
    private static void afterUpdateTest() {
        Opportunity opp = [SELECT Id, Name from Opportunity LIMIT 1];
        User usr = [SELECT Id FROM User LIMIT 1];
        Account newAcc =  new Account(Name = 'Test Account' );
        insert newAcc;
        
        System.assertEquals('Test Account', newAcc.Name);
        opp.AccountId = newAcc.Id;
        update opp;
        
        List<OpportunityShare> sharesAfter = [
            SELECT Id FROM OpportunityShare
            WHERE OpportunityId = :opp.Id AND UserOrGroupId = :usr.Id
        ];
        
        System.assertEquals(0, sharesAfter.Size());
    }
    
     @isTest
    private static void deleteTest() {
        Opportunity opp = [SELECT Id, Name from Opportunity LIMIT 1];
        Delete opp;
        
        undelete opp;
    }

    // -----------------------------------------------------------------------
    // Contract Sent stage change — triggers webhook callout
    // -----------------------------------------------------------------------

    private class ContractSentMockHttp implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assertEquals('POST', req.getMethod());
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"status": "success", "message": "contract_sent_processed"}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    private static void contractSentStageChangeFiresWebhookTest() {
        Test.setMock(HttpCalloutMock.class, new ContractSentMockHttp());

        insert new Appeals_WebhookApi__c(
            Name = 'Default',
            EndPoint_URL__c = 'https://test.example.com/salesforce/webhook/',
            Api_Key__c = 'TEST_KEY_123'
        );

        Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
        System.assertNotEquals('Contract Sent', opp.StageName,
            'Test setup Opportunity should not start at Contract Sent stage');

        Test.startTest();
        opp.StageName = 'Contract Sent';
        update opp;
        Test.stopTest();

        List<Application_Log__c> logs = [SELECT Id, Body__c, Response__c FROM Application_Log__c];
        System.assert(logs.size() > 0,
            'Contract Sent stage change should trigger webhook and create Application_Log__c');
        System.assert(logs[0].Body__c.contains('Opportunity'),
            'Log body should contain Opportunity data');
    }

    @isTest
    private static void migrationGuardSuppressesStageSideEffectsTest() {
        Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
        Integer serviceContractsBefore = [SELECT COUNT() FROM ServiceContract WHERE Opportunity__c = :opp.Id];

        Test.startTest();
        OpportunityTriggerHandler.skipWebhookFiring = true;
        opp.StageName = 'Contract Sent';
        update opp;
        OpportunityTriggerHandler.skipWebhookFiring = false;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Application_Log__c],
            'Migration guard should suppress the outbound stage webhook');
        System.assertEquals(serviceContractsBefore,
            [SELECT COUNT() FROM ServiceContract WHERE Opportunity__c = :opp.Id],
            'Migration guard should suppress ServiceContract creation');
    }
    
}
