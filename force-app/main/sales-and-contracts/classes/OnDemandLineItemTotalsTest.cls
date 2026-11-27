@IsTest
private class OnDemandLineItemTotalsTest {
    @IsTest
    static void recalculatesBothParentsFromTheirOwnLines() {
        Id pricebookId = Test.getStandardPricebookId();
        Account account = new Account(Name = 'On-demand totals');
        insert account;
        Opportunity opportunity = new Opportunity(
            Name = 'On-demand totals', AccountId = account.Id, Pricebook2Id = pricebookId,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opportunity;
        ServiceContract contract = new ServiceContract(
            Name = 'On-demand totals', AccountId = account.Id, Pricebook2Id = pricebookId,
            StartDate = Date.today()
        );
        insert contract;
        Product2 product = new Product2(Name = 'Deposit service', IsActive = true);
        Product2 otherProduct = new Product2(Name = 'Non-deposit service', IsActive = true);
        insert new List<Product2>{ product, otherProduct };
        PricebookEntry depositEntry = new PricebookEntry(
            Product2Id = product.Id, Pricebook2Id = pricebookId, UnitPrice = 100, IsActive = true
        );
        PricebookEntry otherEntry = new PricebookEntry(
            Product2Id = otherProduct.Id, Pricebook2Id = pricebookId, UnitPrice = 75, IsActive = true
        );
        insert new List<PricebookEntry>{ depositEntry, otherEntry };
        ContractLineItem depositContractLine = new ContractLineItem(
            ServiceContractId = contract.Id, PricebookEntryId = depositEntry.Id, UnitPrice = 100,
            Quantity = 2, Discount = 10, Deposit__c = 30
        );
        OpportunityLineItem depositOpportunityLine = new OpportunityLineItem(
            OpportunityId = opportunity.Id, PricebookEntryId = depositEntry.Id, UnitPrice = 100,
            Quantity = 2, Discount = 10, Deposit__c = 30
        );

        Test.startTest();
        insert new List<ContractLineItem>{
            depositContractLine,
            new ContractLineItem(
                ServiceContractId = contract.Id, PricebookEntryId = otherEntry.Id, UnitPrice = 75, Quantity = 1
            )
        };
        insert new List<OpportunityLineItem>{
            depositOpportunityLine,
            new OpportunityLineItem(
                OpportunityId = opportunity.Id, PricebookEntryId = otherEntry.Id, UnitPrice = 75, Quantity = 2
            )
        };
        assertTotals(contract.Id, opportunity.Id, 54, 201, 276);
        depositContractLine.Deposit__c = 0;
        depositOpportunityLine.Deposit__c = 0;
        update depositContractLine;
        update depositOpportunityLine;
        assertTotals(contract.Id, opportunity.Id, 0, 255, 330);
        delete depositContractLine;
        delete depositOpportunityLine;
        assertTotals(contract.Id, opportunity.Id, 0, 75, 150);
        Test.stopTest();
    }

    private static void assertTotals(
        Id contractId, Id opportunityId, Decimal deposit, Decimal contractBalance, Decimal opportunityBalance
    ) {
        ServiceContract contract = [
            SELECT Total_Deposit_Payment__c, Total_Balance__c FROM ServiceContract WHERE Id = :contractId
        ];
        Opportunity opportunity = [
            SELECT Total_Deposit_Payment__c, Total_Balance__c FROM Opportunity WHERE Id = :opportunityId
        ];
        Assert.areEqual(deposit, contract.Total_Deposit_Payment__c);
        Assert.areEqual(deposit, opportunity.Total_Deposit_Payment__c);
        Assert.areEqual(contractBalance, contract.Total_Balance__c);
        Assert.areEqual(opportunityBalance, opportunity.Total_Balance__c);
    }
}
