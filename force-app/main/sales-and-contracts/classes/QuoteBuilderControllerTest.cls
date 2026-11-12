@IsTest
private class QuoteBuilderControllerTest {
  @TestSetup
  static void setup() {
    Id standardPricebookId = Test.getStandardPricebookId();
    Pricebook2 services = new Pricebook2(
      Name = 'QB Test Services',
      IsActive = true
    );
    insert services;
    Product2 first = new Product2(
      Name = 'Listing reinstatement',
      Family = 'Appeals',
      IsActive = true
    );
    Product2 second = new Product2(
      Name = 'Account protection',
      Family = 'Protection',
      IsActive = true
    );
    insert new List<Product2>{ first, second };
    insert new List<PricebookEntry>{
      new PricebookEntry(
        Pricebook2Id = standardPricebookId,
        Product2Id = first.Id,
        UnitPrice = 500,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = standardPricebookId,
        Product2Id = second.Id,
        UnitPrice = 1000,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = services.Id,
        Product2Id = first.Id,
        UnitPrice = 500,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = services.Id,
        Product2Id = second.Id,
        UnitPrice = 1000,
        IsActive = true
      )
    };
    Account account = new Account(Name = 'QB Client');
    insert account;
    Contact contact = new Contact(
      FirstName = 'Quote',
      LastName = 'Recipient',
      Email = 'quote.recipient@example.com',
      AccountId = account.Id
    );
    insert contact;
    insert new List<Opportunity>{
      new Opportunity(
        Name = 'QB With Pricebook',
        AccountId = account.Id,
        StageName = 'Meeting Booked',
        CloseDate = Date.today().addDays(30),
        Pricebook2Id = services.Id
      ),
      new Opportunity(
        Name = 'QB No Pricebook',
        AccountId = account.Id,
        StageName = 'Meeting Booked',
        CloseDate = Date.today().addDays(30)
      )
    };
    Opportunity priced = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'QB With Pricebook'
    ];
    insert new OpportunityContactRole(
      OpportunityId = priced.Id,
      ContactId = contact.Id,
      Role = 'Decision Maker',
      IsPrimary = true
    );
  }

  private static Opportunity opportunity(String name) {
    return [
      SELECT Id, Pricebook2Id, SyncedQuoteId
      FROM Opportunity
      WHERE Name = :name
    ];
  }

  private static Map<String, Id> entries(Id pricebookId) {
    Map<String, Id> result = new Map<String, Id>();
    for (PricebookEntry entry : [
      SELECT Id, Product2.Name
      FROM PricebookEntry
      WHERE Pricebook2Id = :pricebookId
    ]) {
      result.put(entry.Product2.Name, entry.Id);
    }
    return result;
  }

  private static QuoteBuilderController.LineInput line(
    Id entryId,
    Decimal quantity,
    Decimal discount
  ) {
    QuoteBuilderController.LineInput input = new QuoteBuilderController.LineInput();
    input.pricebookEntryId = entryId;
    input.quantity = quantity;
    input.discountPct = discount;
    input.description = 'Client-facing scope';
    return input;
  }

  private static QuoteBuilderController.QuoteInfo createQuote() {
    Opportunity opp = opportunity('QB With Pricebook');
    Map<String, Id> pricebookEntries = entries(opp.Pricebook2Id);
    return QuoteBuilderController.saveQuote(
      opp.Id,
      null,
      Date.today().addDays(14),
      'Initial proposal',
      new List<QuoteBuilderController.LineInput>{
        line(pricebookEntries.get('Listing reinstatement'), 2, 10),
        line(pricebookEntries.get('Account protection'), 1, 0)
      }
    );
  }

  @IsTest
  static void contextStartsWithQuoteListAndCatalogue() {
    Opportunity opp = opportunity('QB With Pricebook');
    QuoteBuilderController.Context context = QuoteBuilderController.getContext(
      opp.Id
    );
    Assert.areEqual('QB Test Services', context.pricebookName);
    Assert.areEqual(2, context.catalog.size());
    Assert.areEqual(0, context.quotes.size());
    Assert.isNull(context.syncedQuoteId);
  }

  @IsTest
  static void userCanChoosePricebookBeforeCreatingQuote() {
    Opportunity opp = opportunity('QB No Pricebook');
    QuoteBuilderController.Context context = QuoteBuilderController.getContext(
      opp.Id
    );
    Assert.isNull(context.pricebookId);
    Id servicesId = [SELECT Id FROM Pricebook2 WHERE Name = 'QB Test Services']
    .Id;
    context = QuoteBuilderController.setPricebook(opp.Id, servicesId);
    Assert.areEqual(servicesId, context.pricebookId);
    Assert.areEqual(2, context.catalog.size());
  }

  @IsTest
  static void quoteLinesStaySeparateFromOpportunityProducts() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    Assert.areEqual(2, quote.lines.size());
    Assert.areEqual(1900, quote.totalPrice);
    Assert.areEqual('Draft', quote.status);
    Assert.areEqual('quote.recipient@example.com', quote.recipientEmail);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
    );

    QuoteBuilderController.Context context = QuoteBuilderController.getContext(
      opp.Id
    );
    Assert.areEqual(1, context.quotes.size());
    Assert.areEqual(2, context.quotes[0].lines.size());
  }

  @IsTest
  static void editingQuoteReplacesOnlyItsLines() {
    QuoteBuilderController.QuoteInfo created = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    Map<String, Id> pricebookEntries = entries(opp.Pricebook2Id);
    QuoteBuilderController.QuoteInfo updated = QuoteBuilderController.saveQuote(
      opp.Id,
      created.quoteId,
      Date.today().addDays(30),
      'Revised proposal',
      new List<QuoteBuilderController.LineInput>{
        line(pricebookEntries.get('Account protection'), 3, 5)
      }
    );
    Assert.areEqual(created.quoteId, updated.quoteId);
    Assert.areEqual(1, updated.lines.size());
    Assert.areEqual(2850, updated.totalPrice);
    Assert.areEqual('Revised proposal', updated.notes);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
    );
  }

  @IsTest
  static void discountLimitIsEnforcedAndOverrideIsSupported() {
    Opportunity opp = opportunity('QB With Pricebook');
    Id entryId = entries(opp.Pricebook2Id).get('Listing reinstatement');
    QuoteBuilderController.overrideForTest = false;
    try {
      QuoteBuilderController.saveQuote(
        opp.Id,
        null,
        null,
        null,
        new List<QuoteBuilderController.LineInput>{ line(entryId, 1, 20) }
      );
      Assert.fail('Expected discount validation');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true);
    }
    QuoteBuilderController.overrideForTest = true;
    QuoteBuilderController.QuoteInfo quote = QuoteBuilderController.saveQuote(
      opp.Id,
      null,
      null,
      null,
      new List<QuoteBuilderController.LineInput>{ line(entryId, 1, 20) }
    );
    Assert.areEqual(20, quote.lines[0].discountPct);
  }

  @IsTest
  static void nativeSyncCopiesSelectedQuoteToOpportunity() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    Test.startTest();
    QuoteBuilderController.Context context = QuoteBuilderController.syncQuoteToOpportunity(
      opp.Id,
      quote.quoteId
    );
    Test.stopTest();
    Opportunity refreshed = opportunity('QB With Pricebook');
    Assert.areEqual(quote.quoteId, refreshed.SyncedQuoteId);
    Assert.areEqual(quote.quoteId, context.syncedQuoteId);
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
    );
    Assert.isTrue(context.quotes[0].isSynced);
  }

  @IsTest
  static void pdfCanBeGeneratedAndListed() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Id pdfId = QuoteBuilderController.generatePdf(quote.quoteId);
    Assert.isNotNull(pdfId);
    Opportunity opp = opportunity('QB With Pricebook');
    QuoteBuilderController.Context context = QuoteBuilderController.getContext(
      opp.Id
    );
    Assert.areEqual(pdfId, context.quotes[0].pdfId);
  }

  @IsTest
  static void sendQuoteEmailsPdfAndMarksPresented() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    QuoteBuilderController.EmailDraft draft = QuoteBuilderController.renderEmailDraft(
      quote.quoteId,
      null
    );
    Assert.areEqual('QB With Pricebook – Proposal v1', draft.subject);
    Assert.isTrue(draft.htmlBody.contains('Appeals Doctor'));
    Test.startTest();
    QuoteBuilderController.QuoteInfo sent = QuoteBuilderController.sendQuote(
      quote.quoteId,
      'end.user@example.com',
      'manager@example.com; legal@example.com',
      null,
      null,
      'Custom quote subject',
      '<p>Custom quote email body.</p>'
    );
    Test.stopTest();
    Assert.areEqual('Presented', sent.status);
    Assert.isNotNull(sent.pdfId);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM QuoteDocument WHERE QuoteId = :quote.quoteId]
    );
    Task activity = [
      SELECT WhatId, Subject, Description, Status
      FROM Task
      WHERE WhatId = :opp.Id
      LIMIT 1
    ];
    Assert.areEqual(opp.Id, activity.WhatId);
    Assert.areEqual('Completed', activity.Status);
    Assert.isTrue(activity.Subject.startsWith('Email:'));
    Assert.isTrue(activity.Description.contains('end.user@example.com'));
    Assert.isTrue(activity.Description.contains('manager@example.com'));
  }

  @IsTest
  static void invalidInputsAndCrossOpportunityQuoteAreRejected() {
    Opportunity opp = opportunity('QB With Pricebook');
    Map<String, Id> pricebookEntries = entries(opp.Pricebook2Id);
    List<List<QuoteBuilderController.LineInput>> invalidLines = new List<List<QuoteBuilderController.LineInput>>{
      new List<QuoteBuilderController.LineInput>(),
      new List<QuoteBuilderController.LineInput>{
        line(pricebookEntries.get('Listing reinstatement'), 0, 0)
      },
      new List<QuoteBuilderController.LineInput>{
        line(pricebookEntries.get('Listing reinstatement'), 1, -1)
      },
      new List<QuoteBuilderController.LineInput>{ line(null, 1, 0) }
    };
    Integer failures = 0;
    for (List<QuoteBuilderController.LineInput> invalid : invalidLines) {
      try {
        QuoteBuilderController.saveQuote(opp.Id, null, null, null, invalid);
      } catch (AuraHandledException expected) {
        failures++;
      }
    }
    Assert.areEqual(invalidLines.size(), failures);

    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity other = opportunity('QB No Pricebook');
    try {
      QuoteBuilderController.syncQuoteToOpportunity(other.Id, quote.quoteId);
      Assert.fail('Expected cross-Opportunity quote validation');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true);
    }
  }

  @IsTest
  static void nonOpportunityRecordIsRejected() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    try {
      QuoteBuilderController.getContext(account.Id);
      Assert.fail('Expected record type validation');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true);
    }
  }
}
