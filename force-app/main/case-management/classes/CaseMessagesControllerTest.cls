@isTest
private class CaseMessagesControllerTest {

    //=========================================================================
    // Test Setup: Create reusable records for all test methods
    //=========================================================================
    @testSetup
    static void setupTestData() {
        // Create a test contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert testContact;

        // Create a test case linked to contact
        Case testCase = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Origin = 'Phone',
            ContactId = testContact.Id
        );
        insert testCase;

        // Create initial messages
        List<Case_Message__c> messages = new List<Case_Message__c>{
            new Case_Message__c(
                Case__c = testCase.Id,
                Sender_Type__c = 'Internal',
                Sender_User__c = UserInfo.getUserId(),
                Message_Body__c = 'Message 1'
            ),
            new Case_Message__c(
                Case__c = testCase.Id,
                Sender_Type__c = 'External',
                Sender_Contact__c = testContact.Id,
                Message_Body__c = 'Message 2'
            )
        };
        insert messages;
    }

    //=========================================================================
    // Test getCaseMessages method
    //=========================================================================
    @isTest
    static void testGetCaseMessages() {
        // Get existing test Case
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<CaseMessagesController.CaseMessageWrapper> result = CaseMessagesController.getCaseMessages(testCase.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(2, result.size(), 'Should return 2 messages');

        // Optional: check content
        System.assertEquals('Message 1', result[0].messageBody);
        System.assertEquals('Message 2', result[1].messageBody);
    }

    //=========================================================================
    // Test saveCaseMessage method
    //=========================================================================
    @isTest
    static void testSaveCaseMessage() {
        // Get existing test Case
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        CaseMessagesController.saveCaseMessage(testCase.Id, 'New message', null);
        Test.stopTest();

        // Verify that message was saved
        List<Case_Message__c> savedMessages = [
            SELECT Id, Message_Body__c, Case__c, Sender_Type__c, Sender_User__c
            FROM Case_Message__c
            WHERE Case__c = :testCase.Id
            ORDER BY CreatedDate DESC
        ];

        String expectedMsg ='';
        for(Case_Message__c msg :savedMessages) {
            if(msg.Message_Body__c == 'New message') {
                expectedMsg = msg.Message_Body__c;
                break;
            }
        }

        System.assertEquals('New message', expectedMsg);

    }

    //=========================================================================
    // Test saveCaseMessage as a reply to an existing message
    //=========================================================================
    @isTest
    static void testSaveCaseMessageAsReply() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Case_Message__c original = [
            SELECT Id
            FROM Case_Message__c
            WHERE Case__c = :testCase.Id AND Sender_Type__c = 'Internal'
            LIMIT 1
        ];

        Test.startTest();
        CaseMessagesController.saveCaseMessage(testCase.Id, 'Reply message', original.Id);
        Test.stopTest();

        Case_Message__c reply = [
            SELECT Id, Reply_To_Message__c
            FROM Case_Message__c
            WHERE Case__c = :testCase.Id AND Reply_To_Message__c = :original.Id
            LIMIT 1
        ];

        System.assertEquals(original.Id, reply.Reply_To_Message__c, 'Reply should reference the original message');
    }

    //=========================================================================
    // Test markMessageRead method
    //=========================================================================
    @isTest
    static void testMarkMessageRead() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Case_Message__c message = [
            SELECT Id, Message_Read__c
            FROM Case_Message__c
            WHERE Case__c = :testCase.Id AND Sender_Type__c = 'External'
            LIMIT 1
        ];
        System.assertEquals(null, message.Message_Read__c, 'Message should start unread');

        Test.startTest();
        CaseMessagesController.markMessageRead(message.Id);
        Test.stopTest();

        Case_Message__c updated = [SELECT Id, Message_Read__c FROM Case_Message__c WHERE Id = :message.Id];
        System.assertNotEquals(null, updated.Message_Read__c, 'Message should be marked read');
    }
}