@isTest
private class DrAppApiFlowProvisionTest {

    private class DrAppMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"account":{"vuid":"acc-uuid","sfdcAccountId":"001x"},"contact":{"vuid":"user-uuid","sfdcContactId":"003x"},'
                + '"stores":[],"username":"jdoe","temporaryPassword":"Temp123!"}');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Dr_App_Api_Setting__c setting = Dr_App_Api_Setting__c.getOrgDefaults();
        setting.Api_Key__c = 'test-key';
        upsert setting;
    }

    @isTest
    static void testProvisionAccountFlow() {
        DrAppApiClient.FlowProvisionInput input = new DrAppApiClient.FlowProvisionInput();
        input.companyName = 'Acme Co';
        input.firstName = 'Jane';
        input.lastName = 'Doe';
        input.email = 'jane.doe@example.com';
        input.phone = '555-1234';
        input.website = 'https://example.com';

        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        Test.startTest();
        List<DrAppApiClient.FlowProvisionOutput> results = DrAppApiFlowProvision.provisionAccountFlow(
            new List<DrAppApiClient.FlowProvisionInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        DrAppApiClient.FlowProvisionOutput out = results[0];
        System.assertEquals('acc-uuid', out.accountVuid);
        System.assertEquals('001x', out.sfdcAccountId);
        System.assertEquals('user-uuid', out.contactVuid);
        System.assertEquals('003x', out.sfdcContactId);
        System.assertEquals('jdoe', out.username);
        System.assertEquals('Temp123!', out.temporaryPassword);
    }

    @isTest
    static void testProvisionAccountFlowMultipleInputs() {
        DrAppApiClient.FlowProvisionInput input1 = new DrAppApiClient.FlowProvisionInput();
        input1.companyName = 'Acme Co';
        input1.lastName = 'Doe';
        input1.email = 'jane.doe@example.com';

        DrAppApiClient.FlowProvisionInput input2 = new DrAppApiClient.FlowProvisionInput();
        input2.companyName = 'Beta Inc';
        input2.lastName = 'Smith';
        input2.email = 'john.smith@example.com';

        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        Test.startTest();
        List<DrAppApiClient.FlowProvisionOutput> results = DrAppApiFlowProvision.provisionAccountFlow(
            new List<DrAppApiClient.FlowProvisionInput>{ input1, input2 }
        );
        Test.stopTest();

        System.assertEquals(2, results.size());
    }
}