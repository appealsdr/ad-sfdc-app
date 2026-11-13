@isTest
private class OpportunityTriggerHandlerTest {
  @TestSetup
  static void setupTestData() {
    // Create multiple test accounts using factory
    List<Account> accList = TestDataFactory.createAccounts(1);
    List<Case> Cases = TestDataFactory.createCases(accList, 1);
    List<User> users = TestDataFactory.createUsers(1);
    TestDataFactory.createCaseTeamMembers(Cases, users);
    List<Opportunity> OppList = TestDataFactory.createOpportunities(accList, 1);
  }

  @isTest
  private static void beforeInsertTest() {
    Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
    User usr = [SELECT Id FROM User LIMIT 1];

    List<OpportunityShare> sharesBefore = [
      SELECT Id
      FROM OpportunityShare
      WHERE OpportunityId = :opp.Id AND UserOrGroupId = :usr.Id
    ];
    System.assertEquals(true, opp != null);
  }
  @isTest
  private static void afterUpdateTest() {
    Opportunity opp = [SELECT Id, Name FROM Opportunity LIMIT 1];
    User usr = [SELECT Id FROM User LIMIT 1];
    Account newAcc = new Account(Name = 'Test Account');
    insert newAcc;

    System.assertEquals('Test Account', newAcc.Name);
    opp.AccountId = newAcc.Id;
    update opp;

    List<OpportunityShare> sharesAfter = [
      SELECT Id
      FROM OpportunityShare
      WHERE OpportunityId = :opp.Id AND UserOrGroupId = :usr.Id
    ];

    System.assertEquals(0, sharesAfter.Size());
  }

  @isTest
  private static void deleteTest() {
    Opportunity opp = [SELECT Id, Name FROM Opportunity LIMIT 1];
    delete opp;

    undelete opp;
  }

  // -----------------------------------------------------------------------
  // Contract Sent stage change — triggers webhook callout
  // -----------------------------------------------------------------------

  private class ContractSentMockHttp implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      System.assertEquals('POST', req.getMethod());
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setBody(
        '{"status": "success", "message": "contract_sent_processed"}'
      );
      res.setStatusCode(200);
      return res;
    }
  }

  @isTest
  private static void contractSentStageChangeFiresWebhookTest() {
    Test.setMock(HttpCalloutMock.class, new ContractSentMockHttp());

    insert new Appeals_WebhookApi__c(
      Name = 'Default',
      EndPoint_URL__c = 'https://test.example.com/salesforce/webhook/',
      Api_Key__c = 'TEST_KEY_123'
    );

    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    System.assertNotEquals(
      'Contract Sent',
      opp.StageName,
      'Test setup Opportunity should not start at Contract Sent stage'
    );
    addProduct(opp.Id);

    Test.startTest();
    opp.StageName = 'Contract Sent';
    update opp;
    Test.stopTest();

    List<Application_Log__c> logs = [
      SELECT Id, Body__c, Response__c
      FROM Application_Log__c
    ];
    System.assert(
      logs.size() > 0,
      'Contract Sent stage change should trigger webhook and create Application_Log__c'
    );
    System.assert(
      logs[0].Body__c.contains('Opportunity'),
      'Log body should contain Opportunity data'
    );
  }

  @isTest
  private static void migrationGuardSuppressesStageSideEffectsTest() {
    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    addProduct(opp.Id);
    Integer serviceContractsBefore = [
      SELECT COUNT()
      FROM ServiceContract
      WHERE Opportunity__c = :opp.Id
    ];

    Test.startTest();
    OpportunityTriggerHandler.skipWebhookFiring = true;
    opp.StageName = 'Contract Sent';
    update opp;
    OpportunityTriggerHandler.skipWebhookFiring = false;
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Application_Log__c],
      'Migration guard should suppress the outbound stage webhook'
    );
    System.assertEquals(
      serviceContractsBefore,
      [SELECT COUNT() FROM ServiceContract WHERE Opportunity__c = :opp.Id],
      'Migration guard should suppress ServiceContract creation'
    );
  }

  private static void addProduct(Id opportunityId) {
    PricebookEntry entry = TestDataFactory.createStandardPricebookEntry(100);
    TestDataFactory.createOpportunityLineItems(opportunityId, entry, 1);
    update new Opportunity(
      Id = opportunityId,
      Opportunity_Opener__c = UserInfo.getUserId(),
      Opportunity_Closer__c = UserInfo.getUserId()
    );
  }

  @isTest
  private static void contractSentRequiresOpenerAndCloser() {
    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    PricebookEntry entry = TestDataFactory.createStandardPricebookEntry(100);
    TestDataFactory.createOpportunityLineItems(opp.Id, entry, 1);
    opp.StageName = 'Contract Sent';

    Test.startTest();
    Database.SaveResult result = Database.update(opp, false);
    Test.stopTest();

    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0]
        .getMessage()
        .contains('Set both Opportunity Opener and Opportunity Closer')
    );
  }

  @isTest
  private static void contractSentWithoutPricebookIsRejected() {
    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    String previousStage = opp.StageName;
    opp.StageName = 'Contract Sent';

    Test.startTest();
    Database.SaveResult result = Database.update(opp, false);
    Test.stopTest();

    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0].getMessage().contains('Select a price book')
    );
    System.assertEquals('StageName', result.getErrors()[0].getFields()[0]);
    System.assertEquals(
      previousStage,
      [SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM ServiceContract WHERE Opportunity__c = :opp.Id]
    );
  }

  @isTest
  private static void contractSentWithoutProductsIsRejectedEvenWhenWebhookSkipped() {
    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    opp.Pricebook2Id = Test.getStandardPricebookId();
    update opp;
    opp.StageName = 'Contract Sent';

    Test.startTest();
    OpportunityTriggerHandler.skipWebhookFiring = true;
    Database.SaveResult result = Database.update(opp, false);
    OpportunityTriggerHandler.skipWebhookFiring = false;
    Test.stopTest();

    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0]
        .getMessage()
        .contains('Add at least one Opportunity product')
    );
  }

  @isTest
  private static void cannotInsertContractSentWithoutProducts() {
    Opportunity opp = new Opportunity(
      Name = 'Invalid contract',
      AccountId = [SELECT Id FROM Account LIMIT 1]
      .Id,
      StageName = 'Contract Sent',
      CloseDate = Date.today(),
      Pricebook2Id = Test.getStandardPricebookId()
    );

    Test.startTest();
    Database.SaveResult result = Database.insert(opp, false);
    Test.stopTest();

    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0]
        .getMessage()
        .contains('Add at least one Opportunity product')
    );
  }

  @isTest
  private static void contractReadinessValidationSupportsBulkUpdates() {
    Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
    PricebookEntry entry = TestDataFactory.createStandardPricebookEntry(100);
    List<Opportunity> opportunities = new List<Opportunity>();
    for (Integer i = 0; i < 200; i++) {
      opportunities.add(
        new Opportunity(
          Name = 'Bulk contract ' + i,
          AccountId = accountId,
          StageName = 'Prospecting',
          CloseDate = Date.today(),
          Pricebook2Id = Math.mod(i, 3) == 0 ? null : entry.Pricebook2Id,
          Opportunity_Opener__c = UserInfo.getUserId(),
          Opportunity_Closer__c = UserInfo.getUserId()
        )
      );
    }
    insert opportunities;
    List<OpportunityLineItem> products = new List<OpportunityLineItem>();
    for (Integer i = 0; i < opportunities.size(); i++) {
      if (Math.mod(i, 3) == 2) {
        products.add(
          new OpportunityLineItem(
            OpportunityId = opportunities[i].Id,
            PricebookEntryId = entry.Id,
            Quantity = 1,
            UnitPrice = 100
          )
        );
      }
      opportunities[i].StageName = 'Contract Sent';
    }
    insert products;

    Test.startTest();
    OpportunityTriggerHandler.skipWebhookFiring = true;
    Database.SaveResult[] results = Database.update(opportunities, false);
    OpportunityTriggerHandler.skipWebhookFiring = false;
    Test.stopTest();

    for (Integer i = 0; i < results.size(); i++) {
      System.assertEquals(
        Math.mod(i, 3) == 2,
        results[i].isSuccess(),
        'Unexpected readiness result at index ' + i
      );
    }
  }

  @isTest
  private static void unrelatedEditOfContractSentOpportunityRemainsAllowed() {
    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    addProduct(opp.Id);
    OpportunityTriggerHandler.skipWebhookFiring = true;
    opp.StageName = 'Contract Sent';
    update opp;
    delete [SELECT Id FROM OpportunityLineItem WHERE OpportunityId = :opp.Id];

    Test.startTest();
    opp.Description = 'An unrelated correction';
    update opp;
    Test.stopTest();

    OpportunityTriggerHandler.skipWebhookFiring = false;
    System.assertEquals(
      'An unrelated correction',
      [SELECT Description FROM Opportunity WHERE Id = :opp.Id].Description
    );
  }
}
