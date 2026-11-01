@isTest
private class CaseFileControllerTest {

    // Utility method to create test data
    private static Case createTestCase() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Case c = new Case(Subject = 'Test Case', AccountId = acc.Id);
        insert c;

        return c;
    }

    private static List<Case_Document_Type_List__c> createDocTypeList() {
        List<Case_Document_Type_List__c> docTypes = new List<Case_Document_Type_List__c>();
        docTypes.add(new Case_Document_Type_List__c(
            Case_Document_Type_Label__c = 'Bank Information linked to the account',
            Case_Document_Type_Value__c = 'bank_information',
            Short_Description__c = 'Bank account or payment details linked to the seller account',
            Instructions__c = 'XYZ'
        ));
        docTypes.add(new Case_Document_Type_List__c(
            Case_Document_Type_Label__c = 'Brand Registration Certificate',
            Case_Document_Type_Value__c = 'brand_registration_certificate',
            Short_Description__c = 'Official certificate showing registered brand ownership',
            Instructions__c = 'ABC'
        ));
        insert docTypes;
        return docTypes;
    }

    @IsTest
    static void testGetCaseDocTypeList() {
        // Prepare test data
        createDocTypeList();

        // Run method
        Test.startTest();
        List<Case_Document_Type_List__c> result = CaseFileController.getCaseDocTypeList();
        Test.stopTest();

        // Assertions
        System.assertNotEquals(0, result.size(), 'Expected non-empty result');
        System.assertEquals('Bank Information linked to the account', result[0].Case_Document_Type_Label__c, 'Label should match');
    }

    @IsTest
    static void testCreateCaseFile_Success() {
        // Create related data
        Case testCase = createTestCase();
        createDocTypeList();

        // Prepare input
        CaseFileController.DocTypeInput input1 = new CaseFileController.DocTypeInput();
        input1.documentTypeLabel = 'Bank Information linked to the account';
        input1.shortDescription = 'bank_information';
        input1.instructions = 'Bank account or payment details linked to the seller account';

        CaseFileController.DocTypeInput input2 = new CaseFileController.DocTypeInput();
        input2.documentTypeLabel = 'Brand Registration Certificate';
        input2.shortDescription = 'brand_registration_certificate';
        input2.instructions = 'Official certificate showing registered brand ownership';

        List<CaseFileController.DocTypeInput> docInputs = new List<CaseFileController.DocTypeInput>{ input1, input2 };

        // Run method
        Test.startTest();
        String result = CaseFileController.createCaseFile(docInputs, testCase.Id);
        Test.stopTest();

        // Assertions
        System.assertEquals('Success', result, 'Expected success response');
        List<Case_File__c> createdFiles = [SELECT Id, Document_Type__c, Case__c, Client__c FROM Case_File__c WHERE Case__c = :testCase.Id];
        System.assertEquals(2, createdFiles.size(), 'Expected two Case_File__c records created');
        System.assertEquals(testCase.AccountId, createdFiles[0].Client__c, 'Client should match Account');
    }

    @IsTest
    static void testCreateCaseFile_InvalidCaseId() {
        // Prepare input with invalid CaseId
        CaseFileController.DocTypeInput input = new CaseFileController.DocTypeInput();
        input.documentTypeLabel = 'Test Doc';
        input.shortDescription = 'Desc';
        input.instructions = 'Instr';

        List<CaseFileController.DocTypeInput> docInputs = new List<CaseFileController.DocTypeInput>{ input };

        Test.startTest();
        String result = CaseFileController.createCaseFile(docInputs, null);
        Test.stopTest();

        System.assert(result.startsWith('Error'), 'Expected error for invalid Case ID');
    }

    @IsTest
    static void testCreateCaseFile_EmptyDocTypes() {
        Case testCase = createTestCase();

        Test.startTest();
        String result = CaseFileController.createCaseFile(new List<CaseFileController.DocTypeInput>(), testCase.Id);
        Test.stopTest();

        System.assert(result.startsWith('Error'), 'Expected error for empty document list');
    }
}