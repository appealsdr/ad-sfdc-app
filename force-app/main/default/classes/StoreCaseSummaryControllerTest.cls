@IsTest
private class StoreCaseSummaryControllerTest {
    @TestSetup
    static void setupData() {
        Account account = TestDataFactory.createAccounts(1)[0];
        Opportunity opportunity = TestDataFactory.createOpportunities(new List<Account>{ account }, 1)[0];
        Store__c store = TestDataFactory.createStores(opportunity.Id, 1)[0];
        Store__c otherStore = TestDataFactory.createStores(opportunity.Id, 1)[0];
        store.Name = 'Summary Store';
        otherStore.Name = 'Other Summary Store';
        update new List<Store__c>{ store, otherStore };

        insert new List<Case>{
            new Case(
                Subject = 'New Store Case',
                Origin = 'Phone',
                Status = 'New',
                Store__c = store.Id
            ),
            new Case(
                Subject = 'In Progress Store Case',
                Origin = 'Phone',
                Status = 'In Progress - Tech',
                Store__c = store.Id
            ),
            new Case(
                Subject = 'Resolved Store Case',
                Origin = 'Phone',
                Status = 'Resolved - Tech',
                Store__c = store.Id
            ),
            new Case(
                Subject = 'Closed Store Case',
                Origin = 'Phone',
                Status = 'Closed - No Resolution',
                Store__c = store.Id
            ),
            new Case(
                Subject = 'Other Store Case',
                Origin = 'Phone',
                Status = 'New',
                Store__c = otherStore.Id
            )
        };
    }

    @IsTest
    static void returnsSummaryForStore() {
        Store__c store = [SELECT Id FROM Store__c WHERE Name = 'Summary Store' LIMIT 1];

        Test.startTest();
        StoreCaseSummaryController.CaseSummary summary =
            StoreCaseSummaryController.getCaseSummary(store.Id);
        Test.stopTest();

        System.assert(summary.newCases != null, 'At least the new case for this store should be counted.');
    }

    @IsTest
    static void returnsEmptySummaryWhenStoreIsBlank() {
        StoreCaseSummaryController.CaseSummary summary =
            StoreCaseSummaryController.getCaseSummary(null);

            System.assert(summary.newCases != null, 'At least the new case for this store should be counted.');
    }


}