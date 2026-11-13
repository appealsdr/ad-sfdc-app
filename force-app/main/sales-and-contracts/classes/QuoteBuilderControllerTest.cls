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
    Contact accountContact = new Contact(
      FirstName = 'Account',
      LastName = 'Buyer',
      Email = 'account.buyer@example.com',
      Title = 'Head of Operations',
      AccountId = account.Id
    );
    insert new List<Contact>{ contact, accountContact };
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
    Assert.areEqual(2, context.recipientContacts.size());
    Assert.isTrue(
      new Set<String>{
          context.recipientContacts[0].email,
          context.recipientContacts[1].email
        }
        .contains('account.buyer@example.com')
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
    refreshed = [
      SELECT SyncedQuoteId, Description
      FROM Opportunity
      WHERE Id = :opp.Id
    ];
    Assert.isTrue(refreshed.Description.startsWith('Selected services:'));
    Assert.isTrue(refreshed.Description.contains('Listing reinstatement'));
    Assert.isTrue(refreshed.Description.contains('Qty 2'));
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
      null,
      'account.buyer@example.com'
    );
    Assert.areEqual('QB With Pricebook – Proposal v1', draft.subject);
    Assert.isTrue(draft.htmlBody.contains('Appeals Doctor'));
    Test.startTest();
    QuoteBuilderController.QuoteInfo sent = QuoteBuilderController.sendQuote(
      quote.quoteId,
      'end.user@example.com; finance@example.com',
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
    Assert.isTrue(activity.Description.contains('finance@example.com'));
    Assert.isTrue(activity.Description.contains('manager@example.com'));
    Opportunity refreshed = [
      SELECT Proposal_Sent_DateTime__c, Description
      FROM Opportunity
      WHERE Id = :opp.Id
    ];
    Assert.isNotNull(refreshed.Proposal_Sent_DateTime__c);
    Assert.isTrue(refreshed.Description.startsWith('Selected services:'));
    Assert.isTrue(refreshed.Description.contains('Listing reinstatement'));
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

  @IsTest
  static void negotiatedPricesKeepCataloguePriceAndDiscount() {
    Opportunity opp = opportunity('QB With Pricebook');
    Id entryId = entries(opp.Pricebook2Id).get('Listing reinstatement');
    QuoteBuilderController.overrideForTest = true;
    QuoteBuilderController.LineInput input = line(entryId, 2, 10);
    input.unitPrice = 450;
    QuoteBuilderController.QuoteInfo quote = QuoteBuilderController.saveQuote(
      opp.Id,
      null,
      null,
      null,
      new List<QuoteBuilderController.LineInput>{ input },
      null
    );
    Assert.areEqual(450, quote.lines[0].unitPrice);
    Assert.areEqual(500, quote.lines[0].listPrice);
    Assert.areEqual(10, quote.lines[0].discountPct);
    Assert.areEqual(810, quote.totalPrice);
    Assert.areEqual(
      500,
      [SELECT UnitPrice FROM PricebookEntry WHERE Id = :entryId].UnitPrice
    );
    QuoteBuilderController.syncQuoteToOpportunity(opp.Id, quote.quoteId);
    OpportunityLineItem synced = [
      SELECT UnitPrice, Discount, TotalPrice
      FROM OpportunityLineItem
      WHERE OpportunityId = :opp.Id
    ];
    Assert.areEqual(450, synced.UnitPrice);
    Assert.areEqual(10, synced.Discount);
    Assert.areEqual(810, synced.TotalPrice);
  }

  @IsTest
  static void manualPriceReductionsDoNotRequireDiscountApproval() {
    Opportunity opp = opportunity('QB With Pricebook');
    Id entryId = entries(opp.Pricebook2Id).get('Listing reinstatement');
    QuoteBuilderController.overrideForTest = false;
    List<QuoteBuilderController.LineInput> invalid = new List<QuoteBuilderController.LineInput>();
    QuoteBuilderController.LineInput negative = line(entryId, 1, 0);
    negative.unitPrice = -1;
    invalid.add(negative);
    QuoteBuilderController.LineInput excessiveDiscount = line(entryId, 1, 20);
    excessiveDiscount.unitPrice = 300;
    invalid.add(excessiveDiscount);
    for (QuoteBuilderController.LineInput input : invalid) {
      try {
        QuoteBuilderController.saveQuote(
          opp.Id,
          null,
          null,
          null,
          new List<QuoteBuilderController.LineInput>{ input },
          null
        );
        Assert.fail('Expected negative price or explicit discount validation.');
      } catch (AuraHandledException expected) {
        Assert.areEqual(
          0,
          [SELECT COUNT() FROM Quote WHERE OpportunityId = :opp.Id]
        );
      }
    }
    for (Decimal discount : new List<Decimal>{ 0, 10, 15 }) {
      QuoteBuilderController.LineInput reduced = line(entryId, 1, discount);
      reduced.unitPrice = 300;
      QuoteBuilderController.QuoteInfo quote = QuoteBuilderController.saveQuote(
        opp.Id,
        null,
        null,
        null,
        new List<QuoteBuilderController.LineInput>{ reduced },
        null
      );
      Assert.areEqual(300, quote.lines[0].unitPrice);
      Assert.areEqual(500, quote.lines[0].listPrice);
      Assert.areEqual(300 * (1 - discount / 100), quote.totalPrice);
    }
  }

  @IsTest
  static void recurringTermsAreRequiredAndValidatedOnServer() {
    Opportunity opp = opportunity('QB With Pricebook');
    Id entryId = entries(opp.Pricebook2Id).get('Listing reinstatement');
    update new PricebookEntry(Id = entryId, Payment_type__c = 'Recurring');
    QuoteBuilderController.LineInput input = line(entryId, 1, 0);
    List<Integer> invalidTerms = new List<Integer>{ null, 0, -1, 1201 };
    for (Integer invalid : invalidTerms) {
      try {
        QuoteBuilderController.saveQuote(
          opp.Id,
          null,
          null,
          null,
          new List<QuoteBuilderController.LineInput>{ input },
          invalid
        );
        Assert.fail('Expected a required, bounded quote term.');
      } catch (AuraHandledException expected) {
        Assert.areEqual(
          0,
          [SELECT COUNT() FROM Quote WHERE OpportunityId = :opp.Id]
        );
      }
    }
    input.termMonths = 1201;
    try {
      QuoteBuilderController.saveQuote(
        opp.Id,
        null,
        null,
        null,
        new List<QuoteBuilderController.LineInput>{ input },
        12
      );
      Assert.fail('Expected recurring line term validation.');
    } catch (AuraHandledException expected) {
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Quote WHERE OpportunityId = :opp.Id]
      );
    }
  }

  @IsTest
  static void recurringTermsSyncForDuplicateProductsAndSurviveEdits() {
    Opportunity opp = opportunity('QB With Pricebook');
    Id entryId = entries(opp.Pricebook2Id).get('Listing reinstatement');
    update new PricebookEntry(Id = entryId, Payment_type__c = 'Recurring');
    QuoteBuilderController.LineInput inherited = line(entryId, 1, 0);
    QuoteBuilderController.LineInput overridden = line(entryId, 2, 0);
    inherited.depositAmount = 100;
    overridden.depositAmount = 25;
    overridden.termMonths = 6;
    QuoteBuilderController.QuoteInfo quote = QuoteBuilderController.saveQuote(
      opp.Id,
      null,
      null,
      null,
      new List<QuoteBuilderController.LineInput>{ inherited, overridden },
      12
    );
    Assert.areEqual(12, quote.termMonths);
    Assert.isTrue(quote.lines[0].isRecurring);
    for (QuoteBuilderController.Line savedLine : quote.lines) {
      Assert.areEqual(savedLine.quantity == 1, savedLine.inheritsQuoteTerm);
      Assert.areEqual(savedLine.quantity == 1 ? 12 : 6, savedLine.termMonths);
    }
    QuoteBuilderController.syncQuoteToOpportunity(opp.Id, quote.quoteId);
    List<QuoteLineItem> linked = [
      SELECT Term_Months__c, OpportunityLineItemId, Deposit__c
      FROM QuoteLineItem
      WHERE QuoteId = :quote.quoteId
    ];
    Assert.areEqual(2, linked.size());
    Map<Id, OpportunityLineItem> products = new Map<Id, OpportunityLineItem>(
      [
        SELECT Term_Months__c, Deposit__c
        FROM OpportunityLineItem
        WHERE OpportunityId = :opp.Id
      ]
    );
    for (QuoteLineItem item : linked) {
      Assert.isNotNull(
        item.OpportunityLineItemId,
        'Native sync must preserve each line link.'
      );
      Assert.areEqual(
        item.Term_Months__c,
        products.get(item.OpportunityLineItemId).Term_Months__c
      );
      Assert.areEqual(
        item.Deposit__c,
        products.get(item.OpportunityLineItemId).Deposit__c
      );
    }
    QuoteBuilderController.QuoteInfo edited = QuoteBuilderController.saveQuote(
      opp.Id,
      quote.quoteId,
      null,
      'Updated term',
      new List<QuoteBuilderController.LineInput>{ inherited },
      24
    );
    Assert.areEqual(24, edited.lines[0].termMonths);
    Assert.isTrue(edited.lines[0].inheritsQuoteTerm);
    Assert.areEqual(
      24,
      [
        SELECT Term_Months__c
        FROM OpportunityLineItem
        WHERE OpportunityId = :opp.Id
      ]
      .Term_Months__c
    );
  }

  @IsTest
  static void draftQuoteCanChangePricebookWithoutChangingCatalogue() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    PricebookEntry original = [
      SELECT Product2Id
      FROM PricebookEntry
      WHERE Id = :quote.lines[0].pricebookEntryId
    ];
    Pricebook2 replacement = new Pricebook2(
      Name = 'QB Replacement',
      IsActive = true
    );
    insert replacement;
    PricebookEntry replacementEntry = new PricebookEntry(
      Pricebook2Id = replacement.Id,
      Product2Id = original.Product2Id,
      UnitPrice = 550,
      IsActive = true
    );
    insert replacementEntry;
    QuoteBuilderController.setPricebook(opp.Id, replacement.Id);
    QuoteBuilderController.QuoteInfo edited = QuoteBuilderController.saveQuote(
      opp.Id,
      quote.quoteId,
      null,
      'New price book',
      new List<QuoteBuilderController.LineInput>{
        line(replacementEntry.Id, 1, 0)
      },
      null
    );
    Assert.areEqual(replacement.Id, edited.pricebookId);
    Assert.areEqual(550, edited.totalPrice);
    Assert.areEqual(1, edited.lines.size());
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
    );
  }

  private static Id replacementPricebook() {
    Pricebook2 replacement = new Pricebook2(
      Name = 'QB Confirmed Replacement',
      IsActive = true
    );
    insert replacement;
    Product2 original = [
      SELECT Id
      FROM Product2
      WHERE Name = 'Listing reinstatement'
      LIMIT 1
    ];
    insert new PricebookEntry(
      Pricebook2Id = replacement.Id,
      Product2Id = original.Id,
      UnitPrice = 600,
      IsActive = true
    );
    return replacement.Id;
  }

  @IsTest
  static void confirmedPricebookChangeStopsSyncAndPreservesSavedQuote() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    QuoteBuilderController.syncQuoteToOpportunity(opp.Id, quote.quoteId);
    Id replacementId = replacementPricebook();
    List<QuoteLineItem> originalLines = [
      SELECT
        Id,
        PricebookEntryId,
        Quantity,
        UnitPrice,
        Discount,
        Term_Months__c,
        Use_Quote_Term__c
      FROM QuoteLineItem
      WHERE QuoteId = :quote.quoteId
      ORDER BY Id
    ];

    Test.startTest();
    QuoteBuilderController.Context changed = QuoteBuilderController.setPricebook(
      opp.Id,
      replacementId,
      true
    );
    Test.stopTest();

    Assert.areEqual(replacementId, changed.pricebookId);
    Assert.isNull(changed.syncedQuoteId);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
    );
    Quote kept = [
      SELECT Pricebook2Id, TotalPrice
      FROM Quote
      WHERE Id = :quote.quoteId
    ];
    Assert.areEqual(opp.Pricebook2Id, kept.Pricebook2Id);
    Assert.areEqual(1900, kept.TotalPrice);
    Assert.areEqual(
      JSON.serialize(originalLines),
      JSON.serialize(
        [
          SELECT
            Id,
            PricebookEntryId,
            Quantity,
            UnitPrice,
            Discount,
            Term_Months__c,
            Use_Quote_Term__c
          FROM QuoteLineItem
          WHERE QuoteId = :quote.quoteId
          ORDER BY Id
        ]
      ),
      'Stopping sync must preserve every saved quote line and its negotiated values.'
    );
  }

  @IsTest
  static void existingProductsRequireExplicitPricebookConfirmation() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    QuoteBuilderController.syncQuoteToOpportunity(opp.Id, quote.quoteId);
    Id replacementId = replacementPricebook();
    for (Boolean confirmed : new List<Boolean>{ false, null }) {
      try {
        QuoteBuilderController.setPricebook(opp.Id, replacementId, confirmed);
        Assert.fail(
          'A destructive price book change must require explicit confirmation.'
        );
      } catch (AuraHandledException expected) {
        Assert.isTrue(
          expected.getMessage().contains('Confirm the price book change')
        );
      }
      Opportunity unchanged = opportunity('QB With Pricebook');
      Assert.areEqual(opp.Pricebook2Id, unchanged.Pricebook2Id);
      Assert.areEqual(quote.quoteId, unchanged.SyncedQuoteId);
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
      );
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.quoteId]
      );
    }
  }

  @IsTest
  static void confirmingCurrentPricebookDoesNotRemoveProductsOrStopSync() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    QuoteBuilderController.syncQuoteToOpportunity(opp.Id, quote.quoteId);
    Set<Id> productIds = new Map<Id, OpportunityLineItem>(
        [SELECT Id FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
      )
      .keySet();
    QuoteBuilderController.Context unchanged = QuoteBuilderController.setPricebook(
      opp.Id,
      opp.Pricebook2Id,
      true
    );
    Assert.areEqual(quote.quoteId, unchanged.syncedQuoteId);
    Assert.areEqual(
      productIds,
      new Map<Id, OpportunityLineItem>(
          [SELECT Id FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
        )
        .keySet()
    );
  }

  @IsTest
  static void invalidPricebooksKeepSyncAndProductsIntact() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    QuoteBuilderController.syncQuoteToOpportunity(opp.Id, quote.quoteId);
    Pricebook2 inactive = new Pricebook2(
      Name = 'QB Inactive Target',
      IsActive = false
    );
    insert inactive;
    for (
      Id invalidId : new List<Id>{
        inactive.Id,
        null,
        Test.getStandardPricebookId()
      }
    ) {
      try {
        QuoteBuilderController.setPricebook(opp.Id, invalidId, true);
        Assert.fail(
          'An invalid target must be rejected before removing any products.'
        );
      } catch (AuraHandledException expected) {
        Opportunity unchanged = opportunity('QB With Pricebook');
        Assert.areEqual(opp.Pricebook2Id, unchanged.Pricebook2Id);
        Assert.areEqual(quote.quoteId, unchanged.SyncedQuoteId);
        Assert.areEqual(
          2,
          [
            SELECT COUNT()
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
          ]
        );
        Assert.areEqual(
          2,
          [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.quoteId]
        );
      }
    }
  }

  @IsTest
  static void confirmedPricebookChangeAlsoClearsUnsyncedOpportunityProducts() {
    QuoteBuilderController.QuoteInfo quote = createQuote();
    Opportunity opp = opportunity('QB With Pricebook');
    insert new OpportunityLineItem(
      OpportunityId = opp.Id,
      PricebookEntryId = quote.lines[0].pricebookEntryId,
      Quantity = 1,
      UnitPrice = 500
    );
    Id replacementId = replacementPricebook();
    QuoteBuilderController.Context changed = QuoteBuilderController.setPricebook(
      opp.Id,
      replacementId,
      true
    );
    Assert.areEqual(replacementId, changed.pricebookId);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.quoteId]
    );
    Assert.areEqual(
      opp.Pricebook2Id,
      [SELECT Pricebook2Id FROM Quote WHERE Id = :quote.quoteId].Pricebook2Id
    );
  }

  @IsTest
  static void quoteDepositsDefaultFromPricebookAndSyncStoredAmounts() {
    Opportunity opp = opportunity('QB With Pricebook');
    Id entryId = entries(opp.Pricebook2Id).get('Listing reinstatement');
    update new PricebookEntry(Id = entryId, Deposit__c = 125.50);
    QuoteBuilderController.Context initial = QuoteBuilderController.getContext(
      opp.Id
    );
    for (QuoteBuilderController.CatalogItem item : initial.catalog) {
      if (item.pricebookEntryId == entryId)
        Assert.areEqual(125.50, item.depositAmount);
    }
    QuoteBuilderController.LineInput input = line(entryId, 3, 0);
    QuoteBuilderController.QuoteInfo quote = QuoteBuilderController.saveQuote(
      opp.Id,
      null,
      null,
      null,
      new List<QuoteBuilderController.LineInput>{ input },
      null
    );
    Assert.areEqual(
      125.50,
      quote.lines[0].depositAmount,
      'Store the per-unit deposit, not a quantity-multiplied total.'
    );
    update new PricebookEntry(Id = entryId, Deposit__c = 250);
    input.depositAmount = quote.lines[0].depositAmount;
    quote = QuoteBuilderController.saveQuote(
      opp.Id,
      quote.quoteId,
      null,
      'Retain agreed deposit',
      new List<QuoteBuilderController.LineInput>{ input },
      null
    );
    QuoteBuilderController.syncQuoteToOpportunity(opp.Id, quote.quoteId);
    Assert.areEqual(
      125.50,
      [SELECT Deposit__c FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
      .Deposit__c
    );
    input.depositAmount = 75;
    quote = QuoteBuilderController.saveQuote(
      opp.Id,
      quote.quoteId,
      null,
      'Revised deposit',
      new List<QuoteBuilderController.LineInput>{ input },
      null
    );
    Assert.areEqual(75, quote.lines[0].depositAmount);
    Assert.areEqual(
      75,
      [SELECT Deposit__c FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
      .Deposit__c
    );
    Assert.areEqual(
      250,
      [SELECT Deposit__c FROM PricebookEntry WHERE Id = :entryId].Deposit__c
    );
  }

  @IsTest
  static void depositsSupportUnsetAndExplicitZeroAndRejectNegative() {
    Opportunity opp = opportunity('QB With Pricebook');
    Id entryId = entries(opp.Pricebook2Id).get('Listing reinstatement');
    QuoteBuilderController.LineInput input = line(entryId, 1, 0);
    QuoteBuilderController.QuoteInfo unset = QuoteBuilderController.saveQuote(
      opp.Id,
      null,
      null,
      null,
      new List<QuoteBuilderController.LineInput>{ input },
      null
    );
    Assert.isNull(unset.lines[0].depositAmount);
    update new PricebookEntry(Id = entryId, Deposit__c = 100);
    input.depositAmount = 0;
    QuoteBuilderController.QuoteInfo zero = QuoteBuilderController.saveQuote(
      opp.Id,
      null,
      null,
      null,
      new List<QuoteBuilderController.LineInput>{ input },
      null
    );
    Assert.areEqual(0, zero.lines[0].depositAmount);
    QuoteBuilderController.syncQuoteToOpportunity(opp.Id, zero.quoteId);
    Assert.areEqual(
      0,
      [SELECT Deposit__c FROM OpportunityLineItem WHERE OpportunityId = :opp.Id]
      .Deposit__c
    );
    input.depositAmount = -1;
    try {
      QuoteBuilderController.saveQuote(
        opp.Id,
        zero.quoteId,
        null,
        null,
        new List<QuoteBuilderController.LineInput>{ input },
        null
      );
      Assert.fail('Negative deposits must be rejected.');
    } catch (AuraHandledException expected) {
      Assert.areEqual(
        0,
        [SELECT Deposit__c FROM QuoteLineItem WHERE QuoteId = :zero.quoteId]
        .Deposit__c
      );
      Assert.areEqual(
        0,
        [
          SELECT Deposit__c
          FROM OpportunityLineItem
          WHERE OpportunityId = :opp.Id
        ]
        .Deposit__c
      );
    }
  }
}
