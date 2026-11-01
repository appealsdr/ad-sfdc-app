/******************************************************************************
@author:      Pradeep Lodhi
@date:        03 Sep 2025
@description: FileVerificationFailureController 
                Apex controller class for handling Case File operations
******************************************************************************/
public class FileVerificationFailureController {

    /**
     * @method       requestFileAgain
     * @description  Marks the given Case File record as "Failed" and creates a new 
     *               Case File record linked to the same Case and Client with status 
     *               "Not Reviewed".
     * @param        caseFileId - The Id of the Case_File__c record to be re-requested.
     */
    @AuraEnabled
        public static Id requestFileAgain(Id caseFileId, String infoValue) {
    try {
        // Fetch old Case File record
        Case_File__c oldFile = [
            SELECT Id, Case__c, Client__c, Document_Type__c, Instructions__c, Short_Description__c
            FROM Case_File__c 
            WHERE Id = :caseFileId
            LIMIT 1
        ];

        // Create new Case File
        Case_File__c newFile = new Case_File__c(
            Case__c   = oldFile.Case__c,   
            Client__c = oldFile.Client__c, 
            Info__c   = infoValue,
            Document_Type__c = oldFile.Document_Type__c,
            Instructions__c = oldFile.Instructions__c,
            Short_Description__c = oldFile.Short_Description__c,
            Verification_Status__c = 'Requested'
        );
        insert newFile;

        // Return new record Id
        return newFile.Id;
    } catch (Exception e) {
        System.debug('Error in requestFileAgain: ' + e.getMessage());
        throw new AuraHandledException('Unable to request file again: ' + e.getMessage());
    }
}

}