@IsTest
private class RequiredFileControllerTest {

    @TestSetup
    static void setupData() {
        Account account = TestDataFactory.createAccounts(1)[0];

        Opportunity opportunity = new Opportunity(
            Name = 'Required File Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = account.Id
        );
        insert opportunity;

        Store__c store = TestDataFactory.createStores(opportunity.Id, 1)[0];
        store.Account__c = account.Id;
        update store;

        Case testCase = new Case(
            Subject = 'Required File Test Case',
            Origin = 'Phone',
            Status = 'New',
            AccountId = account.Id,
            Store__c = store.Id
        );
        insert testCase;

        Document_Template__c caseTemplate = new Document_Template__c(
            Name = 'Case Template',
            Object_Api_Name__c = 'Case',
            Short_Description__c = 'Case template description'
        );
        Document_Template__c storeTemplate = new Document_Template__c(
            Name = 'Store Template',
            Object_Api_Name__c = 'Store__c',
            Short_Description__c = 'Store template description'
        );
        if (hasAcceptedFormatValue('pdf')) {
            caseTemplate.Accepted_Format__c = 'pdf';
            storeTemplate.Accepted_Format__c = 'pdf';
        }
        insert new List<Document_Template__c>{ caseTemplate, storeTemplate };

        S3_Document__c document = new S3_Document__c(
            Related_Record_Id__c = testCase.Id,
            Related_Object_Type__c = 'Case',
            S3_Bucket__c = 'test-bucket',
            S3_Key__c = 'appealsDrApp/test.pdf',
            S3_Region__c = 'us-east-1',
            File_Name__c = 'test.pdf',
            File_Extension__c = 'pdf',
            Content_Type__c = 'application/pdf',
            Status__c = 'Active'
        );
        insert document;

        insert new Required_File__c(
            Name = 'Uploaded Case File',
            Case__c = testCase.Id,
            Short_Description__c = 'Uploaded file',
            File_Uploaded__c = true,
            Last_Version__c = document.Id
        );

        Required_File__c pendingStoreFile = new Required_File__c(
            Name = 'Pending Store File',
            Store__c = store.Id,
            Short_Description__c = 'Pending file',
            File_Uploaded__c = false
        );
        if (hasAcceptedFormatValue('pdf')) {
            pendingStoreFile.Accepted_Format__c = 'pdf';
        }
        insert pendingStoreFile;
    }

    @IsTest
    static void testGetRequiredFilesForCase() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> files =
            RequiredFileController.getRequiredFiles(testCase.Id);
        Test.stopTest();

        System.assertEquals(1, files.size());
        System.assertEquals('Uploaded Case File', files[0].name);
        System.assertEquals(true, files[0].fileUploaded);
        System.assertEquals('test.pdf', files[0].uploadedFileName);
        System.assertEquals(true, files[0].canPreview);
    }

    @IsTest
    static void testGetRequiredFilesForStore() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> files =
            RequiredFileController.getRequiredFiles(store.Id);
        Test.stopTest();

        System.assertEquals(1, files.size());
        System.assertEquals('Pending Store File', files[0].name);
        System.assertEquals(false, files[0].fileUploaded);
    }

    @IsTest
    static void testGetDocumentTemplates() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        List<RequiredFileController.TemplateWrapper> caseTemplates =
            RequiredFileController.getDocumentTemplates(testCase.Id);
        List<RequiredFileController.TemplateWrapper> storeTemplates =
            RequiredFileController.getDocumentTemplates(store.Id);
        Test.stopTest();

        System.assertEquals(1, caseTemplates.size());
        System.assertEquals('Case Template', caseTemplates[0].name);
        System.assertEquals(1, storeTemplates.size());
        System.assertEquals('Store Template', storeTemplates[0].name);
    }

    @IsTest
    static void testCreateRequiredFileDefault() {
        if (!hasAcceptedFormatValue('pdf')) {
            return;
        }

        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        Id requiredFileId = RequiredFileController.createRequiredFileDefault(
            testCase.Id,
            'New Required File',
            'pdf',
            'Short description',
            '<p>Instructions</p>'
        );
        Test.stopTest();

        Required_File__c createdFile = [
            SELECT Name, Case__c, Short_Description__c, Accepted_Format__c, Instructions__c
            FROM Required_File__c
            WHERE Id = :requiredFileId
        ];
        System.assertEquals('New Required File', createdFile.Name);
        System.assertEquals(testCase.Id, createdFile.Case__c);
        System.assertEquals('Short description', createdFile.Short_Description__c);
        System.assertEquals('pdf', createdFile.Accepted_Format__c);
    }

    @IsTest
    static void testCreateRequiredFileFromTemplate() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Document_Template__c template = [
            SELECT Id
            FROM Document_Template__c
            WHERE Object_Api_Name__c = 'Store__c'
            LIMIT 1
        ];

        Test.startTest();
        Id requiredFileId = RequiredFileController.createRequiredFileFromTemplate(store.Id, template.Id);
        Test.stopTest();

        Required_File__c createdFile = [
            SELECT Name, Store__c, Document_Template__c, Short_Description__c, Accepted_Format__c
            FROM Required_File__c
            WHERE Id = :requiredFileId
        ];
        System.assertEquals('Store Template', createdFile.Name);
        System.assertEquals(store.Id, createdFile.Store__c);
        System.assertEquals(template.Id, createdFile.Document_Template__c);
        System.assertEquals('Store template description', createdFile.Short_Description__c);
    }

    @IsTest
    static void testValidationErrors() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        Boolean missingName = false;
        try {
            RequiredFileController.createRequiredFileDefault(testCase.Id, '', 'pdf', 'Short', null);
        } catch (AuraHandledException ex) {
            missingName = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingName);
    }

    private static Boolean hasAcceptedFormatValue(String value) {
        for (Schema.PicklistEntry entry : Required_File__c.Accepted_Format__c.getDescribe().getPicklistValues()) {
            if (entry.getValue() == value) {
                return true;
            }
        }
        return false;
    }
}