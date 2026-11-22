@IsTest
private class ProductRequiredFileServiceTest {
  @TestSetup
  static void setup() {
    insert new TriggerControl__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Case_Trigger_Enabled__c = true,
      Update_Total_Case__c = false,
      Validate_Case__c = false
    );
    Account account = new Account(Name = 'Required file account');
    insert account;
    Opportunity opp = new Opportunity(
      Name = 'Required file opp',
      AccountId = account.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
    insert opp;
    Id pricebookId = Test.getStandardPricebookId();
    List<Product2> products = new List<Product2>{
      new Product2(Name = 'Product with files', IsActive = true),
      new Product2(Name = 'Product without files', IsActive = true)
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
        Payment_type__c = 'Full Price'
      )
    };
    insert entries;
    ServiceContract contract = new ServiceContract(
      Name = 'Required file contract',
      AccountId = account.Id,
      Opportunity__c = opp.Id,
      Pricebook2Id = pricebookId,
      StartDate = Date.today()
    );
    insert contract;
    insert new List<ContractLineItem>{
      new ContractLineItem(
        ServiceContractId = contract.Id,
        PricebookEntryId = entries[0].Id,
        Quantity = 1,
        UnitPrice = 100
      ),
      new ContractLineItem(
        ServiceContractId = contract.Id,
        PricebookEntryId = entries[1].Id,
        Quantity = 1,
        UnitPrice = 100
      )
    };
    insert new List<Required_File__c>{
      new Required_File__c(
        Name = 'Template B',
        Product__c = products[0].Id,
        Short_Description__c = 'B desc',
        Accepted_Format__c = acceptedFormat(),
        Instructions__c = 'B instructions'
      ),
      new Required_File__c(
        Name = 'Template A',
        Product__c = products[0].Id,
        Short_Description__c = 'A desc'
      )
    };
  }

  private static String acceptedFormat() {
    for (
      Schema.PicklistEntry v : Required_File__c.Accepted_Format__c.getDescribe()
        .getPicklistValues()
    ) {
      if (v.isActive())
        return v.getValue();
    }
    return null;
  }

  private static ContractLineItem lineFor(String productName) {
    return [
      SELECT Id
      FROM ContractLineItem
      WHERE PricebookEntry.Product2.Name = :productName
      LIMIT 1
    ];
  }

  private static Case newCase(Id lineItemId) {
    return new Case(
      Subject = 'Onboarding',
      Status = 'New',
      Contract_Line_Item__c = lineItemId
    );
  }

  @IsTest
  static void clonesProductTemplatesOntoNewCaseWithoutProductReference() {
    Case c = newCase(lineFor('Product with files').Id);
    Test.startTest();
    insert c;
    Test.stopTest();

    List<Required_File__c> clones = [
      SELECT
        Name,
        Product__c,
        Source_Required_File__c,
        Source_Required_File__r.Name,
        Short_Description__c,
        Accepted_Format__c,
        Instructions__c
      FROM Required_File__c
      WHERE Case__c = :c.Id
      ORDER BY Name
    ];
    System.assertEquals(2, clones.size(), 'One clone per product template');
    for (Required_File__c clone : clones) {
      System.assertEquals(null, clone.Product__c, 'Clone has no product');
      System.assertNotEquals(null, clone.Source_Required_File__c);
      System.assertEquals(clone.Name, clone.Source_Required_File__r.Name);
    }
    System.assertEquals('B desc', clones[1].Short_Description__c);
    System.assertEquals(acceptedFormat(), clones[1].Accepted_Format__c);
    System.assertEquals('B instructions', clones[1].Instructions__c);
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Required_File__c
        WHERE Product__c != NULL AND Case__c = NULL
      ],
      'Templates are untouched'
    );
  }

  @IsTest
  static void bulkCasesEachGetOwnClones() {
    Id withFiles = lineFor('Product with files').Id;
    List<Case> cases = new List<Case>{
      newCase(withFiles),
      newCase(withFiles),
      newCase(lineFor('Product without files').Id)
    };
    Test.startTest();
    insert cases;
    Test.stopTest();

    System.assertEquals(2, [SELECT COUNT() FROM Required_File__c WHERE Case__c = :cases[0].Id]);
    System.assertEquals(2, [SELECT COUNT() FROM Required_File__c WHERE Case__c = :cases[1].Id]);
    System.assertEquals(0, [SELECT COUNT() FROM Required_File__c WHERE Case__c = :cases[2].Id]);
  }

  @IsTest
  static void inactiveTemplatesAreNotCloned() {
    update new Required_File__c(
      Id = [SELECT Id FROM Required_File__c WHERE Name = 'Template A'].Id,
      Active__c = false
    );
    Case c = newCase(lineFor('Product with files').Id);
    Test.startTest();
    insert c;
    Test.stopTest();
    List<Required_File__c> clones = [
      SELECT Name
      FROM Required_File__c
      WHERE Case__c = :c.Id
    ];
    System.assertEquals(1, clones.size());
    System.assertEquals('Template B', clones[0].Name);
  }

  @IsTest
  static void caseWithoutLineItemCreatesNothing() {
    Case c = new Case(Subject = 'No product', Status = 'New');
    Test.startTest();
    insert c;
    Test.stopTest();
    System.assertEquals(0, [SELECT COUNT() FROM Required_File__c WHERE Case__c = :c.Id]);
  }

  @IsTest
  static void nullAndEmptyInputAreIgnored() {
    ProductRequiredFileService.createForCases(null);
    ProductRequiredFileService.createForCases(new List<Case>());
    System.assertEquals(0, [SELECT COUNT() FROM Required_File__c WHERE Case__c != NULL]);
  }
}
