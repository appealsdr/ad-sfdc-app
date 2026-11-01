@IsTest
private class CaseFileDataSenderApiTest {

    /**
     * Mock class for HTTP Callout
     */
    private class CaseFileMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"status":"success","message":"received"}');
            res.setStatusCode(200);
            return res;
        }
    }

    // ------------------------------------------------------------
    // MAIN TEST METHOD
    // ------------------------------------------------------------
    @IsTest
    static void SendCaseFileDataTest() {

        // -----------------------------
        // 1. Create Custom Setting Data
        // -----------------------------
        Appeals_WebhookApi__c cs = new Appeals_WebhookApi__c(
            EndPoint_URL__c = 'https://api.test.com/casefile',
            Api_Key__c = 'TEST-123'
        );
        insert cs;

        // -----------------------------
        // 2. Create test Case + Case_File__c
        // -----------------------------
        Case c = new Case(Status = 'New');
        insert c;

        Case_File__c cFile = new Case_File__c(
            Case__c = c.Id,
            File_Name__c = 'abc.pdf',
            File_Type__c = 'pdf',
            File_Size__c = 100
        );
        insert cFile;

        // -----------------------------
        // 3. Mock callout
        // -----------------------------
        Test.setMock(HttpCalloutMock.class, new CaseFileMock());

        // -----------------------------
        // 4. Prepare invocable inputs
        // -----------------------------
        CaseFileDataSenderApi.InputParams p = new CaseFileDataSenderApi.InputParams();
        p.caseFileId = cFile.Id;
        p.action = 'Create';

        List<CaseFileDataSenderApi.InputParams> paramList = new List<CaseFileDataSenderApi.InputParams>{ p };

        // -----------------------------
        // 5. Call Invocable Method
        // -----------------------------
        Test.startTest();
        CaseFileDataSenderApi.sendCaseFileData(paramList);
        Test.stopTest();

        // -----------------------------
        // 6. Validate Log Inserted
        // -----------------------------
        List<Application_Log__c> logs = [
            SELECT Id, Body__c, Response__c, Error__c 
            FROM Application_Log__c
        ];

        System.assert(!logs.isEmpty(), 'Log should be inserted.');
        System.assert(logs[0].Response__c.contains('success'), 'Response should contain success.');
    }


    // ------------------------------------------------------------
    // TEST TRIGGER BASED CALL
    // ------------------------------------------------------------
    @IsTest
    static void TriggerBasedCallTest() {

        // Custom Setting
        Appeals_WebhookApi__c cs = new Appeals_WebhookApi__c(
            EndPoint_URL__c = 'https://api.test.com/casefile',
            Api_Key__c = 'TEST-123'
        );
        insert cs;

        // Case + Case File
        Case c = new Case(Subject = 'Trigger Test Case');
        insert c;

        Case_File__c file = new Case_File__c(
            Case__c = c.Id,
            File_Name__c = 'file.pdf'
        );
        insert file;

        // Mock callout
        Test.setMock(HttpCalloutMock.class, new CaseFileMock());

        // Call trigger version
        Test.startTest();
        CaseFileDataSenderApi.sendCaseFileDataFromTrigger(
            new Set<Id>{ file.Id },
            'Update'
        );
        Test.stopTest();

        List<Application_Log__c> logs = [
            SELECT Id FROM Application_Log__c
        ];

        System.assert(!logs.isEmpty(), 'Log must be created for trigger call.');
    }
}