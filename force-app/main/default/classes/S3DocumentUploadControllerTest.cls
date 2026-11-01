@IsTest
private class S3DocumentUploadControllerTest {

    @TestSetup
    static void setupData() {
        Account account = TestDataFactory.createAccounts(1)[0];
        setVuid(account, 'account-vuid-001');

        Opportunity opportunity = new Opportunity(
            Name = 'Upload Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = account.Id
        );
        insert opportunity;

        Store__c store = TestDataFactory.createStores(opportunity.Id, 1)[0];
        store.Account__c = account.Id;
        setVuid(store, 'store-vuid-001');
        update store;

        Case testCase = new Case(
            Subject = 'Upload Test Case',
            Origin = 'Phone',
            Status = 'New',
            AccountId = account.Id,
            Store__c = store.Id
        );
        insert testCase;

        insert new Document_Template__c(
            Name = 'W-9 Template'
        );

        insert new Contract__c(
            Store__c = store.Id
        );

        Appeals_Dr_Setting__c settings = Appeals_Dr_Setting__c.getOrgDefaults();
        if (settings == null || settings.Id == null) {
            insert new Appeals_Dr_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                App_Url__c = 'https://appeals.example.com',
                AWS_S3_Bucket__c = 'amzn-andrei-appeals-dr-test-bucket',
                AWS_Region__c = 'us-east-1',
                AWS_Access_Key_Id__c = 'TESTACCESSKEY',
                AWS_Secret_Access_Key__c = 'TESTSECRETKEY'
            );
        } else {
            settings.App_Url__c = 'https://appeals.example.com';
            settings.AWS_S3_Bucket__c = 'amzn-andrei-appeals-dr-test-bucket';
            settings.AWS_Region__c = 'us-east-1';
            settings.AWS_Access_Key_Id__c = 'TESTACCESSKEY';
            settings.AWS_Secret_Access_Key__c = 'TESTSECRETKEY';
            update settings;
        }
    }

    @IsTest
    static void testGetUploadContextForCase() {
        Case testCase = [SELECT Id, Store__c FROM Case LIMIT 1];
        Store__c store = [SELECT Id, Account__c FROM Store__c WHERE Id = :testCase.Store__c LIMIT 1];

        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper context =
            S3DocumentUploadController.getUploadContext(testCase.Id);
        Test.stopTest();

        System.assertEquals(true, context.uploadAllowed, context.message);
        System.assertEquals('amzn-andrei-appeals-dr-test-bucket', context.bucket);
        String expectedAccountSegment = expectedVuidSegment('Account', 'account-vuid-001', store.Account__c);
        String expectedStoreSegment = expectedVuidSegment('Store__c', 'store-vuid-001', store.Id);
        System.assert(context.message.contains(
            'appealsDrApp/Accounts/' + expectedAccountSegment + '/Stores/' + expectedStoreSegment + '/Issues/'
        ));
    }

    @IsTest
    static void testGetUploadContextForStore() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper context =
            S3DocumentUploadController.getUploadContext(store.Id);
        Test.stopTest();

        System.assertEquals(true, context.uploadAllowed, context.message);
        System.assert(context.message.contains('/Documents/Files/'));
    }

    @IsTest
    static void testGetUploadContextForTemplate() {
        Document_Template__c template = [SELECT Id FROM Document_Template__c LIMIT 1];

        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper context =
            S3DocumentUploadController.getUploadContext(template.Id);
        Test.stopTest();

        System.assertEquals(true, context.uploadAllowed, context.message);
        System.assert(context.message.contains('/Templates/' + template.Id + '/Files/'));
    }

    @IsTest
    static void testGetUploadContextForContractAndAccount() {
        Contract__c contract = [SELECT Id, Store__c FROM Contract__c LIMIT 1];
        Account account = [SELECT Id FROM Account LIMIT 1];
        Store__c contractStore = [SELECT Id, Account__c FROM Store__c WHERE Id = :contract.Store__c LIMIT 1];

        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper contractContext =
            S3DocumentUploadController.getUploadContext(contract.Id);
        S3DocumentUploadService.UploadContextWrapper accountContext =
            S3DocumentUploadController.getUploadContext(account.Id);
        Test.stopTest();

        System.assertEquals(true, contractContext.uploadAllowed, contractContext.message);
        String expectedContractAccountSegment =
            expectedVuidSegment('Account', 'account-vuid-001', contractStore.Account__c);
        System.assert(contractContext.message.contains(
            '/Accounts/' + expectedContractAccountSegment + '/Contracts/' + contract.Id + '/Files/'
        ));
        System.assertEquals(true, accountContext.uploadAllowed, accountContext.message);
        String expectedAccountSegment = expectedVuidSegment('Account', 'account-vuid-001', account.Id);
        System.assert(accountContext.message.contains('/Accounts/' + expectedAccountSegment + '/Files/'));
    }

    @IsTest
    static void testGetUploadContextForUnsupportedObject() {
        Lead lead = new Lead(
            LastName = 'Upload Test Lead',
            Company = 'Upload Test Company'
        );
        insert lead;

        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper context =
            S3DocumentUploadController.getUploadContext(lead.Id);
        Test.stopTest();

        System.assertEquals(false, context.uploadAllowed);
        System.assert(String.isNotBlank(context.message));
    }

    @IsTest
    static void testPrepareAndFinalizeUploadForCase() {
        Case testCase = [SELECT Id, Store__c FROM Case LIMIT 1];
        Store__c store = [SELECT Id, Account__c FROM Store__c WHERE Id = :testCase.Store__c LIMIT 1];

        Test.startTest();
        S3DocumentUploadService.UploadTargetWrapper target =
            S3DocumentUploadController.prepareUpload(testCase.Id, 'invoice.pdf', 'application/pdf', 1024);
        S3DocumentUploadService.FinalizeResultWrapper result =
            S3DocumentUploadController.finalizeUpload(
                testCase.Id,
                'invoice.pdf',
                'application/pdf',
                1024,
                target.s3Key,
                'Test upload'
            );
        Test.stopTest();

        System.assertNotEquals(null, target.uploadUrl);
        System.assert(target.uploadUrl.contains('X-Amz-Signature='));
        String expectedAccountSegment = expectedVuidSegment('Account', 'account-vuid-001', store.Account__c);
        String expectedStoreSegment = expectedVuidSegment('Store__c', 'store-vuid-001', store.Id);
        System.assert(target.s3Key.contains(
            'appealsDrApp/Accounts/' + expectedAccountSegment + '/Stores/' + expectedStoreSegment + '/Issues/'
        ));
        System.assertNotEquals(null, result.documentId);

        S3_Document__c document = [
            SELECT Related_Record_Id__c, Related_Object_Type__c, S3_Key__c, File_Name__c
            FROM S3_Document__c
            WHERE Id = :result.documentId
        ];
        System.assertEquals(String.valueOf(testCase.Id), document.Related_Record_Id__c);
        System.assertEquals('Case', document.Related_Object_Type__c);
        System.assertEquals('invoice.pdf', document.File_Name__c);
    }

    @IsTest
    static void testRequiredFileUploadUpdatesRequiredFile() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Required_File__c requiredFile = new Required_File__c(
            Name = 'Required Invoice',
            Case__c = testCase.Id
        );
        insert requiredFile;

        Test.startTest();
        S3DocumentUploadService.UploadTargetWrapper target =
            S3DocumentUploadController.prepareUpload(requiredFile.Id, 'invoice.pdf', 'application/pdf', 1024);
        S3DocumentUploadService.FinalizeResultWrapper result =
            S3DocumentUploadController.finalizeUpload(
                requiredFile.Id,
                'invoice.pdf',
                'application/pdf',
                1024,
                target.s3Key,
                'Required file upload'
            );
        Test.stopTest();

        Required_File__c refreshedRequiredFile = [
            SELECT File_Uploaded__c, Last_Version__c
            FROM Required_File__c
            WHERE Id = :requiredFile.Id
        ];
        System.assertEquals(true, refreshedRequiredFile.File_Uploaded__c);
        System.assertEquals(result.documentId, refreshedRequiredFile.Last_Version__c);

        S3_Document__c document = [
            SELECT Related_Record_Id__c, Related_Object_Type__c
            FROM S3_Document__c
            WHERE Id = :result.documentId
        ];
        System.assertEquals(String.valueOf(requiredFile.Id), document.Related_Record_Id__c);
        System.assertEquals('Required_File__c', document.Related_Object_Type__c);
    }

    @IsTest
    static void testRequiredFileAcceptedFormatValidation() {
        if (!hasPicklistValue('pdf')) {
            return;
        }

        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Required_File__c requiredFile = new Required_File__c(
            Name = 'Required Invoice',
            Case__c = testCase.Id,
            Accepted_Format__c = 'pdf'
        );
        insert requiredFile;

        Test.startTest();
        Boolean threw = false;
        try {
            S3DocumentUploadController.prepareUpload(
                requiredFile.Id,
                'invoice.docx',
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                1024
            );
        } catch (AuraHandledException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('not allowed'));
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPrepareUploadValidationErrors() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        Boolean missingName = false;
        Boolean oversizeFile = false;
        try {
            S3DocumentUploadController.prepareUpload(testCase.Id, '', 'application/pdf', 1024);
        } catch (AuraHandledException ex) {
            missingName = true;
        }
        try {
            S3DocumentUploadController.prepareUpload(testCase.Id, 'large.pdf', 'application/pdf', 60000000);
        } catch (AuraHandledException ex) {
            oversizeFile = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingName);
        System.assertEquals(true, oversizeFile);
    }
    @IsTest
    static void testGetUploadContextNullRecord() {
        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper context =
            S3DocumentUploadController.getUploadContext(null);
        Test.stopTest();

        System.assertEquals(false, context.uploadAllowed);
        System.assert(String.isNotBlank(context.message));
    }

    @IsTest
    static void testRequiredFileStorePath() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Required_File__c requiredFile = new Required_File__c(
            Name = 'Store Required File',
            Store__c = store.Id
        );
        insert requiredFile;

        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper context =
            S3DocumentUploadController.getUploadContext(requiredFile.Id);
        Test.stopTest();

        System.assertEquals(true, context.uploadAllowed, context.message);
        System.assert(context.message.contains('/Documents/Files/'));
    }

    @IsTest
    static void testRequiredFileTemplatePath() {
        Document_Template__c template = [SELECT Id FROM Document_Template__c LIMIT 1];
        Required_File__c requiredFile = new Required_File__c(
            Name = 'Template Required File',
            Document_Template__c = template.Id
        );
        insert requiredFile;

        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper context =
            S3DocumentUploadController.getUploadContext(requiredFile.Id);
        Test.stopTest();

        System.assertEquals(true, context.uploadAllowed, context.message);
        System.assert(context.message.contains('/Templates/' + template.Id + '/Files/'));
    }
    @IsTest
    static void testRequiredFileWithoutLinks() {
        Required_File__c requiredFile = new Required_File__c(
            Name = 'Orphan Required File'
        );
        insert requiredFile;

        Test.startTest();
        S3DocumentUploadService.UploadContextWrapper context =
            S3DocumentUploadController.getUploadContext(requiredFile.Id);
        Test.stopTest();

        System.assertEquals(false, context.uploadAllowed);
        System.assert(String.isNotBlank(context.message));
    }

    @IsTest
    static void testServiceFinalizeMissingKey() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        Boolean threw = false;
        try {
            S3DocumentUploadService.finalizeUpload(
                testCase.Id,
                'invoice.pdf',
                'application/pdf',
                1024,
                null,
                'Missing key'
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    @IsTest
    static void testBuildObjectKey() {
        S3DocumentPathService.UploadPath path = S3DocumentPathService.resolveUploadPath(
            [SELECT Id FROM Document_Template__c LIMIT 1].Id
        );

        Test.startTest();
        String objectKey = S3DocumentPathService.buildObjectKey(path, 'My File.pdf');
        Test.stopTest();

        System.assert(objectKey.startsWith(path.s3KeyPrefix));
        System.assert(objectKey.endsWith('_My_File.pdf'));
    }

    @IsTest
    static void testUploadFileContent() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        S3DocumentUploadService.UploadTargetWrapper target =
            S3DocumentUploadController.prepareUpload(testCase.Id, 'invoice.pdf', 'application/pdf', 1024);

        Test.setMock(HttpCalloutMock.class, new UploadPresignMock(200, ''));

        Test.startTest();
        S3DocumentUploadController.uploadFileContent(
            target.uploadUrl,
            target.contentType,
            EncodingUtil.base64Encode(Blob.valueOf('pdf-body'))
        );
        Test.stopTest();
    }

    @IsTest
    static void testUploadFileContentFailure() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        S3DocumentUploadService.UploadTargetWrapper target =
            S3DocumentUploadController.prepareUpload(testCase.Id, 'invoice.pdf', 'application/pdf', 1024);

        Test.setMock(HttpCalloutMock.class, new UploadPresignMock(403, 'Forbidden'));

        Test.startTest();
        Boolean threw = false;
        String message = '';
        try {
            S3DocumentUploadController.uploadFileContent(
                target.uploadUrl,
                target.contentType,
                EncodingUtil.base64Encode(Blob.valueOf('pdf-body'))
            );
        } catch (Exception ex) {
            threw = true;
            message = ex.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, threw, message);
    }

    @IsTest
    static void testUploadFileContentValidation() {
        Test.startTest();
        Boolean missingEncodedBody = false;
        Boolean missingUrl = false;
        Boolean missingBlobBody = false;
        try {
            S3DocumentUploadController.uploadFileContent('https://example.com/file', 'application/pdf', '');
        } catch (AuraHandledException ex) {
            missingEncodedBody = true;
        }
        try {
            S3DocumentUploadService.uploadToPresignedUrl(
                '',
                'application/pdf',
                Blob.valueOf('body')
            );
        } catch (AuraHandledException ex) {
            missingUrl = true;
        }
        try {
            S3DocumentUploadService.uploadToPresignedUrl(
                'https://example.com/file',
                'application/pdf',
                Blob.valueOf('')
            );
        } catch (AuraHandledException ex) {
            missingBlobBody = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingEncodedBody);
        System.assertEquals(true, missingUrl);
        System.assertEquals(true, missingBlobBody);
    }

    @IsTest
    static void testUploadUrlService() {
        Appeals_Dr_Setting__c settings = new Appeals_Dr_Setting__c(
            AWS_Access_Key_Id__c = 'TESTACCESSKEY',
            AWS_Secret_Access_Key__c = 'TESTSECRETKEY',
            AWS_Region__c = 'us-east-1'
        );

        Test.startTest();
        S3DocumentUrlService.PresignResponse response = S3DocumentUrlService.createAwsPresignedUrl(
            settings,
            'amzn-andrei-appeals-dr-test-bucket',
            'appealsDrApp/Templates/a1/Files/sample.pdf',
            'us-east-1',
            'sample.pdf',
            'application/pdf',
            S3DocumentUrlService.ACCESS_UPLOAD
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.url.contains('X-Amz-Signature='));
    }

    private static Boolean hasPicklistValue(String value) {
        for (Schema.PicklistEntry entry : Required_File__c.Accepted_Format__c.getDescribe().getPicklistValues()) {
            if (entry.getValue() == value) {
                return true;
            }
        }
        return false;
    }

    private static void setVuid(SObject record, String vuid) {
        if (record.getSObjectType().getDescribe().fields.getMap().containsKey('appealsdoctor_vuid__c')) {
            record.put('appealsdoctor_vuid__c', vuid);
            update record;
        }
    }

    /**
     * S3DocumentPathService falls back to the record's own Id when
     * appealsdoctor_vuid__c isn't present on the object (e.g. production,
     * where Account/Store__c don't have this field). Mirrors that fallback
     * here so assertions hold in orgs with and without the field.
     */
    private static String expectedVuidSegment(String objectApiName, String literalVuid, Id recordId) {
        Schema.SObjectType token = Schema.getGlobalDescribe().get(objectApiName);
        Boolean hasVuidField = token != null
            && token.getDescribe().fields.getMap().containsKey('appealsdoctor_vuid__c');
        return hasVuidField ? literalVuid : String.valueOf(recordId);
    }

    /* =====================================================
       Controller-level error wrapping
       (S3DocumentUploadService.getUploadContext never throws, so the
       controller's getUploadContext has no catch block to cover.)
    ======================================================*/
    @IsTest
    static void testPrepareUploadWrapsUnexpectedException() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        delete testCase;

        Test.startTest();
        Boolean threw = false;
        try {
            S3DocumentUploadController.prepareUpload(testCase.Id, 'invoice.pdf', 'application/pdf', 1024);
        } catch (AuraHandledException ex) {
            // AuraHandledException.getMessage() reliably returns the generic
            // "Script-thrown exception" placeholder when read back in Apex,
            // so the only thing worth asserting here is that this catch -
            // the controller's generic-exception wrapping branch - actually ran.
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    @IsTest
    static void testFinalizeUploadPassesThroughValidationError() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        Boolean threw = false;
        try {
            S3DocumentUploadController.finalizeUpload(
                testCase.Id, 'invoice.pdf', 'application/pdf', 1024, null, 'desc'
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    @IsTest
    static void testFinalizeUploadWrapsUnexpectedException() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        delete testCase;

        Test.startTest();
        Boolean threw = false;
        try {
            S3DocumentUploadController.finalizeUpload(
                testCase.Id, 'invoice.pdf', 'application/pdf', 1024, 'some/key.pdf', 'desc'
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    @IsTest
    static void testUploadFileContentWrapsUnexpectedException() {
        Test.startTest();
        Boolean threw = false;
        try {
            S3DocumentUploadController.uploadFileContent(
                'https://example.com/upload', 'application/pdf', '!!!not-valid-base64!!!'
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    private class UploadPresignMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        UploadPresignMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            response.setHeader('Content-Type', 'application/json');
            return response;
        }
    }
}