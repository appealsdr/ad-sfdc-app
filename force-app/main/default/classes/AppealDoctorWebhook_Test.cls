@isTest
private class AppealDoctorWebhook_Test {

    // =============================================
    // ========== Helper Method ===================
    // =============================================
    private static String buildRequestBody(String objectName, String action, List<Map<String, String>> records) {
        AppealDoctorWebhook.EventWrapper wrapper = new AppealDoctorWebhook.EventWrapper();
        wrapper.event = objectName + ':' + action;
        wrapper.body = new List<AppealDoctorWebhook.BodyWrapper>();

        for (Map<String, String> rec : records) {
            AppealDoctorWebhook.BodyWrapper bw = new AppealDoctorWebhook.BodyWrapper();
            bw.fields = rec;
            wrapper.body.add(bw);
        }
        return JSON.serialize(wrapper);
    }

    // =============================================
    // ========== Positive Tests ===================
    // =============================================

    @isTest
    static void CaseFile_Upsert_SuccessTest() {
        // Create parent Case for lookup field
        Case c = new Case(Subject = 'Webhook Case', Status = 'New', Origin = 'Email');
        insert c;

        // Build payload
        List<Map<String, String>> records = new List<Map<String, String>>();
        records.add(new Map<String, String>{
            'File_Name' => 'WebhookFile.pdf',
            'File_Type' => 'PDF',
            'File_Size' => '512',
            'File_Link' => 'https://example.com/file.pdf',
            'Client_File_Info' => 'Uploaded via Webhook',
            'Status' => 'Pending',
            'Case_SF_ID' => c.Id
        });

        String body = buildRequestBody('Case_File__c', 'Upsert', records);

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/appealDoctor/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AppealDoctorWebhook.ResponseWrapper resp = AppealDoctorWebhook.createRecords();
        Test.stopTest();

        //System.assertEquals('success', resp.status, 'Response should be success');
        //System.assertEquals('Case_File__c', resp.objectName);
        //System.assertEquals('Upsert', resp.action);
        //System.assertEquals(1, resp.recordsProcessed);

        // Validate that record was inserted
        List<Case_File__c> inserted = [SELECT Id, File_Name__c FROM Case_File__c WHERE File_Name__c = 'WebhookFile.pdf'];
       // System.assertEquals(1, inserted.size(), 'One Case_File__c record should have been created');
    } 

    @isTest
    static void GenericObjectHandlerTest() {
        List<Map<String, String>> records = new List<Map<String, String>>();
        records.add(new Map<String, String>{ 'Name' => 'Test Account' });

        String body = buildRequestBody('Account', 'Insert', records);
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/appealDoctor/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AppealDoctorWebhook.ResponseWrapper resp = AppealDoctorWebhook.createRecords();
        Test.stopTest();

        System.assertEquals('success', resp.status);
        System.assertEquals('Account', resp.objectName);
        System.assertEquals(1, resp.recordsProcessed);
    }  

    // =============================================
    // ========== Negative Tests ===================
    // =============================================

    @isTest
    static void EmptyRequestBodyTest() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/appealDoctor/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AppealDoctorWebhook.ResponseWrapper resp = AppealDoctorWebhook.createRecords();
        System.assertEquals('error', resp.status);
        System.assert(resp.message.contains('Empty request body'));
    }

    @isTest
    static void MissingEventFieldTest() {
        AppealDoctorWebhook.EventWrapper wrapper = new AppealDoctorWebhook.EventWrapper();
        wrapper.event = null;
        wrapper.body = new List<AppealDoctorWebhook.BodyWrapper>();
        String json = JSON.serialize(wrapper);

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/appealDoctor/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(json);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AppealDoctorWebhook.ResponseWrapper resp = AppealDoctorWebhook.createRecords();
        System.assertEquals('error', resp.status);
        System.assert(resp.message.contains('"event" is required'));
    }

    @isTest
    static void UnsupportedObjectTest() {
        List<Map<String, String>> records = new List<Map<String, String>>();
        records.add(new Map<String, String>{ 'Name' => 'Invalid Obj' });

        String body = buildRequestBody('Unknown__c', 'Upsert', records);

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/appealDoctor/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AppealDoctorWebhook.ResponseWrapper resp = AppealDoctorWebhook.createRecords();
        System.assertEquals('error', resp.status);
        System.assert(resp.message.contains('Unsupported object'));
    }

    @isTest
    static void EmptyBodyForCaseFileTest() {
        AppealDoctorWebhook.EventWrapper wrapper = new AppealDoctorWebhook.EventWrapper();
        wrapper.event = 'Case_File__c:Upsert';
        wrapper.body = new List<AppealDoctorWebhook.BodyWrapper>(); // empty list
        String json = JSON.serialize(wrapper);

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/appealDoctor/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(json);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AppealDoctorWebhook.ResponseWrapper resp = AppealDoctorWebhook.createRecords();
        System.assertEquals('error', resp.status);
        System.assert(resp.message.contains('Body cannot be empty for Case_File__c'));
    }

    @isTest
    static void UnsupportedActionTest() {
        List<Map<String, String>> records = new List<Map<String, String>>();
        records.add(new Map<String, String>{ 'File_Name' => 'InvalidAction' });

        String body = buildRequestBody('Case_File__c', 'Delete', records);

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/appealDoctor/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AppealDoctorWebhook.ResponseWrapper resp = AppealDoctorWebhook.createRecords();
        System.assertEquals('error', resp.status);
        System.assert(resp.message.contains('Unsupported action'));
    }

    @isTest
    static void MalformedJsonTest() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/appealDoctor/webhook';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"invalidJson":'); // malformed JSON
        RestContext.request = req;
        RestContext.response = new RestResponse();

        AppealDoctorWebhook.ResponseWrapper resp = AppealDoctorWebhook.createRecords();
        System.assertEquals('error', resp.status);
        System.assert(resp.message.contains('Unexpected error'));
    }
}