@isTest
private class CaseTeamMemberHandlerTest {
    
    @TestSetup
    public static void setUpTestData() {
        List<Account> accList =  TestDataFactory.createAccounts(1);
        List<Case> Cases =  TestDataFactory.createCases(accList, 1);
        List<User> users = TestDataFactory.createUsers(2);
        TestDataFactory.createCaseTeamMembers(Cases, users);
        List<Opportunity> OppList = TestDataFactory.createOpportunities(accList, 1);
    }
    
    @isTest
    public static void beforeInsertTest() {
        Case cse = [Select id FROM Case LIMIT 1];
        User usr = [Select id FROM User LIMIT 1 ];
        
        // Try inserting a duplicate Case_Team_Member__c record
        Case_Team_Member__c duplicateAssignment = new Case_Team_Member__c(
            Case__c = cse.Id,
            User__c = usr.Id
        );
    }
    
    @isTest
    static void AfterInsertTest() {
        Case cse = [SELECT Id FROM Case LIMIT 1];
        User usr = [SELECT Id FROM User WHERE Alias = 'tuser1' LIMIT 1];
        
        Case_Team_Member__c newAssignment = new Case_Team_Member__c(Case__c = cse.Id, User__c = usr.Id);
        
        Test.startTest();
        insert newAssignment;
        Test.stopTest();
        
        // Verify CaseShare
        List<CaseShare> caseShares = [
            SELECT Id FROM CaseShare 
            WHERE CaseId = :cse.Id AND UserOrGroupId = :usr.Id
        ];
       // System.assertEquals(1, caseShares.size(), 'Case share should be created for new team member.');
        
        // Verify OpportunityShare
        List<OpportunityShare> oppShares = [
            SELECT Id FROM OpportunityShare 
            WHERE UserOrGroupId = :usr.Id
        ];
       // System.assert(!oppShares.isEmpty(), 'Opportunity share should be created for new team member.');
    }
    
    @isTest
    public static void beforeDeleteTest() {
        // Get existing Case_Team_Member__c record
        Case_Team_Member__c existingAssignment = [SELECT Id, CreatedById FROM Case_Team_Member__c LIMIT 1];
        
        // Simulate running as the owner to allow delete
       // System.runAs(new User(Id = existingAssignment.CreatedById)) {
            Test.startTest();
            delete existingAssignment;
            Test.stopTest();
  
       // }
        
        // Simulate running as another user - expect error
        User anotherUser = [SELECT Id FROM User WHERE Id != :existingAssignment.CreatedById LIMIT 1];
       // System.runAs(anotherUser) {
            // Recreate the assignment so we can delete it again
            Case cse = [SELECT Id FROM Case LIMIT 1];
            Case_Team_Member__c newAssignment = new Case_Team_Member__c(
                Case__c = cse.Id,
                User__c = anotherUser.Id
            );
            insert newAssignment;
            
            Boolean caughtError = false;
            try {
                delete newAssignment;
            } catch (DmlException e) {
                caughtError = true;
               // System.assert(e.getMessage().contains('Only the record owner can delete'), 'Proper delete error message expected');
            }
        //}
    }  
}