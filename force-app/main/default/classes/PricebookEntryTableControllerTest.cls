@IsTest
private class PricebookEntryTableControllerTest {
  @TestSetup
  static void setupData() {
    Product2 product = new Product2(
      Name = 'Appeal Service',
      ProductCode = 'SRV-001',
      IsActive = true
    );
    insert product;

    insert new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = 250,
      IsActive = true
    );
  }

  @IsTest
  static void returnsDefaultFieldsAndEntries() {
    Id pricebookId = Test.getStandardPricebookId();

    Test.startTest();
    PricebookEntryTableController.ViewModel result = PricebookEntryTableController.getEntries(
      pricebookId,
      null
    );
    Test.stopTest();

    Assert.isTrue(
      result.usingDefaultFields,
      'Blank configuration should use defaults.'
    );
    Assert.areEqual(
      5,
      result.fields.size(),
      'The default field list should be returned.'
    );
    Assert.areEqual(
      'Product2Id',
      result.fields[0].apiName,
      'Default field order must be stable.'
    );
    Assert.areEqual(
      'UnitPrice',
      result.fields[1].apiName,
      'Default field order must be stable.'
    );
    Assert.areEqual(
      1,
      result.rows.size(),
      'The price book entry should be returned.'
    );
    Assert.areEqual(250, result.rows[0].values.get('UnitPrice'));
    Assert.areEqual('Appeal Service', result.rows[0].values.get('Product2Id'));
    Assert.isTrue(result.canCreateEntries);
    Assert.isTrue(result.canUpdateEntries);
    Assert.isTrue(result.canDeleteEntries);
  }

  @IsTest
  static void invalidFieldSetFallsBackGracefully() {
    PricebookEntryTableController.ViewModel result = PricebookEntryTableController.getEntries(
      Test.getStandardPricebookId(),
      'Does_Not_Exist'
    );

    Assert.isTrue(result.usingDefaultFields);
    Assert.isTrue(result.warning.contains('was not found'));
    Assert.areEqual(5, result.fields.size());
  }

  @IsTest
  static void rejectsNonPricebookRecordId() {
    Account account = new Account(Name = 'Not a price book');
    insert account;

    Boolean exceptionThrown = false;
    try {
      PricebookEntryTableController.getEntries(account.Id, null);
    } catch (AuraHandledException expected) {
      exceptionThrown = true;
    }
    Assert.isTrue(exceptionThrown, 'Expected an AuraHandledException.');
  }

  @IsTest
  static void addsAvailableProductsToCustomPricebook() {
    Pricebook2 customPricebook = new Pricebook2(
      Name = 'Services',
      IsActive = true
    );
    insert customPricebook;
    Id productId = [SELECT Product2Id FROM PricebookEntry LIMIT 1].Product2Id;

    List<PricebookEntryTableController.ProductOption> options = PricebookEntryTableController.getAvailableProducts(
      customPricebook.Id
    );
    Assert.areEqual(1, options.size());
    Assert.areEqual(productId, options[0].productId);

    PricebookEntryTableController.addProducts(
      customPricebook.Id,
      new List<Id>{ productId }
    );

    PricebookEntry added = [
      SELECT UnitPrice, IsActive
      FROM PricebookEntry
      WHERE Pricebook2Id = :customPricebook.Id AND Product2Id = :productId
    ];
    Assert.areEqual(250, added.UnitPrice);
    Assert.isTrue(added.IsActive);
  }

  @IsTest
  static void bulkUpdatesEditablePricingFields() {
    PricebookEntry entry = [
      SELECT Id, Pricebook2Id
      FROM PricebookEntry
      LIMIT 1
    ];
    String paymentType;
    for (
      Schema.PicklistEntry option : PricebookEntry.Payment_type__c.getDescribe()
        .getPicklistValues()
    ) {
      if (option.isActive()) {
        paymentType = option.getValue();
        break;
      }
    }
    PricebookEntryTableController.EntryUpdate input = new PricebookEntryTableController.EntryUpdate();
    input.entryId = entry.Id;
    input.unitPrice = 300;
    input.active = false;
    input.deposit = 75;
    input.paymentType = paymentType;

    PricebookEntryTableController.saveEntries(
      entry.Pricebook2Id,
      new List<PricebookEntryTableController.EntryUpdate>{ input }
    );

    PricebookEntry updated = [
      SELECT UnitPrice, IsActive, Deposit__c, Payment_type__c
      FROM PricebookEntry
      WHERE Id = :entry.Id
    ];
    Assert.areEqual(300, updated.UnitPrice);
    Assert.isFalse(updated.IsActive);
    Assert.areEqual(75, updated.Deposit__c);
    Assert.areEqual(paymentType, updated.Payment_type__c);
  }

  @IsTest
  static void deletesEntryFromRequestedPricebook() {
    PricebookEntry entry = [
      SELECT Id, Pricebook2Id
      FROM PricebookEntry
      LIMIT 1
    ];

    PricebookEntryTableController.deleteEntry(entry.Pricebook2Id, entry.Id);

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PricebookEntry WHERE Id = :entry.Id],
      'The selected Price Book Entry should be deleted.'
    );
  }
}
