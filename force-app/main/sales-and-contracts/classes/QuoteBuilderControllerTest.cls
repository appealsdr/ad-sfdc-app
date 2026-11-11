@IsTest
private class QuoteBuilderControllerTest {
  @TestSetup
  static void setup() {
    Id standardPb = Test.getStandardPricebookId();
    Pricebook2 servicePb = new Pricebook2(
      Name = 'QB Test SERVICE',
      IsActive = true
    );
    insert servicePb;

    Product2 violation = new Product2(
      Name = 'Violation Removal – High impact',
      Family = 'Violation Removal',
      IsActive = true
    );
    Product2 listing = new Product2(
      Name = 'Listing Issues – Reinstate Listing',
      Family = 'Listing Issues',
      IsActive = true
    );
    insert new List<Product2>{ violation, listing };

    insert new List<PricebookEntry>{
      new PricebookEntry(
        Pricebook2Id = standardPb,
        Product2Id = violation.Id,
        UnitPrice = 400,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = standardPb,
        Product2Id = listing.Id,
        UnitPrice = 900,
        IsActive = true
      )
    };
    insert new List<PricebookEntry>{
      new PricebookEntry(
        Pricebook2Id = servicePb.Id,
        Product2Id = violation.Id,
        UnitPrice = 400,
        IsActive = true
      ),
      new PricebookEntry(
        Pricebook2Id = servicePb.Id,
        Product2Id = listing.Id,
        UnitPrice = 900,
        IsActive = true
      )
    };

    Account acc = new Account(Name = 'QB Test Seller');
    insert acc;
    insert new List<Opportunity>{
      new Opportunity(
        Name = 'QB With Pricebook',
        AccountId = acc.Id,
        StageName = 'Meeting Booked',
        CloseDate = Date.today().addDays(30),
        Pricebook2Id = servicePb.Id
      ),
      new Opportunity(
        Name = 'QB No Pricebook',
        AccountId = acc.Id,
        StageName = 'Meeting Booked',
        CloseDate = Date.today().addDays(30)
      )
    };
  }

  private static Opportunity opp(String name) {
    return [SELECT Id, Pricebook2Id FROM Opportunity WHERE Name = :name];
  }

  private static Map<String, Id> entriesByProduct(Id pricebookId) {
    Map<String, Id> result = new Map<String, Id>();
    for (PricebookEntry pbe : [
      SELECT Id, Product2.Name
      FROM PricebookEntry
      WHERE Pricebook2Id = :pricebookId
    ]) {
      result.put(pbe.Product2.Name, pbe.Id);
    }
    return result;
  }

  private static QuoteBuilderController.LineInput line(
    Id entryId,
    Decimal qty,
    Decimal disc
  ) {
    QuoteBuilderController.LineInput l = new QuoteBuilderController.LineInput();
    l.pricebookEntryId = entryId;
    l.quantity = qty;
    l.discountPct = disc;
    l.description = 'ASIN B0TEST';
    return l;
  }

  @IsTest
  static void getContextReturnsCatalogue() {
    Opportunity o = opp('QB With Pricebook');
    Test.startTest();
    QuoteBuilderController.Context ctx = QuoteBuilderController.getContext(
      o.Id
    );
    Test.stopTest();
    Assert.areEqual(2, ctx.catalog.size());
    Assert.areEqual(0, ctx.lines.size());
    Assert.areEqual('QB Test SERVICE', ctx.pricebookName);
    Assert.isNull(ctx.latestQuote);
  }

  @IsTest
  static void noPricebookListsChoicesAndSetsOne() {
    Opportunity o = opp('QB No Pricebook');
    QuoteBuilderController.Context ctx = QuoteBuilderController.getContext(
      o.Id
    );
    Assert.isNull(ctx.pricebookId);
    Assert.isFalse(ctx.pricebooks.isEmpty());

    Id pb = [SELECT Id FROM Pricebook2 WHERE Name = 'QB Test SERVICE'].Id;
    Test.startTest();
    ctx = QuoteBuilderController.setPricebook(o.Id, pb);
    Test.stopTest();
    Assert.areEqual(pb, ctx.pricebookId);
    Assert.areEqual(2, ctx.catalog.size());
  }

  @IsTest
  static void switchingPricebookNeedsEmptyOpportunity() {
    Opportunity o = opp('QB With Pricebook');
    Pricebook2 other = new Pricebook2(
      Name = 'QB Test White Glove',
      IsActive = true,
      Description = 'Retainer tiers'
    );
    insert other;

    QuoteBuilderController.Context ctx = QuoteBuilderController.getContext(
      o.Id
    );
    Assert.areEqual(2, ctx.pricebooks.size());
    for (QuoteBuilderController.PricebookOption p : ctx.pricebooks) {
      Assert.areEqual(p.id == o.Pricebook2Id, p.isCurrent);
      Assert.areEqual(p.id == o.Pricebook2Id ? 2 : 0, p.productCount);
    }

    // no products yet: switch is allowed
    ctx = QuoteBuilderController.setPricebook(o.Id, other.Id);
    Assert.areEqual(other.Id, ctx.pricebookId);

    // switch back, add a product, then switching is blocked
    ctx = QuoteBuilderController.setPricebook(o.Id, o.Pricebook2Id);
    Map<String, Id> e = entriesByProduct(o.Pricebook2Id);
    QuoteBuilderController.saveLines(
      o.Id,
      new List<QuoteBuilderController.LineInput>{
        line(e.get('Listing Issues – Reinstate Listing'), 1, 0)
      }
    );
    try {
      QuoteBuilderController.setPricebook(o.Id, other.Id);
      Assert.fail('Expected the switch to be blocked');
    } catch (AuraHandledException ex) {
      Assert.isTrue(true);
    }
  }

  @IsTest
  static void saveLinesReplacesProductsWithPricebookPrices() {
    Opportunity o = opp('QB With Pricebook');
    Map<String, Id> e = entriesByProduct(o.Pricebook2Id);

    QuoteBuilderController.saveLines(
      o.Id,
      new List<QuoteBuilderController.LineInput>{
        line(e.get('Violation Removal – High impact'), 3, 10)
      }
    );
    Test.startTest();
    QuoteBuilderController.Context ctx = QuoteBuilderController.saveLines(
      o.Id,
      new List<QuoteBuilderController.LineInput>{
        line(e.get('Violation Removal – High impact'), 2, 10),
        line(e.get('Listing Issues – Reinstate Listing'), 1, 0)
      }
    );
    Test.stopTest();

    Assert.areEqual(2, ctx.lines.size());
    OpportunityLineItem oli = [
      SELECT UnitPrice, Quantity, Discount, TotalPrice
      FROM OpportunityLineItem
      WHERE
        OpportunityId = :o.Id
        AND Product2.Name = 'Violation Removal – High impact'
    ];
    Assert.areEqual(400, oli.UnitPrice);
    Assert.areEqual(2, oli.Quantity);
    Assert.areEqual(10, oli.Discount);
    Assert.areEqual(720, oli.TotalPrice);
  }

  @IsTest
  static void discountAboveLimitNeedsPermission() {
    Opportunity o = opp('QB With Pricebook');
    Map<String, Id> e = entriesByProduct(o.Pricebook2Id);
    List<QuoteBuilderController.LineInput> lines = new List<QuoteBuilderController.LineInput>{
      line(e.get('Listing Issues – Reinstate Listing'), 1, 25)
    };

    QuoteBuilderController.overrideForTest = false;
    try {
      QuoteBuilderController.saveLines(o.Id, lines);
      Assert.fail('Expected the discount to be rejected');
    } catch (AuraHandledException ex) {
      Assert.isTrue(true);
    }

    QuoteBuilderController.overrideForTest = true;
    QuoteBuilderController.Context ctx = QuoteBuilderController.saveLines(
      o.Id,
      lines
    );
    Assert.areEqual(25, ctx.lines[0].discountPct);
  }

  @IsTest
  static void invalidInputIsRejected() {
    Opportunity o = opp('QB With Pricebook');
    Map<String, Id> e = entriesByProduct(o.Pricebook2Id);
    Id standardEntry = [
      SELECT Id
      FROM PricebookEntry
      WHERE Pricebook2Id = :Test.getStandardPricebookId()
      LIMIT 1
    ]
    .Id;

    List<List<QuoteBuilderController.LineInput>> bad = new List<List<QuoteBuilderController.LineInput>>{
      new List<QuoteBuilderController.LineInput>{
        line(e.get('Listing Issues – Reinstate Listing'), 0, 0)
      },
      new List<QuoteBuilderController.LineInput>{
        line(e.get('Listing Issues – Reinstate Listing'), 1, -5)
      },
      new List<QuoteBuilderController.LineInput>{ line(standardEntry, 1, 0) },
      new List<QuoteBuilderController.LineInput>{ line(null, 1, 0) }
    };
    Integer failures = 0;
    for (List<QuoteBuilderController.LineInput> lines : bad) {
      try {
        QuoteBuilderController.saveLines(o.Id, lines);
      } catch (AuraHandledException ex) {
        failures++;
      }
    }
    Assert.areEqual(bad.size(), failures);
  }

  @IsTest
  static void createQuoteCopiesLinesAndRendersPdf() {
    Opportunity o = opp('QB With Pricebook');
    Map<String, Id> e = entriesByProduct(o.Pricebook2Id);
    QuoteBuilderController.saveLines(
      o.Id,
      new List<QuoteBuilderController.LineInput>{
        line(e.get('Violation Removal – High impact'), 2, 10),
        line(e.get('Listing Issues – Reinstate Listing'), 1, 0)
      }
    );

    Test.startTest();
    QuoteBuilderController.QuoteInfo info = QuoteBuilderController.createQuote(
      o.Id,
      14,
      'Valid for 14 days'
    );
    Id pdfId = QuoteBuilderController.generatePdf(
      info.quoteId,
      '0EH000000000001'
    );
    Test.stopTest();

    Quote q = [
      SELECT
        Name,
        ExpirationDate,
        Pricebook2Id,
        TotalPrice,
        (SELECT Id FROM QuoteLineItems)
      FROM Quote
      WHERE Id = :info.quoteId
    ];
    Assert.areEqual(2, q.QuoteLineItems.size());
    Assert.areEqual(Date.today().addDays(14), q.ExpirationDate);
    Assert.areEqual(o.Pricebook2Id, q.Pricebook2Id);
    Assert.areEqual(1620, q.TotalPrice);
    Assert.isTrue(q.Name.endsWith('Proposal v1'));
    Assert.isNotNull(pdfId);

    QuoteBuilderController.Context ctx = QuoteBuilderController.getContext(
      o.Id
    );
    Assert.areEqual(info.quoteId, ctx.latestQuote.quoteId);
    Assert.areEqual(pdfId, ctx.latestQuote.pdfId);
  }

  @IsTest
  static void createQuoteNeedsLinesAndValidTemplate() {
    Opportunity o = opp('QB With Pricebook');
    try {
      QuoteBuilderController.createQuote(o.Id, 14, null);
      Assert.fail('Expected an error without lines');
    } catch (AuraHandledException ex) {
      Assert.isTrue(true);
    }
    Assert.isNull(QuoteBuilderController.generatePdf(null, ''));
    try {
      QuoteBuilderController.generatePdf(null, 'not-an-id');
      Assert.fail('Expected an invalid template error');
    } catch (AuraHandledException ex) {
      Assert.isTrue(true);
    }
  }

  @IsTest
  static void rejectsNonOpportunityRecords() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    try {
      QuoteBuilderController.getContext(acc.Id);
      Assert.fail('Expected an error');
    } catch (AuraHandledException ex) {
      Assert.isTrue(true);
    }
  }
}
