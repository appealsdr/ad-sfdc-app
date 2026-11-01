@isTest
private class DrAppApiFlowResetPasswordTest {

    private class DrAppMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"userId":"u-1","username":"jdoe","temporaryPassword":"Temp123!"}');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Dr_App_Api_Setting__c setting = Dr_App_Api_Setting__c.getOrgDefaults();
        setting.Api_Key__c = 'test-key';
        upsert setting;

        Account acct = new Account(Name = 'Test Account');
        insert acct;

        insert new Contact(FirstName = 'Jane', LastName = 'Doe', Email = 'jane.doe@example.com', AccountId = acct.Id);
    }

    @isTest
    static void testResetPasswordFlow() {
        Contact cont = [SELECT Id FROM Contact LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        Test.startTest();
        List<DrAppApiClient.FlowResetPasswordOutput> results = DrAppApiFlowResetPassword.resetPasswordFlow(
            new List<Id>{ cont.Id }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('u-1', results[0].userId);
        System.assertEquals('jdoe', results[0].username);
        System.assertEquals('Temp123!', results[0].temporaryPassword);
    }

    @isTest
    static void testResetPasswordFlowMultipleContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        insert new Contact(FirstName = 'John', LastName = 'Smith', Email = 'john.smith@example.com', AccountId = acct.Id);
        List<Contact> contacts = [SELECT Id FROM Contact];

        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        Test.startTest();
        List<DrAppApiClient.FlowResetPasswordOutput> results = DrAppApiFlowResetPassword.resetPasswordFlow(
            new List<Id>{ contacts[0].Id, contacts[1].Id }
        );
        Test.stopTest();

        System.assertEquals(2, results.size());
    }
}