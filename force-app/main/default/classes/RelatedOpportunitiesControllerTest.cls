@IsTest
private class RelatedOpportunitiesControllerTest {

    // The Opportunity trigger may call out to the app webhook; keep tests offline.
    private class OkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        // Separate setup-object DML from the business-record fixtures below.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'CSM_Manager_Access' LIMIT 1].Id;
            Id userId = UserInfo.getUserId();
            if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId] == 0) {
                insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
            }
        }

        Account acc = new Account(Name = 'Upsell Test Co');
        insert acc;
        Account other = new Account(Name = 'Other Co');
        insert other;
        insert new List<Store__c>{
            new Store__c(Name = 'Main Store', Account__c = acc.Id),
            new Store__c(Name = 'Second Store', Account__c = acc.Id),
            new Store__c(Name = 'Foreign Store', Account__c = other.Id)
        };
        Store__c main = [SELECT Id FROM Store__c WHERE Name = 'Main Store'];
        insert new Case(AccountId = acc.Id, Subject = 'Upsell case', Status = 'New', Store__c = main.Id);
        insert new CSM_Call__c(Account__c = acc.Id, Call_Date__c = Date.today(), Call_Type__c = 'Monthly Retainer Call');

        Pricebook2 service = new Pricebook2(Name = 'Service', IsActive = true);
        insert service;
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'A-Z Claims', IsActive = true, Family = 'Services'),
            new Product2(Name = 'Chargeback', IsActive = true, Family = 'Services')
        };
        insert products;
        List<PricebookEntry> std = new List<PricebookEntry>();
        for (Product2 p : products) {
            std.add(new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = p.Id, UnitPrice = 100, IsActive = true));
        }
        insert std;
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = service.Id, Product2Id = products[0].Id, UnitPrice = 450, IsActive = true),
            new PricebookEntry(Pricebook2Id = service.Id, Product2Id = products[1].Id, UnitPrice = 300, IsActive = true)
        };
    }

    private static List<RelatedOpportunitiesController.LineInput> lines(Decimal qty) {
        List<RelatedOpportunitiesController.LineInput> result = new List<RelatedOpportunitiesController.LineInput>();
        for (PricebookEntry pbe : [SELECT Id FROM PricebookEntry WHERE Pricebook2.Name = 'Service' ORDER BY Product2.Name]) {
            RelatedOpportunitiesController.LineInput l = new RelatedOpportunitiesController.LineInput();
            l.pricebookEntryId = pbe.Id;
            l.quantity = qty;
            result.add(l);
        }
        return result;
    }

    @IsTest
    static void createsTechnicianUpsellFromCase() {
        Test.setMock(HttpCalloutMock.class, new OkMock());
        Case c = [SELECT Id, AccountId FROM Case LIMIT 1];

        Test.startTest();
        RelatedOpportunitiesController.SourceContext ctx = RelatedOpportunitiesController.getContext(c.Id, 'Service');
        Id oppId = RelatedOpportunitiesController.createOpportunity(c.Id, 'Service', '', ctx.defaultStoreId, 'Client asked for help', lines(2));
        Test.stopTest();

        Assert.areEqual('Technician Upsell', ctx.opportunityType);
        Assert.areEqual('Upsell Test Co', ctx.accountName);
        Assert.areEqual(2, ctx.stores.size(), 'Only the account\'s own stores are offered');
        Assert.areEqual([SELECT Id FROM Store__c WHERE Name = 'Main Store'].Id, ctx.defaultStoreId, 'Case store is preselected');

        Opportunity opp = [
            SELECT Name, AccountId, Case__c, CSM_Call__c, Type, StageName, CloseDate, Pricebook2.Name, ForecastCategoryName, Amount, Store__r.Name, Description,
                (SELECT Quantity, UnitPrice FROM OpportunityLineItems)
            FROM Opportunity WHERE Id = :oppId
        ];
        Assert.areEqual(c.Id, opp.Case__c);
        Assert.isNull(opp.CSM_Call__c);
        Assert.areEqual(c.AccountId, opp.AccountId);
        Assert.areEqual('Technician Upsell', opp.Type);
        Assert.areEqual('New', opp.StageName);
        Assert.areEqual(Date.today(), opp.CloseDate);
        Assert.areEqual('Service', opp.Pricebook2.Name);
        Assert.areEqual('Pipeline', opp.ForecastCategoryName);
        Assert.areEqual('Main Store', opp.Store__r.Name);
        Assert.areEqual('Client asked for help', opp.Description);
        Assert.areEqual(ctx.defaultOpportunityName, opp.Name);
        Assert.areEqual(2, opp.OpportunityLineItems.size());
        Assert.areEqual((450 + 300) * 2, opp.Amount);

        List<Opportunity> related = RelatedOpportunitiesController.getOpportunities(c.Id);
        Assert.areEqual(1, related.size());
    }

    @IsTest
    static void createsCsmUpsellFromCsmCall() {
        Test.setMock(HttpCalloutMock.class, new OkMock());
        CSM_Call__c call = [SELECT Id, Account__c FROM CSM_Call__c LIMIT 1];

        Test.startTest();
        Store__c second = [SELECT Id FROM Store__c WHERE Name = 'Second Store'];
        RelatedOpportunitiesController.SourceContext ctx = RelatedOpportunitiesController.getContext(call.Id, 'service');
        Id oppId = RelatedOpportunitiesController.createOpportunity(call.Id, 'service', 'My upsell', second.Id, 'Client asked for help', lines(1));
        Test.stopTest();

        Assert.isNull(ctx.defaultStoreId, 'CSM Call has no store to preselect');
        Assert.areEqual(2, ctx.stores.size());
        Opportunity opp = [SELECT Name, AccountId, CSM_Call__c, Case__c, Type, Store__c FROM Opportunity WHERE Id = :oppId];
        Assert.areEqual(second.Id, opp.Store__c);
        Assert.areEqual('My upsell', opp.Name);
        Assert.areEqual(call.Id, opp.CSM_Call__c);
        Assert.isNull(opp.Case__c);
        Assert.areEqual(call.Account__c, opp.AccountId);
        Assert.areEqual('CSM Upsell', opp.Type);
        Assert.areEqual(1, RelatedOpportunitiesController.getOpportunities(call.Id).size());
    }

    @IsTest
    static void storeOptionalWhenAccountHasNoStores() {
        Test.setMock(HttpCalloutMock.class, new OkMock());
        Account bare = new Account(Name = 'No Stores Co');
        insert bare;
        Case c = new Case(AccountId = bare.Id, Subject = 'No store', Status = 'New');
        insert c;

        Test.startTest();
        Id oppId = RelatedOpportunitiesController.createOpportunity(c.Id, 'Service', null, null, 'Client asked for help', lines(1));
        Test.stopTest();

        Assert.isNull([SELECT Store__c FROM Opportunity WHERE Id = :oppId].Store__c);
    }

    @IsTest
    static void listsProductsFromConfiguredPricebook() {
        List<RelatedOpportunitiesController.ProductOption> products = RelatedOpportunitiesController.getProducts('Service');
        Assert.areEqual(2, products.size());
        Assert.areEqual('A-Z Claims', products[0].productName);
        Assert.areEqual(450, products[0].unitPrice);
    }

    @IsTest
    static void rejectsBadInput() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Integer failures = 0;

        try {
            RelatedOpportunitiesController.createOpportunity(c.Id, 'Service', null, null, 'Client asked for help', new List<RelatedOpportunitiesController.LineInput>());
        } catch (AuraHandledException e) { failures++; }
        try {
            RelatedOpportunitiesController.createOpportunity(c.Id, 'Service', null, null, 'Client asked for help', lines(0));
        } catch (AuraHandledException e) { failures++; }
        try {
            Id main = [SELECT Id FROM Store__c WHERE Name = 'Main Store'].Id;
            RelatedOpportunitiesController.createOpportunity(c.Id, 'Service', null, main, '   ', lines(1)); // blank description
        } catch (AuraHandledException e) { failures++; }
        try {
            RelatedOpportunitiesController.createOpportunity(c.Id, 'Service', null, null, 'Client asked for help', lines(1)); // account has stores
        } catch (AuraHandledException e) { failures++; }
        try {
            Id foreign = [SELECT Id FROM Store__c WHERE Name = 'Foreign Store'].Id;
            RelatedOpportunitiesController.createOpportunity(c.Id, 'Service', null, foreign, 'Client asked for help', lines(1));
        } catch (AuraHandledException e) { failures++; }
        try {
            RelatedOpportunitiesController.getProducts('No Such Book');
        } catch (AuraHandledException e) { failures++; }
        try {
            RelatedOpportunitiesController.getOpportunities(acc.Id);
        } catch (AuraHandledException e) { failures++; }

        Assert.areEqual(7, failures, 'Each bad input should be rejected');
        Assert.areEqual(0, [SELECT COUNT() FROM Opportunity]);
    }
}