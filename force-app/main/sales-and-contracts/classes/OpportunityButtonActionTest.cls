@isTest
private class OpportunityButtonActionTest {
  private class MockHttp implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setBody('{"status": "success"}');
      res.setStatusCode(200);
      return res;
    }
  }

  @TestSetup
  static void setupTestData() {
    List<Account> accList = TestDataFactory.createAccounts(1);
    List<Opportunity> oppList = TestDataFactory.createOpportunities(accList, 1);
    oppList[0].Opportunity_Opener__c = UserInfo.getUserId();
    oppList[0].Opportunity_Closer__c = UserInfo.getUserId();
    update oppList[0];
  }

  @isTest
  private static void executeSetsStageAndFiresWebhook() {
    Test.setMock(HttpCalloutMock.class, new MockHttp());

    insert new Appeals_WebhookApi__c(
      Name = 'Default',
      EndPoint_URL__c = 'https://test.example.com/salesforce/webhook/',
      Api_Key__c = 'TEST_KEY_123'
    );

    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    System.assertNotEquals('Store Access', opp.StageName);

    OpportunityButtonAction.Request req = new OpportunityButtonAction.Request();
    req.opportunityId = opp.Id;
    req.targetStage = 'Store Access';
    req.webhookAction = 'Update';

    Test.startTest();
    OpportunityButtonAction.execute(
      new List<OpportunityButtonAction.Request>{ req }
    );
    Test.stopTest();

    Opportunity updated = [
      SELECT StageName
      FROM Opportunity
      WHERE Id = :opp.Id
    ];
    System.assertEquals(
      'Store Access',
      updated.StageName,
      'Stage should be updated to Store Access'
    );

    List<Application_Log__c> logs = [SELECT Id FROM Application_Log__c];
    System.assert(
      logs.size() > 0,
      'Button action should fire exactly one webhook via ODSA'
    );
  }

  @isTest
  private static void executeSkipsTriggerDuplicate() {
    Test.setMock(HttpCalloutMock.class, new MockHttp());

    insert new Appeals_WebhookApi__c(
      Name = 'Default',
      EndPoint_URL__c = 'https://test.example.com/salesforce/webhook/',
      Api_Key__c = 'TEST_KEY_123'
    );

    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];

    OpportunityButtonAction.Request req = new OpportunityButtonAction.Request();
    req.opportunityId = opp.Id;
    req.targetStage = 'Invoiced';
    req.webhookAction = 'Create';

    Test.startTest();
    OpportunityButtonAction.execute(
      new List<OpportunityButtonAction.Request>{ req }
    );
    Test.stopTest();

    Opportunity updated = [
      SELECT StageName
      FROM Opportunity
      WHERE Id = :opp.Id
    ];
    System.assertEquals('Invoiced', updated.StageName);

    List<Application_Log__c> logs = [SELECT Id FROM Application_Log__c];
    System.assertEquals(
      1,
      logs.size(),
      'Should have exactly 1 log entry (button webhook only, trigger skipped)'
    );
  }

  @isTest
  private static void executeRejectsContractSendWithoutPricebook() {
    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    String previousStage = opp.StageName;
    OpportunityButtonAction.Request req = contractSendRequest(opp.Id);

    Test.startTest();
    try {
      OpportunityButtonAction.execute(
        new List<OpportunityButtonAction.Request>{ req }
      );
      System.assert(false, 'Missing price book must block contract send');
    } catch (OpportunityButtonAction.ContractReadinessException ex) {
      System.assert(ex.getMessage().contains('Select a price book'));
    }
    Test.stopTest();

    System.assertEquals(
      previousStage,
      [SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
    );
    System.assertEquals(false, OpportunityTriggerHandler.skipWebhookFiring);
    System.assertEquals(0, [SELECT COUNT() FROM Application_Log__c]);
  }

  @isTest
  private static void executeRejectsContractSendWithoutProducts() {
    Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
    opp.Pricebook2Id = Test.getStandardPricebookId();
    update opp;

    Test.startTest();
    try {
      OpportunityButtonAction.execute(
        new List<OpportunityButtonAction.Request>{ contractSendRequest(opp.Id) }
      );
      System.assert(false, 'Missing products must block contract send');
    } catch (OpportunityButtonAction.ContractReadinessException ex) {
      System.assert(
        ex.getMessage().contains('Add at least one Opportunity product')
      );
    }
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Application_Log__c]);
  }

  @isTest
  private static void executeRejectsContractSendWithoutDealTeam() {
    Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
    PricebookEntry entry = TestDataFactory.createStandardPricebookEntry(100);
    TestDataFactory.createOpportunityLineItems(opp.Id, entry, 1);
    update new Opportunity(
      Id = opp.Id,
      Opportunity_Opener__c = null,
      Opportunity_Closer__c = null
    );

    Test.startTest();
    try {
      OpportunityButtonAction.execute(
        new List<OpportunityButtonAction.Request>{ contractSendRequest(opp.Id) }
      );
      System.assert(
        false,
        'Missing opener and closer must block contract send'
      );
    } catch (OpportunityButtonAction.ContractReadinessException ex) {
      System.assert(
        ex.getMessage()
          .contains('Set both Opportunity Opener and Opportunity Closer')
      );
    }
    Test.stopTest();
  }

  @isTest
  private static void executeRejectsResendAfterProductsRemoved() {
    Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
    PricebookEntry entry = TestDataFactory.createStandardPricebookEntry(100);
    TestDataFactory.createOpportunityLineItems(opp.Id, entry, 1);
    OpportunityTriggerHandler.skipWebhookFiring = true;
    opp.StageName = 'Contract Sent';
    update opp;
    OpportunityTriggerHandler.skipWebhookFiring = false;
    delete [SELECT Id FROM OpportunityLineItem WHERE OpportunityId = :opp.Id];

    Test.startTest();
    try {
      OpportunityButtonAction.execute(
        new List<OpportunityButtonAction.Request>{ contractSendRequest(opp.Id) }
      );
      System.assert(false, 'Resending a contract must check current products');
    } catch (OpportunityButtonAction.ContractReadinessException ex) {
      System.assert(
        ex.getMessage().contains('Add at least one Opportunity product')
      );
    }
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Application_Log__c]);
  }

  @isTest
  private static void executeAllowsContractSendWithProducts() {
    Test.setMock(HttpCalloutMock.class, new MockHttp());
    insert new Appeals_WebhookApi__c(
      Name = 'Default',
      EndPoint_URL__c = 'https://test.example.com/salesforce/webhook/',
      Api_Key__c = 'TEST_KEY_123'
    );
    Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
    PricebookEntry entry = TestDataFactory.createStandardPricebookEntry(100);
    TestDataFactory.createOpportunityLineItems(opp.Id, entry, 1);

    Test.startTest();
    OpportunityButtonAction.execute(
      new List<OpportunityButtonAction.Request>{ contractSendRequest(opp.Id) }
    );
    Test.stopTest();

    System.assertEquals(
      'Contract Sent',
      [SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
    );
    System.assertEquals(false, OpportunityTriggerHandler.skipWebhookFiring);
    System.assertEquals(1, [SELECT COUNT() FROM Application_Log__c]);
  }

  private static OpportunityButtonAction.Request contractSendRequest(
    Id opportunityId
  ) {
    OpportunityButtonAction.Request req = new OpportunityButtonAction.Request();
    req.opportunityId = opportunityId;
    req.targetStage = 'Contract Sent';
    req.webhookAction = 'Update';
    return req;
  }
}
