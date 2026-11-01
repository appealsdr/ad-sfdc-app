@IsTest
private class CSMCaseDashboardControllerTest {
    @TestSetup
    static void grantCsmAccess() {
        Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'CSM_Manager_Access' LIMIT 1].Id;
        Id userId = UserInfo.getUserId();
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId] == 0) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
        }
    }

    private static CSM_Call__c makeCall(Id accountId) {
        CSM_Call__c call = new CSM_Call__c(Account__c = accountId,
            Call_Date__c = Date.today(), Call_Type__c = 'Monthly Retainer Call');
        insert call;
        return call;
    }

    @IsTest static void groupsAccountAndStoreCasesWithoutDoubleCounting() {
        Account account = new Account(Name = 'Dashboard account');
        Account other = new Account(Name = 'Other account');
        insert new List<Account>{account, other};
        Store__c first = new Store__c(Name = 'First store', Account__c = account.Id);
        Store__c second = new Store__c(Name = 'Second store', Account__c = account.Id);
        Store__c emptyStore = new Store__c(Name = 'Empty store', Account__c = account.Id);
        Store__c unrelated = new Store__c(Name = 'Unrelated store', Account__c = other.Id);
        insert new List<Store__c>{first, second, emptyStore, unrelated};
        Opportunity opportunity = new Opportunity(Name = 'Dashboard contract fixture', AccountId = account.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(10));
        insert opportunity;
        insert new Contract__c(Opportunity__c = opportunity.Id, Status__c = 'Signed');
        CSM_Call__c call = makeCall(account.Id);
        Case recent = new Case(Subject = 'Recent', AccountId = account.Id, Store__c = first.Id, Status = 'New', Origin = 'Phone', Type = 'Problem', Category__c = 'Account');
        Case aging = new Case(Subject = 'Aging', AccountId = account.Id, Store__c = first.Id, Status = 'New', Origin = 'Phone', Type = 'Problem', Category__c = 'Account');
        Case delayed = new Case(Subject = 'Store only', Store__c = second.Id, Status = 'New', Origin = 'Phone');
        Case closed = new Case(Opportunity__c = opportunity.Id, Subject = 'Resolved', AccountId = account.Id, Store__c = first.Id, Status = 'Closed', Closed_Reason__c = 'Resolved - Tech', Origin = 'Phone', Type = 'Problem', Category__c = 'Account');
        Case unassigned = new Case(Subject = 'No store', AccountId = account.Id, Status = 'New', Origin = 'Phone');
        Case excluded = new Case(Subject = 'Unrelated', AccountId = other.Id, Store__c = unrelated.Id, Status = 'New', Origin = 'Phone');
        insert new List<Case>{recent, aging, delayed, closed, unassigned, excluded};
        // Case creation automation initializes status; close the fixture after insertion.
        closed.Status = 'Closed';
        closed.Closed_Reason__c = 'Resolved - Tech';
        update closed;
        Assert.isTrue([SELECT IsClosed FROM Case WHERE Id = :closed.Id].IsClosed);
        Test.setCreatedDate(aging.Id, System.now().addDays(-8));
        Test.setCreatedDate(delayed.Id, System.now().addDays(-15));
        Test.setCreatedDate(closed.Id, System.now().addDays(-30));
        Test.startTest();
        CSMCaseDashboardController.Dashboard result = CSMCaseDashboardController.getDashboard(call.Id);
        Assert.areEqual(4, CSMCaseDashboardController.getCases(call.Id, 'open', false, null, false, null, null, null).records.size());
        Assert.areEqual(closed.Id, CSMCaseDashboardController.getCases(call.Id, 'closed', false, null, false, null, null, null).records[0].Id);
        Assert.areEqual(2, CSMCaseDashboardController.getCases(call.Id, 'aging', false, null, false, null, null, null).records.size());
        Assert.areEqual(delayed.Id, CSMCaseDashboardController.getCases(call.Id, 'overdue', false, null, false, null, null, null).records[0].Id);
        Assert.areEqual(3, CSMCaseDashboardController.getCases(call.Id, 'all', true, first.Id, true, 'Problem', 'Account', null).records.size());
        Assert.areEqual(2, CSMCaseDashboardController.getCases(call.Id, 'open', true, first.Id, true, 'Problem', 'Account', null).records.size());
        Assert.areEqual(1, CSMCaseDashboardController.getCases(call.Id, 'closed', true, first.Id, true, 'Problem', 'Account', null).records.size());
        Assert.areEqual(unassigned.Id, CSMCaseDashboardController.getCases(call.Id, 'all', true, null, true, null, null, null).records[0].Id);
        Assert.areEqual(0, CSMCaseDashboardController.getCases(call.Id, 'all', true, unrelated.Id, false, null, null, null).records.size());
        CSMCaseDashboardController.CasePage allCases = CSMCaseDashboardController.getCases(call.Id, 'all', false, null, false, null, null, null);
        Assert.areEqual(5, allCases.records.size());
        Assert.isFalse(allCases.hasMore);
        Assert.areEqual(0, CSMCaseDashboardController.getCases(call.Id, 'all', false, null, false, null, null, allCases.nextCursor).records.size());
        Test.stopTest();
        Assert.areEqual(4, result.openCount);
        Assert.areEqual(1, result.closedCount);
        Assert.areEqual(2, result.agingCount, 'Closed cases must not count as aging');
        Assert.areEqual(1, result.overdueCount);
        Assert.areEqual(4, result.stores.size());
        Map<Id, CSMCaseDashboardController.StoreSummary> stores = new Map<Id, CSMCaseDashboardController.StoreSummary>();
        for (CSMCaseDashboardController.StoreSummary store : result.stores) stores.put(store.storeId, store);
        Assert.areEqual(2, stores.get(first.Id).openCount);
        Assert.areEqual(1, stores.get(first.Id).closedCount);
        Assert.areEqual(1, stores.get(first.Id).agingCount);
        Assert.areEqual(1, stores.get(first.Id).breakdowns.size());
        Assert.areEqual('Problem', stores.get(first.Id).breakdowns[0].caseType);
        Assert.areEqual('Account', stores.get(first.Id).breakdowns[0].category);
        Assert.areEqual(2, stores.get(first.Id).breakdowns[0].openCount);
        Assert.areEqual(1, stores.get(first.Id).breakdowns[0].closedCount);
        Assert.areEqual('Unspecified type', stores.get(second.Id).breakdowns[0].caseType);
        Assert.areEqual('Unspecified category', stores.get(second.Id).breakdowns[0].category);
        Assert.areEqual(0, stores.get(emptyStore.Id).openCount);
        Assert.areEqual('No store assigned', stores.get(null).storeName);
        Assert.isFalse(stores.containsKey(unrelated.Id));
    }

    @IsTest static void handlesEmptyAccountAndMissingId() {
        Account account = new Account(Name = 'No cases');
        insert account;
        CSM_Call__c call = makeCall(account.Id);
        CSMCaseDashboardController.Dashboard result = CSMCaseDashboardController.getDashboard(call.Id);
        Assert.areEqual(0, result.openCount);
        Assert.areEqual(0, result.closedCount);
        Assert.areEqual(0, result.stores.size());
        Assert.areEqual(0, CSMCaseDashboardController.getDashboard(null).openCount);
    }
    @IsTest static void paginatesWithoutDuplicates() {
        Account account = new Account(Name = 'Pagination');
        insert account;
        CSM_Call__c call = makeCall(account.Id);
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 101; i++) cases.add(new Case(AccountId = account.Id, Subject = 'Page ' + i, Status = 'New', Origin = 'Phone'));
        insert cases;
        Test.startTest();
        CSMCaseDashboardController.CasePage first = CSMCaseDashboardController.getCases(call.Id, 'all', false, null, false, null, null, null);
        CSMCaseDashboardController.CasePage second = CSMCaseDashboardController.getCases(call.Id, 'all', false, null, false, null, null, first.nextCursor);
        Test.stopTest();
        Assert.areEqual(100, first.records.size());
        Assert.isTrue(first.hasMore);
        Assert.areEqual(1, second.records.size());
        Assert.isFalse(second.hasMore);
        Set<Id> ids = new Map<Id, Case>(first.records).keySet();
        Assert.isFalse(ids.contains(second.records[0].Id));
    }

    @IsTest static void rejectsInvalidFilters() {
        try {
            CSMCaseDashboardController.getCases(null, 'invalid', false, null, false, null, null, null);
            Assert.fail('Invalid request must be rejected');
        } catch (AuraHandledException expected) {
            Assert.isNotNull(expected);
        }
    }

    @IsTest static void returnsRelatedContractsAndPurchasedProducts() {
        Account account = new Account(Name = 'Contract account');
        Account other = new Account(Name = 'Unrelated contract account');
        insert new List<Account>{account, other};
        Store__c store = new Store__c(Name = 'Contract store', Account__c = account.Id);
        insert store;
        Opportunity opportunity = new Opportunity(Name = 'Store purchase', AccountId = account.Id,
            Store__c = store.Id, StageName = 'Prospecting', CloseDate = Date.today());
        insert opportunity;
        Id pricebookId = Test.getStandardPricebookId();
        Product2 product = new Product2(Name = 'Purchased service', IsActive = true);
        insert product;
        PricebookEntry entry = new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = product.Id, UnitPrice = 100, IsActive = true);
        insert entry;
        ServiceContract direct = new ServiceContract(Name = 'Direct store contract', AccountId = account.Id,
            Store__c = store.Id, StartDate = Date.today(), Pricebook2Id = pricebookId);
        ServiceContract viaOpportunity = new ServiceContract(Name = 'Opportunity contract', AccountId = account.Id,
            Opportunity__c = opportunity.Id, StartDate = Date.today());
        ServiceContract accountOnly = new ServiceContract(Name = 'Account contract', AccountId = account.Id, StartDate = Date.today());
        ServiceContract excluded = new ServiceContract(Name = 'Other contract', AccountId = other.Id, StartDate = Date.today());
        insert new List<ServiceContract>{direct, viaOpportunity, accountOnly, excluded};
        ContractLineItem line = new ContractLineItem(ServiceContractId = direct.Id, PricebookEntryId = entry.Id,
            Quantity = 3, UnitPrice = 100);
        insert line;
        Case linkedCase = new Case(Subject = 'Purchased product case', AccountId = account.Id, Store__c = store.Id,
            Status = 'New', Origin = 'Phone', ServiceContractId = direct.Id, Contract_Line_Item__c = line.Id);
        insert linkedCase;
        CSM_Call__c call = makeCall(account.Id);
        Test.startTest();
        List<ServiceContract> contracts = CSMCaseDashboardController.getServiceContracts(call.Id);
        Case detail = CSMCaseDashboardController.getCases(call.Id, 'all', true, store.Id, false, null, null, null).records[0];
        Test.stopTest();
        Map<Id, ServiceContract> byId = new Map<Id, ServiceContract>(contracts);
        Assert.areEqual(3, contracts.size());
        Assert.isFalse(byId.containsKey(excluded.Id));
        Assert.areEqual(store.Id, byId.get(direct.Id).Store__c);
        Assert.areEqual(store.Id, byId.get(viaOpportunity.Id).Opportunity__r.Store__c);
        Assert.areEqual(null, byId.get(accountOnly.Id).Store__c);
        Assert.areEqual(3, byId.get(direct.Id).ContractLineItems[0].Quantity);
        Assert.areEqual('Purchased service', byId.get(direct.Id).ContractLineItems[0].PricebookEntry.Product2.Name);
        Assert.areEqual(direct.Id, detail.ServiceContractId);
        Assert.areEqual('Purchased service', detail.Contract_Line_Item__r.PricebookEntry.Product2.Name);
        Assert.areEqual(3, detail.Contract_Line_Item__r.Quantity);
        Assert.areEqual(0, CSMCaseDashboardController.getServiceContracts(null).size());
    }

}