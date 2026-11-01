/**
 * CaseStatusCommentController
 *
 * This Apex class provides functionality for handling Case status updates and comments.
 * Date: 09/02/2025
 * Last Modified Date: 09/01/2025
 * Version: 1.0
 */
public with sharing class CaseStatusCommentController {

    //=========================================================================
    // Wrapper class for Case_Message__c to send to LWC
    //=========================================================================
     public class CommentMessageWrapper{ 
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String status {get; set;}
        @AuraEnabled public Boolean internalComment {get; set;}
        @AuraEnabled public String comment {get; set;}
        @AuraEnabled public String senderUserName {get; set;}
       // @AuraEnabled public String senderContactName {get; set;}
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String SourceType {get; set;}
        @AuraEnabled public Boolean Incoming {get; set;}
 
        public CommentMessageWrapper (Case_Comment__c msg){
            this.id = msg.id;
            this.status = msg.Status__c;
            this.internalComment = msg.Internal_Comment__c == true;
            this.comment = msg.Comment__c != null ? msg.Comment__c.replaceAll('<[^>]+>', '').trim() : '';
            this.senderUserName = msg.User_Name__c; 
          //  this.senderContactName = msg.User_Name__c;
            this.SourceType = msg.Source_Type__c;
            this.Incoming = msg.Incoming__c;
            this.createdDate = msg.CreatedDate;
    
       }
   }

    /**
     * Retrieves default comments for a given Case Status.
     *
     * @param statusValue The Case Status for which default comments are required.
     * @return A Map<String, List<String>> where the key is the Case Status and the value is a list of comments.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getDefaultComment(String statusValue) {
        // Initialize a map to store status and corresponding default comments
        Map<String, List<String>> returnMap = new Map<String, List<String>>();

        // Query custom metadata for mappings with the given status
        List<Status_to_Comment_Mapping__mdt> mappings = [
            SELECT Default_Comment__c, Case_Status__c
            FROM Status_to_Comment_Mapping__mdt 
            WHERE Case_Status__c = :statusValue
        ];

        // Loop through each mapping record
        for (Status_to_Comment_Mapping__mdt mapping : mappings) {
            String status = mapping.Case_Status__c; // Status from metadata
            String comment = mapping.Default_Comment__c; // Default comment from metadata
            system.debug('Case Status'+status);

            // Only add non-blank comments
            if (String.isNotBlank(comment)) {
                // If the status is not yet in the map, initialize a new list
                if (!returnMap.containsKey(status)) {
                    returnMap.put(status, new List<String>());
                }
                // Add the comment to the list for this status
                returnMap.get(status).add(comment);
            }
        }

        return returnMap;
    }
    
    /**
     * Updates a Case's status and inserts a related Case Comment record.
     *
     * @param caseId       The Id of the Case to update.
     * @param statusValue  The new Status value for the Case.
     * @param commentBody  The comment text to insert.
     * @param internalOnly Boolean flag indicating if the comment is internal only.
     */
    @AuraEnabled
    public static void saveCaseUpdate(Id caseId, String statusValue, String commentBody, Boolean internalOnly) {
        try {
        // Retrieve the Case record to update
        Case c = [SELECT Id, Status FROM Case WHERE Id = :caseId LIMIT 1];

        // Update the Case status
        c.Status = statusValue;
        update c;
          // Create a new Case Comment record (custom object)
        Case_Comment__c caseComment = new Case_Comment__c();
        caseComment.Case__c = caseId;            // Link to the Case
        caseComment.Status__c = statusValue;     // Record the status
        caseComment.Comment__c = commentBody;    // Add comment text
        caseComment.Internal_Comment__c = internalOnly; // Internal-only flag
        caseComment.Sender_User__c = UserInfo.getUserId();
        insert caseComment;                      // Insert the comment
    } catch (Exception ex) {
        System.debug(' Error in saveCaseUpdate: ' + ex.getMessage());
        throw new AuraHandledException('Error while saving: ' + ex.getMessage());
    }

   }

   
    @AuraEnabled(cacheable=true)
    public static List<CommentMessageWrapper> getMessages(String recordId){
    List<CommentMessageWrapper> wrappedMsgs = new List<CommentMessageWrapper>();

    try {
        List<Case_Comment__c> cMsg = [SELECT Id, Comment__c, Status__c,User_Name__c,Internal_Comment__c,Source_Type__c,Incoming__c, CreatedDate
                FROM Case_Comment__c
                WHERE Case__c = :recordId
                ORDER BY CreatedDate DESC ];
                    
            System.debug('cMsg List data: '+ cMsg);
        for(Case_Comment__c m: cMsg){
            wrappedMsgs.add(new CommentMessageWrapper(m));
        }	 
    } catch(Exception ex){
    
        System.debug('message: ' + ex.getMessage() + ' Line: ' + ex.getLineNumber() + ' Stack Trace: ' + ex.getStackTraceString());
    }
    return wrappedMsgs;
    } 

    

}