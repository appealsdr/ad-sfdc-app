@isTest
private class ContractLineItemPaymentServiceTest {
    @isTest
    static void createsTotalAndThreeLinePayments() {
        Account account = new Account(Name = 'Payment contract account');
        insert account;
        Id pricebookId = Test.getStandardPricebookId();
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Full service', IsActive = true),
            new Product2(Name = 'Deposit service A', IsActive = true),
            new Product2(Name = 'Deposit service B', IsActive = true)
        };
        insert products;
        List<PricebookEntry> entries = new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = products[0].Id,
                UnitPrice = 100, IsActive = true, Payment_type__c = 'Full Price'),
            new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = products[1].Id,
                UnitPrice = 100, IsActive = true, Payment_type__c = 'Deposit', Deposit__c = 100),
            new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = products[2].Id,
                UnitPrice = 150, IsActive = true, Payment_type__c = 'Deposit', Deposit__c = 50)
        };
        insert entries;
        ServiceContract contract = new ServiceContract(Name = 'Payment example',
            AccountId = account.Id, Pricebook2Id = pricebookId, StartDate = Date.today());
        insert contract;

        Test.startTest();
        insert new List<ContractLineItem>{
            new ContractLineItem(ServiceContractId = contract.Id, PricebookEntryId = entries[0].Id,
                Quantity = 3, UnitPrice = 100),
            new ContractLineItem(ServiceContractId = contract.Id, PricebookEntryId = entries[1].Id,
                Quantity = 2, UnitPrice = 100),
            new ContractLineItem(ServiceContractId = contract.Id, PricebookEntryId = entries[2].Id,
                Quantity = 1, UnitPrice = 150)
        };
        Test.stopTest();

        List<Payment__c> payments = [
            SELECT Amount__c, Contract_Line_Item__c, Payment_Type__c
            FROM Payment__c WHERE Service_Contract__c = :contract.Id
        ];
        System.assertEquals(4, payments.size());
        Map<Decimal, Integer> countsByAmount = new Map<Decimal, Integer>();
        for (Payment__c payment : payments) {
            countsByAmount.put(payment.Amount__c,
                (countsByAmount.containsKey(payment.Amount__c) ? countsByAmount.get(payment.Amount__c) : 0) + 1);
            System.assertEquals(payment.Payment_Type__c == 'First Payment',
                payment.Contract_Line_Item__c == null);
        }
        System.assertEquals(new Map<Decimal, Integer>{300.00 => 1, 200.00 => 1, 50.00 => 1, 550.00 => 1}, countsByAmount);
    }

    @isTest
    static void noPaymentsWithoutDeposit() {
        Account account = new Account(Name = 'No deposit account');
        insert account;
        Product2 product = new Product2(Name = 'Full payment product', IsActive = true);
        insert product;
        PricebookEntry entry = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id, UnitPrice = 100, IsActive = true, Payment_type__c = 'Full Price');
        insert entry;
        ServiceContract contract = new ServiceContract(Name = 'Full payment contract',
            AccountId = account.Id, Pricebook2Id = Test.getStandardPricebookId(), StartDate = Date.today());
        insert contract;
        insert new ContractLineItem(ServiceContractId = contract.Id, PricebookEntryId = entry.Id,
            Quantity = 1, UnitPrice = 100);
        System.assertEquals(0, [SELECT COUNT() FROM Payment__c WHERE Service_Contract__c = :contract.Id]);
    }

    @isTest
    static void usesStoredDepositsAndPreservesLegacyFallbackAndExplicitZero() {
        Account account = new Account(Name = 'Agreed deposit account');
        insert account;
        Id pricebookId = Test.getStandardPricebookId();
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Stored deposit', IsActive = true),
            new Product2(Name = 'Legacy deposit', IsActive = true),
            new Product2(Name = 'Waived deposit', IsActive = true)
        };
        insert products;
        List<PricebookEntry> entries = new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = products[0].Id,
                UnitPrice = 100, IsActive = true, Payment_type__c = 'Deposit', Deposit__c = 100),
            new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = products[1].Id,
                UnitPrice = 100, IsActive = true, Payment_type__c = 'Deposit', Deposit__c = 50),
            new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = products[2].Id,
                UnitPrice = 100, IsActive = true, Payment_type__c = 'Deposit', Deposit__c = 75)
        };
        insert entries;
        ServiceContract contract = new ServiceContract(Name = 'Agreed deposit contract',
            AccountId = account.Id, Pricebook2Id = pricebookId, StartDate = Date.today());
        insert contract;
        List<ContractLineItem> lines = new List<ContractLineItem>{
            new ContractLineItem(ServiceContractId = contract.Id, PricebookEntryId = entries[0].Id,
                Quantity = 2, UnitPrice = 100, Deposit__c = 25),
            new ContractLineItem(ServiceContractId = contract.Id, PricebookEntryId = entries[1].Id,
                Quantity = 3, UnitPrice = 100),
            new ContractLineItem(ServiceContractId = contract.Id, PricebookEntryId = entries[2].Id,
                Quantity = 4, UnitPrice = 100, Deposit__c = 0)
        };
        Test.startTest();
        insert lines;
        Test.stopTest();
        Map<Id, Decimal> amountByLine = new Map<Id, Decimal>();
        Decimal total;
        for (Payment__c payment : [
            SELECT Amount__c, Contract_Line_Item__c, Payment_Type__c
            FROM Payment__c WHERE Service_Contract__c = :contract.Id
        ]) {
            if (payment.Contract_Line_Item__c != null) {
                amountByLine.put(payment.Contract_Line_Item__c, payment.Amount__c);
            } else if (payment.Payment_Type__c == 'First Payment') {
                total = payment.Amount__c;
            }
        }
        System.assertEquals(3, amountByLine.size());
        System.assertEquals(50, amountByLine.get(lines[0].Id), 'Use the stored per-unit deposit instead of the catalogue deposit');
        System.assertEquals(150, amountByLine.get(lines[1].Id), 'Legacy null deposits still use the catalogue amount');
        System.assertEquals(0, amountByLine.get(lines[2].Id), 'Explicit zero must not fall back to the catalogue');
        System.assertEquals(200, total, 'The first payment uses deposit snapshots multiplied by quantity');
    }
}
