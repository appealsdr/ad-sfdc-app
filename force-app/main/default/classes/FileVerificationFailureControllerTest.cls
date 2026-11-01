/******************************************************************************
@author:      Pradeep Lodhi
@date:        03 Sep 2025
@description: Test class for FileVerificationFailureController
******************************************************************************/
@IsTest
public class FileVerificationFailureControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create a sample Case and Client (replace API names if different)
        Case testCase = new Case(Subject = 'Test Case for File Verification');
        insert testCase;

        Account client = new Account(Name = 'Test Client');
        insert client;

        // Create a Case_File__c record linked to the above Case and Client
        Case_File__c file = new Case_File__c(
            Case__c = testCase.Id,
            Client__c = client.Id,
            Info__c = 'Initial Info',
            Verification_Status__c = 'Failed',
            Status_Reason__c = 'Validation Test' 
        );
        insert file;
    }

    @IsTest
    static void testRequestFileAgain_Success() {
        // Retrieve the existing test Case_File__c
        Case_File__c oldFile = [SELECT Id, Case__c, Client__c,Status_Reason__c FROM Case_File__c LIMIT 1];

        // Call the method under test
        String testInfoValue = 'New Info for File Re-request';
        Test.startTest();
        FileVerificationFailureController.requestFileAgain(oldFile.Id, testInfoValue);
        Test.stopTest();

        // Verify new Case_File__c record is created
        List<Case_File__c> files = [
            SELECT Id, Case__c, Client__c, Info__c, Verification_Status__c,Status_Reason__c
            FROM Case_File__c
            WHERE Case__c = :oldFile.Case__c
        ];

        System.assertEquals(2, files.size(), 'Two Case_File__c records should exist (old + new).');

        // Find the new one (not the old)
        Case_File__c newFile = null;
        for (Case_File__c f : files) {
            if (f.Id != oldFile.Id) {
                newFile = f;
                break;
            }
        }

        System.assertNotEquals(null, newFile, 'New Case_File__c should be created.');
        System.assertEquals(oldFile.Case__c, newFile.Case__c, 'New file should link to same Case.');
        System.assertEquals(oldFile.Client__c, newFile.Client__c, 'New file should link to same Client.');
        System.assertEquals('Requested', newFile.Verification_Status__c, 'New file should have status Requested.');
        System.assertEquals(testInfoValue, newFile.Info__c, 'Info__c should match passed value.');
    }

    @IsTest
    static void testRequestFileAgain_InvalidId() {
        // Try calling the method with a fake Id and expect an exception
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            FileVerificationFailureController.requestFileAgain('a0ODi00000A6LkEMAV', 'Info should fail');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
           // System.assert(e.getMessage().contains('Unable to request file again'), 
                         // 'Should throw a handled exception message.');
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected AuraHandledException should be thrown.');
    }
}