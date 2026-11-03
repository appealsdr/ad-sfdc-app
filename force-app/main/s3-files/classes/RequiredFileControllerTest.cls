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

        Required_File__c uploadedCaseFile = new Required_File__c(
            Name = 'Uploaded Case File',
            Case__c = testCase.Id,
            Short_Description__c = 'Uploaded file',
            File_Uploaded__c = true,
            Last_Version__c = document.Id
        );
        insert uploadedCaseFile;
        document.Required_File__c = uploadedCaseFile.Id;
        update document;

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
        System.assertEquals('requiredFile', files[0].rowType);
        System.assertEquals(true, files[0].fileUploaded);
        System.assertEquals('test.pdf', files[0].uploadedFileName);
        System.assertEquals(true, files[0].canPreview);
        System.assertEquals(1, files[0].uploadedFiles.size());
        System.assertEquals(files[0].lastVersionId, files[0].uploadedFiles[0].id);
        System.assertEquals('test.pdf', files[0].uploadedFiles[0].name);
        System.assertEquals(true, files[0].uploadedFiles[0].canPreview);
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
        System.assertEquals('requiredFile', files[0].rowType);
        System.assertEquals(false, files[0].fileUploaded);
        System.assertEquals(0, files[0].uploadedFiles.size());
    }

    @IsTest
    static void testMultipleUploadsAreGroupedByLookup() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Required_File__c requiredFile = [
            SELECT Id, Last_Version__c FROM Required_File__c WHERE Case__c = :testCase.Id LIMIT 1
        ];
        Required_File__c otherRequirement = new Required_File__c(
            Name = 'Another Case Requirement',
            Case__c = testCase.Id
        );
        insert otherRequirement;

        S3_Document__c secondUpload = buildDocument(testCase.Id, 'second.zip', 'Active');
        secondUpload.Required_File__c = requiredFile.Id;
        secondUpload.Description__c = 'Supporting evidence';
        S3_Document__c otherUpload = buildDocument(testCase.Id, 'other.pdf', 'Active');
        otherUpload.Required_File__c = otherRequirement.Id;
        insert new List<S3_Document__c>{ secondUpload, otherUpload };

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> files =
            RequiredFileController.getRequiredFiles(testCase.Id);
        Test.stopTest();

        Map<Id, RequiredFileController.RequiredFileWrapper> filesById =
            new Map<Id, RequiredFileController.RequiredFileWrapper>();
        for (RequiredFileController.RequiredFileWrapper file : files) {
            filesById.put(file.id, file);
        }
        System.assertEquals(2, files.size());
        RequiredFileController.RequiredFileWrapper uploaded = filesById.get(requiredFile.Id);
        System.assertEquals(2, uploaded.uploadedFiles.size());
        System.assertEquals(true, uploaded.fileUploaded);
        Set<Id> uploadedIds = new Set<Id>();
        for (RequiredFileController.UploadedFileWrapper document : uploaded.uploadedFiles) {
            uploadedIds.add(document.id);
            if (document.id == secondUpload.Id) {
                System.assertEquals('second.zip', document.name);
                System.assertEquals('Supporting evidence', document.shortDescription);
                System.assertEquals(false, document.canPreview);
            }
        }
        System.assertEquals(new Set<Id>{ requiredFile.Last_Version__c, secondUpload.Id }, uploadedIds);
        System.assertEquals(1, filesById.get(otherRequirement.Id).uploadedFiles.size());
        System.assertEquals(otherUpload.Id, filesById.get(otherRequirement.Id).uploadedFiles[0].id);
    }

    @IsTest
    static void testUnassignedUploadIsStandaloneDespiteLastVersion() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Required_File__c requiredFile = [
            SELECT Id, Last_Version__c FROM Required_File__c WHERE Case__c = :testCase.Id LIMIT 1
        ];
        update new S3_Document__c(Id = requiredFile.Last_Version__c, Required_File__c = null);

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> files =
            RequiredFileController.getRequiredFiles(testCase.Id);
        Test.stopTest();

        System.assertEquals(2, files.size());
        System.assertEquals('requiredFile', files[0].rowType);
        System.assertEquals(0, files[0].uploadedFiles.size());
        System.assertEquals(false, files[0].fileUploaded);
        System.assertEquals(false, files[0].canPreview);
        System.assertEquals('uploadedFile', files[1].rowType);
        System.assertEquals(requiredFile.Last_Version__c, files[1].id);
        System.assertEquals('test.pdf', files[1].name);
        System.assertEquals(true, files[1].canPreview);
        System.assertEquals(0, files[1].uploadedFiles.size());
    }

    @IsTest
    static void testStoreUploadsDoNotRequireLastVersionOrUploadedFlag() {
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Required_File__c requiredFile = [
            SELECT Id FROM Required_File__c WHERE Store__c = :store.Id LIMIT 1
        ];
        S3_Document__c firstUpload = buildDocument(store.Id, 'first.pdf', 'Active');
        firstUpload.Required_File__c = requiredFile.Id;
        S3_Document__c secondUpload = buildDocument(store.Id, 'second.pdf', 'Active');
        secondUpload.Required_File__c = requiredFile.Id;
        S3_Document__c standaloneUpload = buildDocument(store.Id, 'standalone.pdf', 'Active');
        insert new List<S3_Document__c>{ firstUpload, secondUpload, standaloneUpload };

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> files =
            RequiredFileController.getRequiredFiles(store.Id);
        Test.stopTest();

        System.assertEquals(2, files.size());
        System.assertEquals(2, files[0].uploadedFiles.size());
        System.assertEquals(true, files[0].fileUploaded);
        System.assertEquals('Yes', files[0].uploadedLabel);
        System.assertEquals('uploadedFile', files[1].rowType);
        System.assertEquals(standaloneUpload.Id, files[1].id);
        System.assertEquals(0, files[1].uploadedFiles.size());
    }

    @IsTest
    static void testInactiveLastVersionDoesNotAppearAsAnUpload() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Required_File__c requiredFile = [
            SELECT Id, Last_Version__c FROM Required_File__c WHERE Case__c = :testCase.Id LIMIT 1
        ];
        update new S3_Document__c(Id = requiredFile.Last_Version__c, Status__c = 'Deleted');

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> files =
            RequiredFileController.getRequiredFiles(testCase.Id);
        S3_Document__c activeUpload = buildDocument(testCase.Id, 'active.pdf', 'Active');
        activeUpload.Required_File__c = requiredFile.Id;
        insert activeUpload;
        List<RequiredFileController.RequiredFileWrapper> filesWithActiveUpload =
            RequiredFileController.getRequiredFiles(testCase.Id);
        Test.stopTest();

        System.assertEquals(0, files[0].uploadedFiles.size());
        System.assertEquals(false, files[0].fileUploaded);
        System.assertEquals('No', files[0].uploadedLabel);
        System.assertEquals(false, files[0].canPreview);
        System.assertEquals(1, filesWithActiveUpload[0].uploadedFiles.size());
        System.assertEquals(true, filesWithActiveUpload[0].fileUploaded);
        System.assertEquals(false, filesWithActiveUpload[0].canPreview);
        System.assertEquals(true, filesWithActiveUpload[0].uploadedFiles[0].canPreview);
    }

    @IsTest
    static void testDocumentsAreReturnedWithoutAnyRequirements() {
        Case sourceCase = [SELECT AccountId, Store__c, Status, Origin FROM Case LIMIT 1];
        Case documentOnlyCase = sourceCase.clone(false, false, false, false);
        documentOnlyCase.Subject = 'Documents Without Requirements';
        insert documentOnlyCase;
        S3_Document__c standaloneUpload = buildDocument(documentOnlyCase.Id, 'standalone.zip', 'Active');
        standaloneUpload.Description__c = 'A standalone attachment';
        insert standaloneUpload;

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> files =
            RequiredFileController.getRequiredFiles(documentOnlyCase.Id);
        Test.stopTest();

        System.assertEquals(1, files.size());
        System.assertEquals(standaloneUpload.Id, files[0].id);
        System.assertEquals('uploadedFile', files[0].rowType);
        System.assertEquals('standalone.zip', files[0].name);
        System.assertEquals('A standalone attachment', files[0].shortDescription);
        System.assertEquals(false, files[0].canPreview);
        System.assertEquals(0, files[0].uploadedFiles.size());
    }

    @IsTest
    static void testInactiveAndOtherParentDocumentsAreExcluded() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Required_File__c requiredFile = [
            SELECT Id, Last_Version__c FROM Required_File__c WHERE Case__c = :testCase.Id LIMIT 1
        ];
        S3_Document__c deletedUpload = buildDocument(testCase.Id, 'deleted.pdf', 'Deleted');
        deletedUpload.Required_File__c = requiredFile.Id;
        S3_Document__c archivedUpload = buildDocument(testCase.Id, 'archived.pdf', 'Archived');
        archivedUpload.Required_File__c = requiredFile.Id;
        S3_Document__c otherParentUpload = buildDocument(store.Id, 'other-parent.pdf', 'Active');
        otherParentUpload.Required_File__c = requiredFile.Id;
        S3_Document__c oldLinkedUpload = buildDocument(requiredFile.Id, 'old-link.pdf', 'Active');
        oldLinkedUpload.Required_File__c = requiredFile.Id;
        insert new List<S3_Document__c>{
            deletedUpload,
            archivedUpload,
            otherParentUpload,
            oldLinkedUpload,
            buildDocument(testCase.Id, 'inactive-standalone.pdf', 'Deleted')
        };
        update new Required_File__c(Id = requiredFile.Id, Last_Version__c = oldLinkedUpload.Id);

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> files =
            RequiredFileController.getRequiredFiles(testCase.Id);
        Test.stopTest();

        System.assertEquals(1, files.size());
        System.assertEquals(requiredFile.Id, files[0].id);
        System.assertEquals(1, files[0].uploadedFiles.size());
        System.assertEquals(requiredFile.Last_Version__c, files[0].uploadedFiles[0].id);
        System.assertEquals(false, files[0].canPreview);
        System.assertEquals(null, files[0].uploadedFileName);
    }

    @IsTest
    static void testLookupToAnotherParentsRequirementRemainsStandalone() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Required_File__c storeRequirement = [
            SELECT Id FROM Required_File__c WHERE Store__c = :store.Id LIMIT 1
        ];
        S3_Document__c mismatchedUpload = buildDocument(testCase.Id, 'mismatched.pdf', 'Active');
        mismatchedUpload.Required_File__c = storeRequirement.Id;
        insert mismatchedUpload;

        Test.startTest();
        List<RequiredFileController.RequiredFileWrapper> caseFiles =
            RequiredFileController.getRequiredFiles(testCase.Id);
        List<RequiredFileController.RequiredFileWrapper> storeFiles =
            RequiredFileController.getRequiredFiles(store.Id);
        Test.stopTest();

        System.assertEquals(2, caseFiles.size());
        System.assertEquals('requiredFile', caseFiles[0].rowType);
        System.assertEquals(1, caseFiles[0].uploadedFiles.size());
        System.assertEquals('uploadedFile', caseFiles[1].rowType);
        System.assertEquals(mismatchedUpload.Id, caseFiles[1].id);
        System.assertEquals(0, caseFiles[1].uploadedFiles.size());
        System.assertEquals(1, storeFiles.size());
        System.assertEquals(storeRequirement.Id, storeFiles[0].id);
        System.assertEquals(0, storeFiles[0].uploadedFiles.size());
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

    private static S3_Document__c buildDocument(Id relatedRecordId, String fileName, String status) {
        return new S3_Document__c(
            Related_Record_Id__c = relatedRecordId,
            Related_Object_Type__c = relatedRecordId.getSObjectType().getDescribe().getName(),
            S3_Bucket__c = 'test-bucket',
            S3_Key__c = 'appealsDrApp/' + relatedRecordId + '/' + fileName,
            S3_Region__c = 'us-east-1',
            File_Name__c = fileName,
            Content_Type__c = fileName.endsWith('.pdf') ? 'application/pdf' : 'application/zip',
            Status__c = status
        );
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
