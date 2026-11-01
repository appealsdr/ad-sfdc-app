/******************************************************************************
@author:      Pradeep Kumar
@date:        04 Sep 2025
@description: CaseMessagesController // Apex controller class for handling Case messages operations
******/

public without sharing class CaseMessagesController {

    //=========================================================================
    // Wrapper class for Case_Message__c to send to LWC
    //=========================================================================
    public class CaseMessageWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String messageBody { get; set; }
        @AuraEnabled public String senderType { get; set; }
        @AuraEnabled public Boolean isInternal { get; set; }
        @AuraEnabled public String senderUserName { get; set; }
        @AuraEnabled public String senderContactName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Id replyToMessageId { get; set; }
        @AuraEnabled public Datetime messageRead { get; set; }

        // Constructor maps Case_Message__c to wrapper
        public CaseMessageWrapper(Case_Message__c msg) {
            this.id = msg.Id;
            this.messageBody = msg.Message_Body__c != null
                   ? msg.Message_Body__c.replaceAll('<[^>]+>', '').trim()
                   : '';
            this.senderType = msg.Sender_Type__c;
            this.senderUserName = msg.Sender_User__r != null ? msg.Sender_User__r.Name : null;
            this.senderContactName = msg.Sender_Contact__r != null ? msg.Sender_Contact__r.Name : null;
            this.createdDate = msg.CreatedDate;
            this.isInternal =  msg.Sender_Type__c == 'Internal';
            this.replyToMessageId = msg.Reply_To_Message__c;
            this.messageRead = msg.Message_Read__c;
        }
    }

    //=========================================================================
    // Fetch all messages for a given Case and map to wrapper list
    //=========================================================================
    @AuraEnabled(cacheable=true)
    public static List<CaseMessageWrapper> getCaseMessages(String recordId) {
        System.debug('Fetching messages for Case Id: ' + recordId);
        
        List<Case_Message__c> msgs = [
            SELECT Id, Message_Body__c, Sender_Type__c, CreatedDate,
                   Sender_User__r.Name, Sender_Contact__r.Name,
                   Reply_To_Message__c, Message_Read__c
            FROM Case_Message__c
            WHERE Case__c = :recordId
            ORDER BY CreatedDate ASC
        ];
        
        List<CaseMessageWrapper> wrappedMsgs = new List<CaseMessageWrapper>();
        for(Case_Message__c m : msgs) {
            wrappedMsgs.add(new CaseMessageWrapper(m));
        }

        return wrappedMsgs;
    }

    //=========================================================================
    // Save a new Case_Message__c record for the given Case
    //=========================================================================
    @AuraEnabled
    public static void saveCaseMessage(String caseId, String messageBody, String replyToMessageId) {
        // Validate input
        if (String.isBlank(caseId) || String.isBlank(messageBody)) {
            throw new AuraHandledException('Case Id and Message Body are required.');
        }

        try {
            // Create new Case_Message__c record
            Case_Message__c newMsg = new Case_Message__c(
                Case__c = caseId,
                Message_Body__c = messageBody,
                Sender_Type__c = 'Internal',           // Set sender type as Internal
                Sender_User__c = UserInfo.getUserId(), // Current running user
                Reply_To_Message__c = String.isNotBlank(replyToMessageId) ? (Id) replyToMessageId : null
            );

            insert newMsg; // Insert record
        }
        catch (DmlException dmlEx) {
            // Handle DML errors
            System.debug('Error inserting Case_Message__c: ' + dmlEx.getMessage());
            throw new AuraHandledException('Unable to save message: ' + dmlEx.getMessage());
        }
        catch (Exception ex) {
            // Handle other unexpected errors
            System.debug('Unexpected error: ' + ex.getMessage());
            throw new AuraHandledException('Unexpected error occurred: ' + ex.getMessage());
        }
    }

    //=========================================================================
    // Mark a Case_Message__c as read by the current viewer
    //=========================================================================
    @AuraEnabled
    public static void markMessageRead(String messageId) {
        if (String.isBlank(messageId)) {
            throw new AuraHandledException('Message Id is required.');
        }

        try {
            update new Case_Message__c(
                Id = (Id) messageId,
                Message_Read__c = System.now()
            );
        }
        catch (DmlException dmlEx) {
            System.debug('Error updating Case_Message__c: ' + dmlEx.getMessage());
            throw new AuraHandledException('Unable to mark message read: ' + dmlEx.getMessage());
        }
    }
}