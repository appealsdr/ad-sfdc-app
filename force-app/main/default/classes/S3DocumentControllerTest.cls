@IsTest
private class S3DocumentControllerTest {

    @TestSetup
    static void setupData() {
        Account account = TestDataFactory.createAccounts(1)[0];
        Case testCase = new Case(
            Subject = 'S3 Document Test Case',
            Origin = 'Phone',
            Status = 'New',
            AccountId = account.Id
        );
        insert testCase;

        insert new S3_Document__c(
            Related_Record_Id__c = testCase.Id,
            Related_Object_Type__c = 'Case',
            S3_Bucket__c = 'appeals-doctor',
            S3_Key__c = 'cases/' + testCase.Id + '/sample.pdf',
            S3_Region__c = 'us-east-1',
            File_Name__c = 'sample.pdf',
            File_Extension__c = 'pdf',
            Content_Type__c = 'application/pdf',
            File_Size_Bytes__c = 2048,
            File_URL__c = 'https://example.com/sample.pdf',
            Preview_URL__c = 'https://example.com/sample-preview.pdf',
            Preview_Expires_At__c = System.now().addHours(2),
            Download_URL__c = 'https://example.com/sample-download.pdf',
            Download_Expires_At__c = System.now().addHours(2),
            Preview_Status__c = 'Ready',
            Status__c = 'Active',
            Uploaded_By__c = UserInfo.getUserId(),
            Uploaded_Date__c = System.now()
        );
    }

    @IsTest
    static void testGetDocuments() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<S3DocumentController.DocumentWrapper> documents =
            S3DocumentController.getDocuments(testCase.Id);
        Test.stopTest();

        System.assertEquals(1, documents.size());
        System.assertEquals('sample.pdf', documents[0].fileName);
        System.assertEquals(true, documents[0].isPreviewable);
        System.assertEquals('PDF', documents[0].previewType);
    }

    @IsTest
    static void testGetDocumentsForS3DocumentRecord() {
        S3_Document__c document = [SELECT Id FROM S3_Document__c LIMIT 1];

        Test.startTest();
        List<S3DocumentController.DocumentWrapper> documents =
            S3DocumentController.getDocuments(document.Id);
        Test.stopTest();

        System.assertEquals(1, documents.size());
        System.assertEquals(document.Id, documents[0].id);
        System.assertEquals('sample.pdf', documents[0].fileName);
    }

    @IsTest
    static void testGetDocumentsForRequiredFileWithLastVersion() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        S3_Document__c lastVersionDocument = new S3_Document__c(
            Related_Record_Id__c = testCase.Id,
            Related_Object_Type__c = 'Case',
            S3_Bucket__c = 'appeals-doctor',
            S3_Key__c = 'cases/' + testCase.Id + '/latest.pdf',
            S3_Region__c = 'us-east-1',
            File_Name__c = 'latest.pdf',
            File_Extension__c = 'pdf',
            Content_Type__c = 'application/pdf',
            File_Size_Bytes__c = 1024,
            Status__c = 'Active',
            Uploaded_By__c = UserInfo.getUserId(),
            Uploaded_Date__c = System.now()
        );
        insert lastVersionDocument;

        Required_File__c requiredFile = new Required_File__c(
            Name = 'Required Upload',
            Case__c = testCase.Id,
            File_Uploaded__c = true,
            Last_Version__c = lastVersionDocument.Id
        );
        insert requiredFile;

        Test.startTest();
        List<S3DocumentController.DocumentWrapper> documents =
            S3DocumentController.getDocuments(requiredFile.Id);
        Test.stopTest();

        System.assertEquals(1, documents.size());
        System.assertEquals(lastVersionDocument.Id, documents[0].id);
        System.assertEquals('latest.pdf', documents[0].fileName);
    }

    @IsTest
    static void testGetDocumentsForRequiredFileWithRelatedDocuments() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Required_File__c requiredFile = new Required_File__c(
            Name = 'Required Upload Related',
            Case__c = testCase.Id
        );
        insert requiredFile;

        insert new S3_Document__c(
            Related_Record_Id__c = requiredFile.Id,
            Related_Object_Type__c = 'Required_File__c',
            S3_Bucket__c = 'appeals-doctor',
            S3_Key__c = 'required/' + requiredFile.Id + '/attached.pdf',
            S3_Region__c = 'us-east-1',
            File_Name__c = 'attached.pdf',
            File_Extension__c = 'pdf',
            Content_Type__c = 'application/pdf',
            File_Size_Bytes__c = 1024,
            Status__c = 'Active',
            Uploaded_By__c = UserInfo.getUserId(),
            Uploaded_Date__c = System.now()
        );

        Test.startTest();
        List<S3DocumentController.DocumentWrapper> documents =
            S3DocumentController.getDocuments(requiredFile.Id);
        Test.stopTest();

        System.assertEquals(1, documents.size());
        System.assertEquals('attached.pdf', documents[0].fileName);
    }

    @IsTest
    static void testGetDocumentAccessUsesCachedPreviewUrl() {
        S3_Document__c document = [SELECT Id FROM S3_Document__c LIMIT 1];

        Test.startTest();
        S3DocumentController.DocumentAccessWrapper access =
            S3DocumentController.getDocumentAccess(document.Id, 'preview');
        Test.stopTest();

        System.assertEquals('https://example.com/sample-preview.pdf', access.url);
        System.assertEquals('preview', access.accessType);
        System.assertEquals(true, access.isPreviewable);
    }

    @IsTest
    static void testGetDocumentAccessUsesCachedDownloadUrl() {
        S3_Document__c document = [SELECT Id FROM S3_Document__c LIMIT 1];

        Test.startTest();
        S3DocumentController.DocumentAccessWrapper access =
            S3DocumentController.getDocumentAccess(document.Id, 'download');
        Test.stopTest();

        System.assertEquals('https://example.com/sample-download.pdf', access.url);
        System.assertEquals('download', access.accessType);
    }

    @IsTest
    static void testPresignRefreshesUrlsWithAwsCredentials() {
        S3_Document__c document = [
            SELECT Id, Preview_URL__c, Preview_Expires_At__c
            FROM S3_Document__c
            LIMIT 1
        ];
        document.Preview_URL__c = null;
        document.Preview_Expires_At__c = null;
        document.Download_URL__c = null;
        document.Download_Expires_At__c = null;
        update document;

        Appeals_Dr_Setting__c settings = Appeals_Dr_Setting__c.getOrgDefaults();
        if (settings == null || settings.Id == null) {
            insert new Appeals_Dr_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                AWS_Access_Key_Id__c = 'TESTACCESSKEY',
                AWS_Secret_Access_Key__c = 'TESTSECRETKEY',
                AWS_Region__c = 'us-east-1'
            );
        } else {
            settings.AWS_Access_Key_Id__c = 'TESTACCESSKEY';
            settings.AWS_Secret_Access_Key__c = 'TESTSECRETKEY';
            settings.AWS_Region__c = 'us-east-1';
            update settings;
        }

        Test.startTest();
        S3DocumentController.DocumentAccessWrapper access =
            S3DocumentController.getDocumentAccess(document.Id, 'preview');
        Test.stopTest();

        System.assert(access.url.contains('X-Amz-Signature='));

        S3_Document__c refreshedDocument = [
            SELECT Preview_URL__c, Preview_Expires_At__c
            FROM S3_Document__c
            WHERE Id = :document.Id
        ];
        System.assert(refreshedDocument.Preview_URL__c.contains('X-Amz-Signature='));
        System.assertNotEquals(null, refreshedDocument.Preview_Expires_At__c);
    }

    @IsTest
    static void testResolveAccessUsesFileUrlFallback() {
        S3_Document__c document = [
            SELECT Id
            FROM S3_Document__c
            LIMIT 1
        ];
        document.Preview_URL__c = null;
        document.Preview_Expires_At__c = null;
        document.S3_Bucket__c = null;
        document.S3_Key__c = null;
        document.File_URL__c = 'https://example.com/fallback.pdf';
        update document;

        S3_Document__c refreshedDocument = S3DocumentUrlService.queryDocument(document.Id);

        Test.startTest();
        S3DocumentUrlService.DocumentAccess access =
            S3DocumentUrlService.resolveAccess(refreshedDocument, S3DocumentUrlService.ACCESS_PREVIEW);
        Test.stopTest();

        System.assertEquals('https://example.com/fallback.pdf', access.url);
    }

    @IsTest
    static void testCreateAwsPresignedPreviewUrl() {
        Appeals_Dr_Setting__c settings = new Appeals_Dr_Setting__c(
            AWS_Access_Key_Id__c = 'TESTACCESSKEY',
            AWS_Secret_Access_Key__c = 'TESTSECRETKEY',
            AWS_Region__c = 'us-east-1'
        );

        Test.startTest();
        S3DocumentUrlService.PresignResponse response = S3DocumentUrlService.createAwsPresignedUrl(
            settings,
            'appeals-doctor',
            'appealsDrApp/Templates/a1/Files/sample.pdf',
            'us-east-1',
            'sample.pdf',
            'application/pdf',
            S3DocumentUrlService.ACCESS_PREVIEW
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.url.contains('X-Amz-Signature='));
        System.assert(!response.url.contains('response-content-disposition='));
    }

    @IsTest
    static void testCreateAwsPresignedDownloadUrl() {
        Appeals_Dr_Setting__c settings = new Appeals_Dr_Setting__c(
            AWS_Access_Key_Id__c = 'TESTACCESSKEY',
            AWS_Secret_Access_Key__c = 'TESTSECRETKEY',
            AWS_Region__c = 'us-east-1'
        );

        Test.startTest();
        S3DocumentUrlService.PresignResponse response = S3DocumentUrlService.createAwsPresignedUrl(
            settings,
            'appeals-doctor',
            'appealsDrApp/Templates/a1/Files/sample.pdf',
            'us-east-1',
            'sample.pdf',
            'application/pdf',
            S3DocumentUrlService.ACCESS_DOWNLOAD
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.url.contains('response-content-disposition='));
    }
}