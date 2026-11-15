@IsTest
private class ProductSetupControllerTest {
  @TestSetup
  static void setupData() {
    update new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
    insert new TriggerControl__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Case_Trigger_Enabled__c = true,
      Validate_Case__c = false,
      Update_Total_Case__c = false
    );
    insert new Product2(Name = 'AD-1942 Product', IsActive = true);
    insert new Pricebook2(Name = 'AD-1942 Custom Price Book', IsActive = true);
    insert new Document_Template__c(
      Name = 'AD-1942 Invoice',
      Object_Api_Name__c = 'Case',
      Active__c = true,
      Short_Description__c = 'Customer invoice',
      Accepted_Format__c = acceptedFormat(),
      Instructions__c = 'Upload the latest invoice.'
    );
  }

  @IsTest
  static void savesStandardAndCustomPriceBooks() {
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'AD-1942 Product'];
    Id standardPricebookId = Test.getStandardPricebookId();
    Pricebook2 customPricebook = [
      SELECT Id
      FROM Pricebook2
      WHERE Name = 'AD-1942 Custom Price Book'
    ];
    String paymentType = paymentType();

    List<ProductSetupController.PricebookInput> rows = new List<ProductSetupController.PricebookInput>();
    for (
      Id pricebookId : new List<Id>{ standardPricebookId, customPricebook.Id }
    ) {
      ProductSetupController.PricebookInput row = new ProductSetupController.PricebookInput();
      row.pricebookId = pricebookId;
      row.selected = true;
      row.unitPrice = pricebookId == standardPricebookId ? 500 : 450;
      row.deposit = 100;
      row.paymentType = paymentType;
      rows.add(row);
    }

    Test.startTest();
    ProductSetupController.SetupData result = ProductSetupController.savePricebooks(
      product.Id,
      rows
    );
    Test.stopTest();

    List<PricebookEntry> entries = [
      SELECT Pricebook2Id, UnitPrice, Deposit__c, Payment_type__c, IsActive
      FROM PricebookEntry
      WHERE Product2Id = :product.Id
    ];
    System.assertEquals(2, entries.size());
    System.assertEquals(2, result.pricebooks.size());
    for (PricebookEntry entry : entries) {
      System.assert(entry.IsActive);
      System.assertEquals(100, entry.Deposit__c);
      System.assertEquals(paymentType, entry.Payment_type__c);
    }
  }

  @IsTest
  static void requiresStandardPriceBeforeCustomPriceBook() {
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'AD-1942 Product'];
    Pricebook2 customPricebook = [
      SELECT Id
      FROM Pricebook2
      WHERE Name = 'AD-1942 Custom Price Book'
    ];
    ProductSetupController.PricebookInput row = new ProductSetupController.PricebookInput();
    row.pricebookId = customPricebook.Id;
    row.selected = true;
    row.unitPrice = 450;

    Boolean threw = false;
    Test.startTest();
    try {
      ProductSetupController.savePricebooks(
        product.Id,
        new List<ProductSetupController.PricebookInput>{ row }
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();
    System.assert(
      threw,
      'Custom pricing must require a Standard Price Book entry.'
    );
  }

  @IsTest
  static void savesTemplateRequirementsAndCreatesCaseChecklist() {
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'AD-1942 Product'];
    Document_Template__c template = [
      SELECT Id, Name, Short_Description__c, Accepted_Format__c, Instructions__c
      FROM Document_Template__c
      WHERE Name = 'AD-1942 Invoice'
    ];
    ProductSetupController.RequirementInput requirement = new ProductSetupController.RequirementInput();
    requirement.templateId = template.Id;
    requirement.active = true;

    ProductSetupController.SetupData result = ProductSetupController.saveRequirements(
      product.Id,
      new List<ProductSetupController.RequirementInput>{ requirement }
    );
    System.assertEquals(1, result.requirements.size());
    System.assertEquals(template.Name, result.requirements[0].name);

    Id standardPricebookId = Test.getStandardPricebookId();
    PricebookEntry entry = new PricebookEntry(
      Product2Id = product.Id,
      Pricebook2Id = standardPricebookId,
      UnitPrice = 500,
      IsActive = true,
      Payment_type__c = paymentType()
    );
    insert entry;
    Account account = new Account(Name = 'AD-1942 Account');
    insert account;
    ServiceContract contract = new ServiceContract(
      Name = 'AD-1942 Contract',
      AccountId = account.Id,
      Pricebook2Id = standardPricebookId,
      StartDate = Date.today()
    );
    insert contract;
    ContractLineItem lineItem = new ContractLineItem(
      ServiceContractId = contract.Id,
      PricebookEntryId = entry.Id,
      Quantity = 1,
      UnitPrice = 500
    );
    insert lineItem;

    Case caseRecord = new Case(
      Subject = 'AD-1942 onboarding',
      Status = 'New',
      Origin = 'Phone',
      Contract_Line_Item__c = lineItem.Id
    );
    Test.startTest();
    insert caseRecord;
    Test.stopTest();

    Required_File__c requiredFile = [
      SELECT
        Name,
        Case__c,
        Document_Template__c,
        Short_Description__c,
        Accepted_Format__c,
        Instructions__c
      FROM Required_File__c
      WHERE Case__c = :caseRecord.Id
    ];
    System.assertEquals(template.Name, requiredFile.Name);
    System.assertEquals(template.Id, requiredFile.Document_Template__c);
    System.assertEquals(
      template.Short_Description__c,
      requiredFile.Short_Description__c
    );
    System.assertEquals(
      template.Accepted_Format__c,
      requiredFile.Accepted_Format__c
    );
    System.assertEquals(template.Instructions__c, requiredFile.Instructions__c);
  }

  @IsTest
  static void savesManualRequirementAndRemovesOmittedRows() {
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'AD-1942 Product'];
    ProductSetupController.RequirementInput row = new ProductSetupController.RequirementInput();
    row.name = 'Manual proof';
    row.shortDescription = 'Manual upload';
    row.acceptedFormat = acceptedFormat();
    row.instructions = 'Upload proof.';
    row.active = true;

    ProductSetupController.SetupData saved = ProductSetupController.saveRequirements(
      product.Id,
      new List<ProductSetupController.RequirementInput>{ row }
    );
    System.assertEquals(1, saved.requirements.size());

    Test.startTest();
    ProductSetupController.SetupData cleared = ProductSetupController.saveRequirements(
      product.Id,
      new List<ProductSetupController.RequirementInput>()
    );
    Test.stopTest();
    System.assertEquals(0, cleared.requirements.size());
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Product_Document_Requirement__c
        WHERE Product__c = :product.Id
      ]
    );
  }

  private static String acceptedFormat() {
    for (
      Schema.PicklistEntry value : Required_File__c.Accepted_Format__c.getDescribe()
        .getPicklistValues()
    ) {
      if (value.isActive())
        return value.getValue();
    }
    return null;
  }

  private static String paymentType() {
    String firstActive;
    for (
      Schema.PicklistEntry value : PricebookEntry.Payment_type__c.getDescribe()
        .getPicklistValues()
    ) {
      if (!value.isActive())
        continue;
      if (firstActive == null)
        firstActive = value.getValue();
      if (value.getValue() == 'Full Price')
        return value.getValue();
    }
    return firstActive;
  }
}
