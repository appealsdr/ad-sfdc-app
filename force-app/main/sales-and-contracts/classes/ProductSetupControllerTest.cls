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
  static void updatesExistingPriceBookEntriesWithSparseRecords() {
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'AD-1942 Product'];
    Id standardPricebookId = Test.getStandardPricebookId();
    Pricebook2 customPricebook = [
      SELECT Id
      FROM Pricebook2
      WHERE Name = 'AD-1942 Custom Price Book'
    ];
    String paymentType = paymentType();
    insert new List<PricebookEntry>{
      new PricebookEntry(
        Pricebook2Id = standardPricebookId,
        Product2Id = product.Id,
        UnitPrice = 100,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = customPricebook.Id,
        Product2Id = product.Id,
        UnitPrice = 90,
        IsActive = true
      )
    };

    ProductSetupController.PricebookInput standardRow = new ProductSetupController.PricebookInput();
    standardRow.pricebookId = standardPricebookId;
    standardRow.selected = true;
    standardRow.unitPrice = 200;
    standardRow.deposit = 25;
    standardRow.paymentType = paymentType;
    ProductSetupController.PricebookInput customRow = new ProductSetupController.PricebookInput();
    customRow.pricebookId = customPricebook.Id;
    customRow.selected = false;

    Test.startTest();
    ProductSetupController.savePricebooks(
      product.Id,
      new List<ProductSetupController.PricebookInput>{ standardRow, customRow }
    );
    Test.stopTest();

    Map<Id, PricebookEntry> entriesByPricebook = new Map<Id, PricebookEntry>();
    for (PricebookEntry entry : [
      SELECT Pricebook2Id, UnitPrice, Deposit__c, Payment_type__c, IsActive
      FROM PricebookEntry
      WHERE Product2Id = :product.Id
    ]) {
      entriesByPricebook.put(entry.Pricebook2Id, entry);
    }
    System.assertEquals(
      200,
      entriesByPricebook.get(standardPricebookId).UnitPrice
    );
    System.assertEquals(
      25,
      entriesByPricebook.get(standardPricebookId).Deposit__c
    );
    System.assertEquals(
      paymentType,
      entriesByPricebook.get(standardPricebookId).Payment_type__c
    );
    System.assertEquals(
      false,
      entriesByPricebook.get(customPricebook.Id).IsActive
    );
  }

  @IsTest
  static void loadsActivePriceBooksWithoutExistingProductPrices() {
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'AD-1942 Product'];

    Test.startTest();
    ProductSetupController.SetupData result = ProductSetupController.getSetup(
      product.Id
    );
    Test.stopTest();

    System.assertEquals(2, result.pricebooks.size());
    for (ProductSetupController.PricebookRow row : result.pricebooks) {
      System.assertEquals(false, row.selected);
      System.assertEquals(false, row.isActive);
      System.assertEquals(null, row.pricebookEntryId);
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
    row.paymentType = paymentType();

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
  static void requiresPaymentTypeAndDepositAmount() {
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'AD-1942 Product'];
    ProductSetupController.PricebookInput row = new ProductSetupController.PricebookInput();
    row.pricebookId = Test.getStandardPricebookId();
    row.selected = true;
    row.unitPrice = 500;

    Boolean missingPaymentTypeRejected = false;
    try {
      ProductSetupController.savePricebooks(
        product.Id,
        new List<ProductSetupController.PricebookInput>{ row }
      );
    } catch (AuraHandledException expected) {
      missingPaymentTypeRejected = true;
    }
    System.assert(missingPaymentTypeRejected);

    row.paymentType = 'Deposit';
    Boolean missingDepositRejected = false;
    try {
      ProductSetupController.savePricebooks(
        product.Id,
        new List<ProductSetupController.PricebookInput>{ row }
      );
    } catch (AuraHandledException expected) {
      missingDepositRejected = true;
    }
    System.assert(missingDepositRejected);
  }

  @IsTest
  static void savesTemplateRequirements() {
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

    Required_File__c savedRequirement = [
      SELECT
        Name,
        Product__c,
        Document_Template__c,
        Short_Description__c,
        Accepted_Format__c,
        Instructions__c
      FROM Required_File__c
      WHERE Product__c = :product.Id AND Case__c = NULL
      LIMIT 1
    ];
    System.assertEquals(template.Name, savedRequirement.Name);
    System.assertEquals(product.Id, savedRequirement.Product__c);
    System.assertEquals(template.Id, savedRequirement.Document_Template__c);
    System.assertEquals(
      template.Short_Description__c,
      savedRequirement.Short_Description__c
    );
    System.assertEquals(
      template.Accepted_Format__c,
      savedRequirement.Accepted_Format__c
    );
    System.assertEquals(
      template.Instructions__c,
      savedRequirement.Instructions__c
    );
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
        FROM Required_File__c
        WHERE Product__c = :product.Id AND Case__c = NULL
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
