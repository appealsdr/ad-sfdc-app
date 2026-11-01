@isTest
private class OpportunityServiceContractServiceTest {

    @TestSetup
    static void setupTestData() {
        List<Account> accList = TestDataFactory.createAccounts(1);
        List<Opportunity> oppList = TestDataFactory.createOpportunities(accList, 1);
        PricebookEntry pbe = TestDataFactory.createStandardPricebookEntry(100);
        TestDataFactory.createOpportunityLineItems(oppList[0].Id, pbe, 2);
    }

    // Closed Won with line items -> Service Contract + Service Contract Line Items created
    @isTest
    static void closedWonCreatesServiceContractWithLineItems() {
        Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        List<ServiceContract> contracts = [
            SELECT Id, AccountId, Opportunity__c FROM ServiceContract
            WHERE Opportunity__c = :opp.Id
        ];
        System.assertEquals(1, contracts.size(), 'One Service Contract should be created for the Closed Won Opportunity');

        List<ContractLineItem> scliList = [
            SELECT Id, Quantity, UnitPrice FROM ContractLineItem
            WHERE ServiceContractId = :contracts[0].Id
        ];
        System.assertEquals(2, scliList.size(), 'Both Opportunity Line Items should be copied to the Service Contract');
    }

    // Re-saving an already Closed Won Opportunity should not create a second contract
    @isTest
    static void noDuplicateContractOnResave() {
        Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];

        opp.StageName = 'Closed Won';
        update opp;

        Test.startTest();
        opp.Description = 'Touch to re-fire the after-update trigger';
        update opp;
        Test.stopTest();

        Integer contractCount = [
            SELECT COUNT() FROM ServiceContract WHERE Opportunity__c = :opp.Id
        ];
        System.assertEquals(1, contractCount, 'Re-saving a Closed Won Opportunity must not create a duplicate Service Contract');
    }

    // Contract Sent with line items -> Service Contract + Service Contract Line Items created
    @isTest
    static void contractSendCreatesServiceContractWithLineItems() {
        Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];

        Test.startTest();
        opp.StageName = 'Contract Sent';
        update opp;
        Test.stopTest();

        List<ServiceContract> contracts = [
            SELECT Id, AccountId, Opportunity__c FROM ServiceContract
            WHERE Opportunity__c = :opp.Id
        ];
        System.assertEquals(1, contracts.size(), 'One Service Contract should be created for the Contract Sent Opportunity');

        List<ContractLineItem> scliList = [
            SELECT Id, Quantity, UnitPrice FROM ContractLineItem
            WHERE ServiceContractId = :contracts[0].Id
        ];
        System.assertEquals(2, scliList.size(), 'Both Opportunity Line Items should be copied to the Service Contract');
    }

    // Closed Won with no line items -> no Service Contract created
    @isTest
    static void closedWonWithoutLineItemsCreatesNothing() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity oppNoLines = new Opportunity(
            Name = 'No Lines Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(15)
        );
        insert oppNoLines;

        Test.startTest();
        oppNoLines.StageName = 'Closed Won';
        update oppNoLines;
        Test.stopTest();

        Integer contractCount = [
            SELECT COUNT() FROM ServiceContract WHERE Opportunity__c = :oppNoLines.Id
        ];
        System.assertEquals(0, contractCount, 'No Service Contract should be created when the Opportunity has no line items');
    }
}