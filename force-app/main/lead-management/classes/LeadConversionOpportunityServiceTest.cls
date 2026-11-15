@IsTest
private class LeadConversionOpportunityServiceTest {

    @TestSetup
    static void setupUsersAndSettings() {
        Profile profileRecord = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String unique = String.valueOf(DateTime.now().getTime());
        User manager = new User(
            Alias = 'mgrtest',
            Email = 'manager.' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Conversion Manager',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileRecord.Id,
            TimeZoneSidKey = 'America/New_York',
            Username = 'manager.' + unique + '@example.com'
        );
        insert manager;
        insert new User(
            Alias = 'opentest',
            Email = 'opener.' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Conversion Opener',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ManagerId = manager.Id,
            ProfileId = profileRecord.Id,
            TimeZoneSidKey = 'America/New_York',
            Username = 'opener.' + unique + '@example.com'
        );
        insert new Opportunity_Automation_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Set_Closer_From_Opener_Manager__c = true
        );
    }

    @IsTest
    static void conversionSetsOpenerToLeadOwnerAndCloserToManager() {
        User opener = [
            SELECT Id, ManagerId
            FROM User
            WHERE LastName = 'Conversion Opener'
            LIMIT 1
        ];
        Lead leadRecord = new Lead(
            FirstName = 'Converted',
            LastName = 'Customer',
            Company = 'Converted Customer Co',
            OwnerId = opener.Id,
            Status = firstOpenLeadStatus()
        );
        insert leadRecord;

        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];
        Database.LeadConvert request = new Database.LeadConvert();
        request.setLeadId(leadRecord.Id);
        request.setConvertedStatus(convertedStatus.MasterLabel);
        request.setOpportunityName('Converted Customer Opportunity');

        Test.startTest();
        Database.LeadConvertResult result = Database.convertLead(request);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Lead conversion should succeed.');
        Opportunity convertedOpportunity = [
            SELECT Opportunity_Opener__c, Opportunity_Closer__c
            FROM Opportunity
            WHERE Id = :result.getOpportunityId()
        ];
        System.assertEquals(opener.Id, convertedOpportunity.Opportunity_Opener__c);
        System.assertEquals(opener.ManagerId, convertedOpportunity.Opportunity_Closer__c);
    }

    private static String firstOpenLeadStatus() {
        return [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder
            LIMIT 1
        ].MasterLabel;
    }
}
