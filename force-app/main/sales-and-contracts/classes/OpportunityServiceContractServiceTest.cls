@isTest
private class OpportunityServiceContractServiceTest {
  @TestSetup
  static void setupTestData() {
    List<Account> accList = TestDataFactory.createAccounts(1);
    List<Opportunity> oppList = TestDataFactory.createOpportunities(accList, 1);
    oppList[0].Opportunity_Opener__c = UserInfo.getUserId();
    oppList[0].Opportunity_Closer__c = UserInfo.getUserId();
    update oppList[0];
    List<Contact> contacts = TestDataFactory.createContacts(accList, 1);
    insert new OpportunityContactRole(
      OpportunityId = oppList[0].Id,
      ContactId = contacts[0].Id,
      IsPrimary = true
    );
    PricebookEntry pbe = TestDataFactory.createStandardPricebookEntry(100);
    TestDataFactory.createOpportunityLineItems(oppList[0].Id, pbe, 2);
    insert new Appeals_Dr_Setting__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      App_Url__c = 'https://app.example.com',
      Signup_Link_Secret__c = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    );
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
      SELECT Id, AccountId, Opportunity__c
      FROM ServiceContract
      WHERE Opportunity__c = :opp.Id
    ];
    System.assertEquals(
      1,
      contracts.size(),
      'One Service Contract should be created for the Closed Won Opportunity'
    );

    Account customer = [
      SELECT Signup_Link__c
      FROM Account
      WHERE Id = :contracts[0].AccountId
    ];
    System.assert(
      customer.Signup_Link__c.startsWith('https://app.example.com/register/link?t='),
      'The signup link must be stored before the Service Contract is created.'
    );

    List<ContractLineItem> scliList = [
      SELECT Id, Quantity, UnitPrice
      FROM ContractLineItem
      WHERE ServiceContractId = :contracts[0].Id
    ];
    System.assertEquals(
      2,
      scliList.size(),
      'Both Opportunity Line Items should be copied to the Service Contract'
    );
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
      SELECT COUNT()
      FROM ServiceContract
      WHERE Opportunity__c = :opp.Id
    ];
    System.assertEquals(
      1,
      contractCount,
      'Re-saving a Closed Won Opportunity must not create a duplicate Service Contract'
    );
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
      SELECT Id, AccountId, Opportunity__c
      FROM ServiceContract
      WHERE Opportunity__c = :opp.Id
    ];
    System.assertEquals(
      1,
      contracts.size(),
      'One Service Contract should be created for the Contract Sent Opportunity'
    );

    List<ContractLineItem> scliList = [
      SELECT Id, Quantity, UnitPrice
      FROM ContractLineItem
      WHERE ServiceContractId = :contracts[0].Id
    ];
    System.assertEquals(
      2,
      scliList.size(),
      'Both Opportunity Line Items should be copied to the Service Contract'
    );
  }

  @isTest
  static void contractPreservesNegotiatedPriceDiscountAndRecurringTerm() {
    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    OpportunityLineItem sourceLine = [
      SELECT Id, ListPrice, PricebookEntryId
      FROM OpportunityLineItem
      WHERE OpportunityId = :opp.Id
      LIMIT 1
    ];
    sourceLine.UnitPrice = 75;
    sourceLine.Quantity = 2;
    sourceLine.Discount = 10;
    sourceLine.Term_Months__c = 12;
    sourceLine.Deposit__c = 25;
    sourceLine.Description = 'Negotiated recurring product';
    update sourceLine;
    // A later catalogue change must not replace the agreed product deposit.
    update new PricebookEntry(
      Id = sourceLine.PricebookEntryId,
      Deposit__c = 75
    );

    Test.startTest();
    opp.StageName = 'Contract Sent';
    update opp;
    Test.stopTest();

    ContractLineItem contractLine;
    for (ContractLineItem candidate : [
      SELECT
        UnitPrice,
        ListPrice,
        Quantity,
        Discount,
        TotalPrice,
        Term_Months__c,
        Deposit__c,
        Description
      FROM ContractLineItem
      WHERE ServiceContract.Opportunity__c = :opp.Id
    ]) {
      if (candidate.Description == 'Negotiated recurring product') {
        contractLine = candidate;
        break;
      }
    }
    System.assertNotEquals(
      null,
      contractLine,
      'The negotiated product is copied to the contract'
    );
    System.assertEquals(
      sourceLine.ListPrice,
      contractLine.ListPrice,
      'The catalogue price remains unchanged'
    );
    System.assertEquals(
      75,
      contractLine.UnitPrice,
      'Copy the negotiated unit price to the contract'
    );
    System.assertEquals(2, contractLine.Quantity, 'Copy the selected quantity');
    System.assertEquals(
      10,
      contractLine.Discount,
      'Preserve the line discount separately from the unit price'
    );
    System.assertEquals(
      135,
      contractLine.TotalPrice,
      'Apply the discount once to the negotiated price'
    );
    System.assertEquals(
      12,
      contractLine.Term_Months__c,
      'Preserve the recurring term in months'
    );
    System.assertEquals(
      25,
      contractLine.Deposit__c,
      'Preserve the agreed per-unit deposit despite catalogue changes'
    );
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
    Contact contact = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1];
    insert new OpportunityContactRole(
      OpportunityId = oppNoLines.Id,
      ContactId = contact.Id,
      IsPrimary = true
    );

    Test.startTest();
    oppNoLines.StageName = 'Closed Won';
    update oppNoLines;
    Test.stopTest();

    Integer contractCount = [
      SELECT COUNT()
      FROM ServiceContract
      WHERE Opportunity__c = :oppNoLines.Id
    ];
    System.assertEquals(
      0,
      contractCount,
      'No Service Contract should be created when the Opportunity has no line items'
    );
    System.assertNotEquals(
      null,
      [SELECT Signup_Link__c FROM Account WHERE Id = :acc.Id].Signup_Link__c,
      'Closed Won must generate a signup link even when no contract is created.'
    );
  }
}
