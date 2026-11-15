@isTest
private class ContractLineItemPaymentServiceTest {
  @isTest
  static void createsPaymentsFromEachContractLineConfiguration() {
    Account account = new Account(Name = 'Payment contract account');
    insert account;
    Opportunity opportunity = makeOpportunity(
      account.Id,
      'Configured payment opportunity'
    );
    Id pricebookId = Test.getStandardPricebookId();
    List<Product2> products = new List<Product2>{
      new Product2(Name = 'Full service', IsActive = true),
      new Product2(Name = 'Deposit service A', IsActive = true),
      new Product2(Name = 'Deposit service B', IsActive = true)
    };
    insert products;
    List<PricebookEntry> entries = new List<PricebookEntry>{
      new PricebookEntry(
        Pricebook2Id = pricebookId,
        Product2Id = products[0].Id,
        UnitPrice = 100,
        IsActive = true,
        Payment_type__c = 'Full Price'
      ),
      new PricebookEntry(
        Pricebook2Id = pricebookId,
        Product2Id = products[1].Id,
        UnitPrice = 100,
        IsActive = true,
        Payment_type__c = 'Deposit',
        Deposit__c = 100
      ),
      new PricebookEntry(
        Pricebook2Id = pricebookId,
        Product2Id = products[2].Id,
        UnitPrice = 150,
        IsActive = true,
        Payment_type__c = 'Deposit',
        Deposit__c = 50
      )
    };
    insert entries;
    ServiceContract contract = makeContract(
      account.Id,
      opportunity.Id,
      pricebookId
    );

    List<ContractLineItem> lines = new List<ContractLineItem>{
      new ContractLineItem(
        ServiceContractId = contract.Id,
        PricebookEntryId = entries[0].Id,
        Quantity = 3,
        UnitPrice = 100
      ),
      new ContractLineItem(
        ServiceContractId = contract.Id,
        PricebookEntryId = entries[1].Id,
        Quantity = 2,
        UnitPrice = 100
      ),
      new ContractLineItem(
        ServiceContractId = contract.Id,
        PricebookEntryId = entries[2].Id,
        Quantity = 1,
        UnitPrice = 150
      )
    };

    Test.startTest();
    insert lines;
    Test.stopTest();

    List<Payment__c> payments = [
      SELECT
        Amount__c,
        Contract_Line_Item__c,
        Opportunity__c,
        Payment_Type__c,
        Status__c,
        Order_Ref__c
      FROM Payment__c
      WHERE Service_Contract__c = :contract.Id
      ORDER BY Amount__c
    ];
    System.assertEquals(
      2,
      payments.size(),
      'Initial amounts are aggregated and balances remain product-specific'
    );
    Map<String, Decimal> amountByReference = new Map<String, Decimal>();
    Map<String, String> statusByReference = new Map<String, String>();
    for (Payment__c payment : payments) {
      System.assertEquals(
        opportunity.Id,
        payment.Opportunity__c,
        'Every payment retains the source Opportunity'
      );
      amountByReference.put(payment.Order_Ref__c, payment.Amount__c);
      statusByReference.put(payment.Order_Ref__c, payment.Status__c);
    }
    System.assertEquals(550, amountByReference.get(contract.Id + ':first'));
    System.assertEquals(100, amountByReference.get(lines[2].Id + ':balance'));
    System.assertEquals(
      'Request Payment',
      statusByReference.get(contract.Id + ':first')
    );
    System.assertEquals(
      'Not Active',
      statusByReference.get(lines[2].Id + ':balance')
    );
  }

  @isTest
  static void createsFullPaymentWithoutAnyDepositLines() {
    Account account = new Account(Name = 'No deposit account');
    insert account;
    Opportunity opportunity = makeOpportunity(
      account.Id,
      'Full payment opportunity'
    );
    Product2 product = new Product2(
      Name = 'Full payment product',
      IsActive = true
    );
    insert product;
    PricebookEntry entry = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = 100,
      IsActive = true,
      Payment_type__c = 'Full Price'
    );
    insert entry;
    ServiceContract contract = makeContract(
      account.Id,
      opportunity.Id,
      Test.getStandardPricebookId()
    );

    insert new ContractLineItem(
      ServiceContractId = contract.Id,
      PricebookEntryId = entry.Id,
      Quantity = 2,
      UnitPrice = 100
    );

    Payment__c payment = [
      SELECT
        Amount__c,
        Contract_Line_Item__c,
        Opportunity__c,
        Order_Ref__c,
        Payment_Type__c,
        Status__c
      FROM Payment__c
      WHERE Service_Contract__c = :contract.Id
    ];
    System.assertEquals(200, payment.Amount__c);
    System.assertEquals(opportunity.Id, payment.Opportunity__c);
    System.assertEquals(null, payment.Contract_Line_Item__c);
    System.assertEquals(contract.Id + ':first', payment.Order_Ref__c);
    System.assertEquals('First Payment', payment.Payment_Type__c);
    System.assertEquals('Request Payment', payment.Status__c);
  }

  @isTest
  static void discountsFallbackDepositAndDoesNotCreateDuplicates() {
    Account account = new Account(Name = 'Discounted deposit account');
    insert account;
    Opportunity opportunity = makeOpportunity(
      account.Id,
      'Discounted deposit opportunity'
    );
    Product2 product = new Product2(
      Name = 'Discounted deposit product',
      IsActive = true
    );
    insert product;
    PricebookEntry entry = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = 100,
      IsActive = true,
      Payment_type__c = 'Deposit',
      Deposit__c = 50
    );
    insert entry;
    ServiceContract contract = makeContract(
      account.Id,
      opportunity.Id,
      Test.getStandardPricebookId()
    );
    ContractLineItem line = new ContractLineItem(
      ServiceContractId = contract.Id,
      PricebookEntryId = entry.Id,
      Quantity = 2,
      UnitPrice = 100,
      Discount = 10
    );
    insert line;

    Test.startTest();
    ContractLineItemPaymentService.createInitialPayments(
      new List<ContractLineItem>{ line }
    );
    Test.stopTest();

    Map<String, Payment__c> paymentsByType = new Map<String, Payment__c>();
    for (Payment__c payment : [
      SELECT Amount__c, Payment_Type__c, Order_Ref__c
      FROM Payment__c
      WHERE Service_Contract__c = :contract.Id
    ]) {
      paymentsByType.put(payment.Payment_Type__c, payment);
    }
    System.assertEquals(
      2,
      paymentsByType.size(),
      'Order references make retries idempotent'
    );
    System.assertEquals(
      90,
      paymentsByType.get('First Payment').Amount__c,
      'Discounted deposits roll into the contract first payment'
    );
    System.assertEquals(
      90,
      paymentsByType.get('Balance').Amount__c,
      'Balance equals the negotiated line total less the deposit'
    );
  }

  @isTest
  static void aggregatesThreeDepositsAndCreatesTwoBalances() {
    Account account = new Account(Name = 'Three deposit account');
    insert account;
    Opportunity opportunity = makeOpportunity(
      account.Id,
      'Three deposit opportunity'
    );
    Id pricebookId = Test.getStandardPricebookId();
    List<Product2> products = new List<Product2>{
      new Product2(Name = 'A-Z Claims', IsActive = true),
      new Product2(Name = 'Account Ownership Transfer', IsActive = true),
      new Product2(Name = 'Ad Suspension', IsActive = true)
    };
    insert products;
    List<PricebookEntry> entries = new List<PricebookEntry>();
    for (Integer index = 0; index < products.size(); index++) {
      entries.add(
        new PricebookEntry(
          Pricebook2Id = pricebookId,
          Product2Id = products[index].Id,
          UnitPrice = index == 0 ? 450 : (index == 1 ? 3000 : 900),
          IsActive = true,
          Payment_type__c = 'Deposit',
          Deposit__c = index == 0 ? 150 : (index == 1 ? 3000 : 450)
        )
      );
    }
    insert entries;
    ServiceContract contract = makeContract(
      account.Id,
      opportunity.Id,
      pricebookId
    );
    List<ContractLineItem> lines = new List<ContractLineItem>{
      new ContractLineItem(
        ServiceContractId = contract.Id,
        PricebookEntryId = entries[0].Id,
        Quantity = 2,
        UnitPrice = 450,
        Discount = 15,
        Deposit__c = 127.50
      ),
      new ContractLineItem(
        ServiceContractId = contract.Id,
        PricebookEntryId = entries[1].Id,
        Quantity = 1,
        UnitPrice = 3000,
        Discount = 10,
        Deposit__c = 2700
      ),
      new ContractLineItem(
        ServiceContractId = contract.Id,
        PricebookEntryId = entries[2].Id,
        Quantity = 1,
        UnitPrice = 900,
        Discount = 15,
        Deposit__c = 382.50
      )
    };

    Test.startTest();
    insert lines;
    Test.stopTest();

    Map<String, Payment__c> paymentsByReference = new Map<String, Payment__c>();
    for (Payment__c payment : [
      SELECT
        Amount__c,
        Contract_Line_Item__c,
        Order_Ref__c,
        Payment_Type__c,
        Status__c
      FROM Payment__c
      WHERE Service_Contract__c = :contract.Id
    ]) {
      paymentsByReference.put(payment.Order_Ref__c, payment);
    }
    System.assertEquals(3, paymentsByReference.size());
    Payment__c firstPayment = paymentsByReference.get(contract.Id + ':first');
    System.assertEquals(3337.50, firstPayment.Amount__c);
    System.assertEquals('First Payment', firstPayment.Payment_Type__c);
    System.assertEquals('Request Payment', firstPayment.Status__c);
    System.assertEquals(null, firstPayment.Contract_Line_Item__c);
    System.assertEquals(
      510,
      paymentsByReference.get(lines[0].Id + ':balance').Amount__c
    );
    System.assertEquals(
      382.50,
      paymentsByReference.get(lines[2].Id + ':balance').Amount__c
    );
  }

  private static Opportunity makeOpportunity(Id accountId, String name) {
    Opportunity opportunity = new Opportunity(
      Name = name,
      AccountId = accountId,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunity;
    return opportunity;
  }

  private static ServiceContract makeContract(
    Id accountId,
    Id opportunityId,
    Id pricebookId
  ) {
    ServiceContract contract = new ServiceContract(
      Name = 'Payment example',
      AccountId = accountId,
      Opportunity__c = opportunityId,
      Pricebook2Id = pricebookId,
      StartDate = Date.today()
    );
    insert contract;
    return contract;
  }
}
