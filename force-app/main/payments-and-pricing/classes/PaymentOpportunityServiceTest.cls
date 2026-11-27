@isTest
private class PaymentOpportunityServiceTest {
  private class ContractFixture {
    Account account;
    Store__c store;
    Opportunity opportunity;
    ServiceContract contract;
    ContractLineItem line;
  }

  private static ContractFixture makeContractFixture(String pricebookName) {
    ContractFixture fixture = new ContractFixture();
    fixture.account = new Account(Name = pricebookName + ' payment account');
    insert fixture.account;
    fixture.store = new Store__c(
      Name = pricebookName + ' payment store',
      Account__c = fixture.account.Id
    );
    insert fixture.store;
    fixture.opportunity = new Opportunity(
      Name = pricebookName + ' payment opportunity',
      AccountId = fixture.account.Id,
      Store__c = fixture.store.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today()
    );
    insert fixture.opportunity;

    Pricebook2 pricebook = new Pricebook2(
      Name = pricebookName,
      IsActive = true
    );
    insert pricebook;
    Product2 product = new Product2(
      Name = pricebookName + ' case product',
      IsActive = true,
      Case_Type__c = 'A-Z Claims'
    );
    insert product;
    insert new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = 100,
      IsActive = true
    );
    PricebookEntry entry = new PricebookEntry(
      Pricebook2Id = pricebook.Id,
      Product2Id = product.Id,
      UnitPrice = 100,
      IsActive = true
    );
    insert entry;
    fixture.contract = new ServiceContract(
      Name = pricebookName + ' service contract',
      AccountId = fixture.account.Id,
      Opportunity__c = fixture.opportunity.Id,
      Pricebook2Id = pricebook.Id,
      StartDate = Date.today()
    );
    insert fixture.contract;
    fixture.line = new ContractLineItem(
      ServiceContractId = fixture.contract.Id,
      PricebookEntryId = entry.Id,
      Quantity = 1,
      UnitPrice = 100
    );
    insert fixture.line;
    return fixture;
  }

  @isTest
  static void derivesOpportunityAndClosesItWhenPaymentBecomesPaid() {
    Account account = new Account(Name = 'Paid opportunity account');
    insert account;
    Opportunity opportunity = new Opportunity(
      Name = 'Payment lifecycle opportunity',
      AccountId = account.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(15)
    );
    insert opportunity;
    ServiceContract contract = new ServiceContract(
      Name = 'Payment lifecycle contract',
      AccountId = account.Id,
      Opportunity__c = opportunity.Id,
      StartDate = Date.today()
    );
    insert contract;

    Payment__c payment = new Payment__c(
      Service_Contract__c = contract.Id,
      Amount__c = 125,
      Status__c = 'Pending',
      Payment_Type__c = 'Deposit'
    );
    insert payment;
    payment = [
      SELECT Opportunity__c, Status__c
      FROM Payment__c
      WHERE Id = :payment.Id
    ];
    System.assertEquals(
      opportunity.Id,
      payment.Opportunity__c,
      'The Service Contract supplies the source Opportunity automatically'
    );
    System.assertEquals(
      'Prospecting',
      [SELECT StageName FROM Opportunity WHERE Id = :opportunity.Id].StageName,
      'Pending payments do not close the Opportunity'
    );

    Test.startTest();
    payment.Status__c = 'Paid';
    update payment;
    Test.stopTest();

    System.assertEquals(
      'Closed Won',
      [SELECT StageName FROM Opportunity WHERE Id = :opportunity.Id].StageName,
      'Receiving payment marks the related Opportunity Closed Won'
    );
  }

  @isTest
  static void paidInsertClosesOpportunityWithoutOverwritingExplicitLookup() {
    Account account = new Account(Name = 'Immediate payment account');
    insert account;
    List<Opportunity> opportunities = new List<Opportunity>{
      new Opportunity(
        Name = 'Contract opportunity',
        AccountId = account.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today()
      ),
      new Opportunity(
        Name = 'Explicit payment opportunity',
        AccountId = account.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today()
      )
    };
    insert opportunities;
    ServiceContract contract = new ServiceContract(
      Name = 'Immediate payment contract',
      AccountId = account.Id,
      Opportunity__c = opportunities[0].Id,
      StartDate = Date.today()
    );
    insert contract;

    Test.startTest();
    Payment__c payment = new Payment__c(
      Service_Contract__c = contract.Id,
      Opportunity__c = opportunities[1].Id,
      Amount__c = 50,
      Status__c = 'Paid',
      Payment_Type__c = 'Full'
    );
    insert payment;
    Test.stopTest();

    payment = [SELECT Opportunity__c FROM Payment__c WHERE Id = :payment.Id];
    System.assertEquals(
      opportunities[1].Id,
      payment.Opportunity__c,
      'An explicit Opportunity link is preserved'
    );
    Map<Id, Opportunity> saved = new Map<Id, Opportunity>(
      [SELECT StageName FROM Opportunity WHERE Id IN :opportunities]
    );
    System.assertEquals(
      'Prospecting',
      saved.get(opportunities[0].Id).StageName
    );
    System.assertEquals('Closed Won', saved.get(opportunities[1].Id).StageName);
  }

  @isTest
  static void paidPaymentsUpdateContractAndFirstPaymentCreatesCases() {
    ContractFixture fixture = makeContractFixture('Services');

    Payment__c firstPayment = new Payment__c(
      Service_Contract__c = fixture.contract.Id,
      Amount__c = 40,
      Status__c = 'Paid'
    );
    Test.startTest();
    insert firstPayment;
    insert new Payment__c(
      Service_Contract__c = fixture.contract.Id,
      Amount__c = 60,
      Status__c = 'Paid'
    );
    firstPayment.Status__c = 'Pending';
    update firstPayment;
    Test.stopTest();

    System.assertEquals(
      60,
      [
        SELECT Paid_Amount__c
        FROM ServiceContract
        WHERE Id = :fixture.contract.Id
      ]
      .Paid_Amount__c,
      'Only payments currently marked Paid contribute to the contract total'
    );
    List<Case> createdCases = [
      SELECT
        AccountId,
        Store__c,
        Opportunity__c,
        ServiceContractId,
        Contract_Line_Item__c,
        Case_Type__c
      FROM Case
      WHERE ServiceContractId = :fixture.contract.Id
    ];
    System.assertEquals(1, createdCases.size(), 'Create each case only once');
    Case createdCase = createdCases[0];
    System.assertEquals(fixture.account.Id, createdCase.AccountId);
    System.assertEquals(fixture.store.Id, createdCase.Store__c);
    System.assertEquals(fixture.opportunity.Id, createdCase.Opportunity__c);
    System.assertEquals(fixture.line.Id, createdCase.Contract_Line_Item__c);
    System.assertEquals('A-Z Claims', createdCase.Case_Type__c);
  }

  @isTest
  static void whiteGlovePaymentUpdatesPaidAmountWithoutCreatingCases() {
    ContractFixture fixture = makeContractFixture('White Glove');

    Test.startTest();
    insert new Payment__c(
      Service_Contract__c = fixture.contract.Id,
      Amount__c = 75,
      Status__c = 'Paid'
    );
    Test.stopTest();

    System.assertEquals(
      75,
      [
        SELECT Paid_Amount__c
        FROM ServiceContract
        WHERE Id = :fixture.contract.Id
      ]
      .Paid_Amount__c
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Case WHERE ServiceContractId = :fixture.contract.Id],
      'White Glove contracts must not create cases from payments'
    );
  }

  @isTest
  static void paymentFromUserWithoutOpportunityAccessStillCreatesCases() {
    ContractFixture fixture = makeContractFixture('Services');
    Payment__c payment = new Payment__c(
      Service_Contract__c = fixture.contract.Id,
      Amount__c = 40,
      Status__c = 'Pending',
      Payment_Type__c = 'Deposit'
    );
    insert payment;

    User restricted;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      String unique = 'payment.access.' + System.currentTimeMillis();
      restricted = new User(
        ProfileId = [
          SELECT Id
          FROM Profile
          WHERE Name = 'Minimum Access - Salesforce'
        ]
        .Id,
        LastName = 'Restricted',
        Alias = 'restrict',
        Email = unique + '@example.com',
        Username = unique + '@example.com',
        TimeZoneSidKey = 'America/New_York',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      );
      insert restricted;
    }

    Test.startTest();
    System.runAs(restricted) {
      payment.Status__c = 'Paid';
      update payment;
    }
    Test.stopTest();

    Case createdCase = [
      SELECT Opportunity__c, Store__c
      FROM Case
      WHERE ServiceContractId = :fixture.contract.Id
    ];
    System.assertEquals(fixture.opportunity.Id, createdCase.Opportunity__c);
    System.assertEquals(fixture.store.Id, createdCase.Store__c);
    System.assertEquals(
      'Closed Won',
      [SELECT StageName FROM Opportunity WHERE Id = :fixture.opportunity.Id]
      .StageName
    );
  }

  @isTest
  static void triggerLogsAndRethrowsServiceFailure() {
    ApplicationErrorLogger.publishedEvents.clear();
    PaymentOpportunityService.forceFailure = true;
    Boolean failed = false;
    Test.startTest();
    try {
      insert new Payment__c(
        Amount__c = 10,
        Status__c = 'Pending',
        Payment_Type__c = 'Deposit'
      );
    } catch (DmlException ex) {
      failed = true;
    } finally {
      PaymentOpportunityService.forceFailure = false;
    }
    Test.stopTest();

    System.assert(failed, 'The original trigger exception must be rethrown');
    System.assertEquals(1, ApplicationErrorLogger.publishedEvents.size());
  }
}
