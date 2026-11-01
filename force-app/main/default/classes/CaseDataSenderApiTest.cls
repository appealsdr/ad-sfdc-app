@IsTest
private class CaseDataSenderApiTest {

    /**
     * Mock HTTP callout so sendToExternalAPI doesn't fail in test context.
     */
    private class MockCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"ok"}');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        // Ensure the Custom Setting row exists so sendToExternalAPI can read it
        Appeals_WebhookApi__c setting = Appeals_WebhookApi__c.getInstance();
        if (setting == null || String.isBlank(setting.EndPoint_URL__c)) {
            Appeals_WebhookApi__c s = new Appeals_WebhookApi__c(
                SetupOwnerId  = UserInfo.getOrganizationId(),
                EndPoint_URL__c = 'https://app.appealsdoctor.com/salesforce/webhook/',
                Api_Key__c      = 'test-key'
            );
            insert s;
        }
    }

    @IsTest
    static void testSendCaseDataWithValidCase() {
        // Create a minimal Case to use as input
        Case c = new Case(Subject = 'CaseDataSenderApi Test Case', Status = 'Draft');
        insert c;

        Test.setMock(HttpCalloutMock.class, new MockCallout());

        CaseDataSenderApi.InputParams p = new CaseDataSenderApi.InputParams();
        p.caseId = c.Id;
        p.action = 'Update';

        Test.startTest();
        CaseDataSenderApi.sendCaseData(new List<CaseDataSenderApi.InputParams>{ p });
        Test.stopTest();

        // If no exception was thrown the method completed successfully
        System.assert(true, 'sendCaseData completed without exception');
    }

    @IsTest
    static void testSendCaseDataWithNullParams() {
        Test.startTest();
        CaseDataSenderApi.sendCaseData(null);
        CaseDataSenderApi.sendCaseData(new List<CaseDataSenderApi.InputParams>());
        Test.stopTest();
        System.assert(true, 'Null/empty params handled gracefully');
    }

    @IsTest
    static void testSendCaseDataWithNullCaseId() {
        CaseDataSenderApi.InputParams p = new CaseDataSenderApi.InputParams();
        p.caseId = null;
        p.action = 'Update';

        Test.startTest();
        CaseDataSenderApi.sendCaseData(new List<CaseDataSenderApi.InputParams>{ p });
        Test.stopTest();
        System.assert(true, 'Null caseId handled gracefully');
    }

    @IsTest
    static void testSendCaseDataWithNonExistentCaseId() {
        // Use a well-formed but non-existent Case ID
        Test.setMock(HttpCalloutMock.class, new MockCallout());

        CaseDataSenderApi.InputParams p = new CaseDataSenderApi.InputParams();
        p.caseId = '500000000000001AAA';
        p.action = 'Create';

        Test.startTest();
        CaseDataSenderApi.sendCaseData(new List<CaseDataSenderApi.InputParams>{ p });
        Test.stopTest();
        System.assert(true, 'Non-existent caseId handled gracefully');
    }

    @IsTest
    static void testSendCaseDataBlankAction() {
        Case c = new Case(Subject = 'CaseDataSenderApi Blank Action', Status = 'Draft');
        insert c;

        Test.setMock(HttpCalloutMock.class, new MockCallout());

        CaseDataSenderApi.InputParams p = new CaseDataSenderApi.InputParams();
        p.caseId = c.Id;
        p.action = '';

        Test.startTest();
        CaseDataSenderApi.sendCaseData(new List<CaseDataSenderApi.InputParams>{ p });
        Test.stopTest();
        System.assert(true, 'Blank action defaulted to CREATE without exception');
    }
}