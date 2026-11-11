/**
 * QuoteBuilderController — backs the quoteBuilder LWC on the Opportunity record page.
 *
 * A simpler alternative to the standard "Add Products" / "Edit Products" / "New Quote" screens:
 *   1. getContext      — Opportunity, its price book, the price book catalogue, current lines, latest quote
 *   2. setPricebook    — pick or switch the price book (only while the Opportunity has no products)
 *   3. saveLines       — replace the Opportunity's products in one call (qty, discount %, note per line)
 *   4. createQuote     — copy the saved lines into a new Quote + QuoteLineItems
 *   5. generatePdf     — render the Quote with a Quote Template into a QuoteDocument (separate
 *                        transaction: getContentAsPDF counts as a callout and cannot follow DML)
 *
 * Rules enforced here, never in the browser:
 *   - prices always come from the Opportunity's price book (UnitPrice = list price, standard Discount field = %)
 *   - every product must be active in that price book
 *   - a discount above MAX_DISCOUNT_WITHOUT_APPROVAL needs the Quote_Discount_Override custom permission
 *
 * POC scope: no approval process, no email sending, no Opportunity stage change. See README.
 */
public with sharing class QuoteBuilderController {
  @TestVisible
  static final Decimal MAX_DISCOUNT_WITHOUT_APPROVAL = 15;
  @TestVisible
  static final String OVERRIDE_PERMISSION = 'Quote_Discount_Override';
  @TestVisible
  static final Integer MAX_LINES = 50;
  @TestVisible
  static Boolean overrideForTest; // lets tests simulate the custom permission

  // ------------------------------------------------------------------ DTOs

  public class Context {
    @AuraEnabled
    public Id opportunityId;
    @AuraEnabled
    public String opportunityName;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String stageName;
    @AuraEnabled
    public Id pricebookId;
    @AuraEnabled
    public String pricebookName;
    @AuraEnabled
    public Decimal maxDiscount = MAX_DISCOUNT_WITHOUT_APPROVAL;
    @AuraEnabled
    public Boolean canOverrideDiscount = false;
    @AuraEnabled
    public List<CatalogItem> catalog = new List<CatalogItem>();
    @AuraEnabled
    public List<Line> lines = new List<Line>();
    @AuraEnabled
    public QuoteInfo latestQuote;
    @AuraEnabled
    public Integer quoteCount = 0;
    @AuraEnabled
    public List<PricebookOption> pricebooks = new List<PricebookOption>();
  }

  public class CatalogItem {
    @AuraEnabled
    public Id pricebookEntryId;
    @AuraEnabled
    public Id productId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String family;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal listPrice;
  }

  public class Line {
    @AuraEnabled
    public Id pricebookEntryId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String family;
    @AuraEnabled
    public Decimal listPrice;
    @AuraEnabled
    public Decimal quantity;
    @AuraEnabled
    public Decimal discountPct;
    @AuraEnabled
    public String description;
  }

  public class QuoteInfo {
    @AuraEnabled
    public Id quoteId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String quoteNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date expirationDate;
    @AuraEnabled
    public Decimal totalPrice;
    @AuraEnabled
    public Id pdfId;
  }

  public class PricebookOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Integer productCount = 0;
    @AuraEnabled
    public Boolean isCurrent = false;
  }

  public class LineInput {
    @AuraEnabled
    public Id pricebookEntryId { get; set; }
    @AuraEnabled
    public Decimal quantity { get; set; }
    @AuraEnabled
    public Decimal discountPct { get; set; }
    @AuraEnabled
    public String description { get; set; }
  }

  // ------------------------------------------------------------------ reads

  @AuraEnabled
  public static Context getContext(Id opportunityId) {
    Opportunity opp = loadOpportunity(opportunityId);
    Context ctx = new Context();
    ctx.opportunityId = opp.Id;
    ctx.opportunityName = opp.Name;
    ctx.accountName = opp.Account?.Name;
    ctx.stageName = opp.StageName;
    ctx.pricebookId = opp.Pricebook2Id;
    ctx.pricebookName = opp.Pricebook2?.Name;
    ctx.canOverrideDiscount = canOverride();
    ctx.pricebooks = pricebookOptions(opp.Pricebook2Id);

    if (opp.Pricebook2Id == null) {
      return ctx;
    }

    for (PricebookEntry pbe : [
      SELECT
        Id,
        UnitPrice,
        Product2Id,
        Product2.Name,
        Product2.ProductCode,
        Product2.Family,
        Product2.Description
      FROM PricebookEntry
      WHERE
        Pricebook2Id = :opp.Pricebook2Id
        AND IsActive = TRUE
        AND Product2.IsActive = TRUE
      WITH USER_MODE
      ORDER BY Product2.Family NULLS LAST, Product2.Name
      LIMIT 1000
    ]) {
      CatalogItem c = new CatalogItem();
      c.pricebookEntryId = pbe.Id;
      c.productId = pbe.Product2Id;
      c.name = pbe.Product2.Name;
      c.code = pbe.Product2.ProductCode;
      c.family = pbe.Product2.Family;
      c.description = pbe.Product2.Description;
      c.listPrice = pbe.UnitPrice;
      ctx.catalog.add(c);
    }

    for (OpportunityLineItem oli : [
      SELECT
        PricebookEntryId,
        Product2.Name,
        Product2.Family,
        ListPrice,
        UnitPrice,
        Quantity,
        Discount,
        Description
      FROM OpportunityLineItem
      WHERE OpportunityId = :opp.Id
      WITH USER_MODE
      ORDER BY SortOrder, CreatedDate
    ]) {
      Line l = new Line();
      l.pricebookEntryId = oli.PricebookEntryId;
      l.name = oli.Product2.Name;
      l.family = oli.Product2.Family;
      l.listPrice = oli.ListPrice != null ? oli.ListPrice : oli.UnitPrice;
      l.quantity = oli.Quantity;
      l.discountPct = oli.Discount == null ? 0 : oli.Discount;
      l.description = oli.Description;
      ctx.lines.add(l);
    }

    List<Quote> quotes = [
      SELECT Id, Name, QuoteNumber, Status, ExpirationDate, TotalPrice
      FROM Quote
      WHERE OpportunityId = :opp.Id
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    ctx.quoteCount = [
      SELECT COUNT()
      FROM Quote
      WHERE OpportunityId = :opp.Id
      WITH USER_MODE
    ];
    if (!quotes.isEmpty()) {
      ctx.latestQuote = toInfo(quotes[0]);
    }
    return ctx;
  }

  // ------------------------------------------------------------------ writes

  @AuraEnabled
  public static Context setPricebook(Id opportunityId, Id pricebookId) {
    Opportunity opp = loadOpportunity(opportunityId);
    if (opp.Pricebook2Id == pricebookId) {
      return getContext(opportunityId);
    }
    // Salesforce only allows a price book change while the Opportunity has no products.
    Integer lineCount = [
      SELECT COUNT()
      FROM OpportunityLineItem
      WHERE OpportunityId = :opp.Id
      WITH USER_MODE
    ];
    if (lineCount > 0) {
      throw new AuraHandledException(
        'Remove the ' +
          lineCount +
          ' product(s) on this Opportunity before switching from the ' +
          opp.Pricebook2?.Name +
          ' price book.'
      );
    }
    List<Pricebook2> books = [
      SELECT Id
      FROM Pricebook2
      WHERE Id = :pricebookId AND IsActive = TRUE AND IsStandard = FALSE
      WITH USER_MODE
    ];
    if (books.isEmpty()) {
      throw new AuraHandledException('Choose an active price book.');
    }
    update as user new Opportunity(Id = opp.Id, Pricebook2Id = pricebookId);
    return getContext(opportunityId);
  }

  @AuraEnabled
  public static Context saveLines(Id opportunityId, List<LineInput> lines) {
    Opportunity opp = loadOpportunity(opportunityId);
    if (opp.Pricebook2Id == null) {
      throw new AuraHandledException('Choose a price book first.');
    }
    lines = lines == null ? new List<LineInput>() : lines;
    if (lines.size() > MAX_LINES) {
      throw new AuraHandledException(
        'A quote can have at most ' + MAX_LINES + ' lines.'
      );
    }

    Set<Id> entryIds = new Set<Id>();
    for (LineInput l : lines) {
      if (l.pricebookEntryId == null) {
        throw new AuraHandledException('A line is missing its product.');
      }
      entryIds.add(l.pricebookEntryId);
    }
    Map<Id, PricebookEntry> entries = new Map<Id, PricebookEntry>(
      [
        SELECT Id, UnitPrice, Product2.Name
        FROM PricebookEntry
        WHERE
          Id IN :entryIds
          AND Pricebook2Id = :opp.Pricebook2Id
          AND IsActive = TRUE
          AND Product2.IsActive = TRUE
        WITH USER_MODE
      ]
    );
    if (entries.size() != entryIds.size()) {
      throw new AuraHandledException(
        'One or more products are not active in the ' +
          opp.Pricebook2?.Name +
          ' price book.'
      );
    }

    Boolean mayOverride = canOverride();
    List<OpportunityLineItem> items = new List<OpportunityLineItem>();
    for (LineInput l : lines) {
      PricebookEntry pbe = entries.get(l.pricebookEntryId);
      Decimal qty = l.quantity == null ? 0 : l.quantity;
      Decimal disc = l.discountPct == null ? 0 : l.discountPct.setScale(2);
      if (qty <= 0 || qty > 9999) {
        throw new AuraHandledException(
          'Quantity for "' + pbe.Product2.Name + '" must be between 1 and 9999.'
        );
      }
      if (disc < 0 || disc > 100) {
        throw new AuraHandledException(
          'Discount for "' +
            pbe.Product2.Name +
            '" must be between 0% and 100%.'
        );
      }
      if (disc > MAX_DISCOUNT_WITHOUT_APPROVAL && !mayOverride) {
        throw new AuraHandledException(
          'Discount for "' +
            pbe.Product2.Name +
            '" is ' +
            disc.stripTrailingZeros().toPlainString() +
            '%. Above ' +
            MAX_DISCOUNT_WITHOUT_APPROVAL +
            '% needs manager approval.'
        );
      }
      items.add(
        new OpportunityLineItem(
          OpportunityId = opp.Id,
          PricebookEntryId = pbe.Id,
          Quantity = qty,
          UnitPrice = pbe.UnitPrice, // list price from the price book, never from the browser
          Discount = disc == 0 ? null : disc, // standard field: TotalPrice = Qty × UnitPrice × (1 − Discount)
          Description = l.description == null
            ? null
            : l.description.trim().left(255)
        )
      );
    }

    Savepoint sp = Database.setSavepoint();
    try {
      List<OpportunityLineItem> existing = [
        SELECT Id
        FROM OpportunityLineItem
        WHERE OpportunityId = :opp.Id
        WITH USER_MODE
      ];
      if (!existing.isEmpty()) {
        delete as user existing;
      }
      if (!items.isEmpty()) {
        insert as user items;
      }
    } catch (Exception e) {
      Database.rollback(sp);
      throw new AuraHandledException(
        'Could not save the products: ' + e.getMessage()
      );
    }
    return getContext(opportunityId);
  }

  @AuraEnabled
  public static QuoteInfo createQuote(
    Id opportunityId,
    Integer validDays,
    String notes
  ) {
    Opportunity opp = loadOpportunity(opportunityId);
    List<OpportunityLineItem> olis = [
      SELECT
        PricebookEntryId,
        Product2Id,
        Quantity,
        UnitPrice,
        Discount,
        Description
      FROM OpportunityLineItem
      WHERE OpportunityId = :opp.Id
      WITH USER_MODE
      ORDER BY SortOrder, CreatedDate
    ];
    if (olis.isEmpty()) {
      throw new AuraHandledException(
        'Add and save at least one product before creating a quote.'
      );
    }
    if (!canOverride()) {
      for (OpportunityLineItem oli : olis) {
        if (
          oli.Discount != null &&
          oli.Discount > MAX_DISCOUNT_WITHOUT_APPROVAL
        ) {
          throw new AuraHandledException(
            'A line has a discount above ' +
              MAX_DISCOUNT_WITHOUT_APPROVAL +
              '%; it needs approval first.'
          );
        }
      }
    }

    Integer days = validDays == null
      ? 14
      : Math.max(1, Math.min(validDays, 90));
    Integer version =
      [SELECT COUNT() FROM Quote WHERE OpportunityId = :opp.Id WITH USER_MODE] +
      1;

    Id contactId;
    for (OpportunityContactRole r : [
      SELECT ContactId
      FROM OpportunityContactRole
      WHERE OpportunityId = :opp.Id
      WITH USER_MODE
      ORDER BY IsPrimary DESC, CreatedDate
      LIMIT 1
    ]) {
      contactId = r.ContactId;
    }

    Quote q = new Quote(
      Name = (opp.Name + ' – Proposal v' + version).left(255),
      OpportunityId = opp.Id,
      Pricebook2Id = opp.Pricebook2Id,
      ExpirationDate = Date.today().addDays(days),
      Description = notes == null ? null : notes.trim().left(32000),
      ContactId = contactId
    );

    Savepoint sp = Database.setSavepoint();
    try {
      insert as user q;
      List<QuoteLineItem> qlis = new List<QuoteLineItem>();
      for (OpportunityLineItem oli : olis) {
        qlis.add(
          new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = oli.PricebookEntryId,
            Quantity = oli.Quantity,
            UnitPrice = oli.UnitPrice,
            Discount = oli.Discount,
            Description = oli.Description
          )
        );
      }
      insert as user qlis;
    } catch (Exception e) {
      Database.rollback(sp);
      throw new AuraHandledException(
        'Could not create the quote: ' + e.getMessage()
      );
    }

    return toInfo(
      [
        SELECT Id, Name, QuoteNumber, Status, ExpirationDate, TotalPrice
        FROM Quote
        WHERE Id = :q.Id
        WITH USER_MODE
      ]
    );
  }

  /**
   * Renders the quote with a Quote Template (Setup → Quote Templates; copy the template Id into
   * the component's "Quote Template Id" property) and saves it as a QuoteDocument.
   * Must run in its own transaction, after createQuote has committed.
   */
  @AuraEnabled
  public static Id generatePdf(Id quoteId, String templateId) {
    if (String.isBlank(templateId)) {
      return null;
    }
    Id template;
    try {
      template = Id.valueOf(templateId.trim());
    } catch (Exception e) {
      throw new AuraHandledException(
        'The Quote Template Id on this component is not valid.'
      );
    }
    List<Quote> quotes = [
      SELECT Id
      FROM Quote
      WHERE Id = :quoteId
      WITH USER_MODE
    ];
    if (quotes.isEmpty()) {
      throw new AuraHandledException('Quote not found.');
    }
    Blob pdf = renderPdf(quoteId, template);
    QuoteDocument doc = new QuoteDocument(QuoteId = quoteId, Document = pdf);
    insert as user doc;
    return doc.Id;
  }

  // ------------------------------------------------------------------ helpers

  @TestVisible
  private static Blob renderPdf(Id quoteId, Id templateId) {
    if (Test.isRunningTest()) {
      return Blob.valueOf('test pdf');
    }
    PageReference page = new PageReference(
      '/quote/quoteTemplateDataViewer.apexp?id=' +
        quoteId +
        '&summlid=' +
        templateId
    );
    return page.getContentAsPDF();
  }

  private static Opportunity loadOpportunity(Id opportunityId) {
    if (
      opportunityId == null ||
      opportunityId.getSobjectType() != Opportunity.SObjectType
    ) {
      throw new AuraHandledException(
        'Quote Builder only works on Opportunity records.'
      );
    }
    List<Opportunity> opps = [
      SELECT Id, Name, StageName, Pricebook2Id, Pricebook2.Name, Account.Name
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH USER_MODE
    ];
    if (opps.isEmpty()) {
      throw new AuraHandledException('Opportunity not found.');
    }
    return opps[0];
  }

  /** Active, non-standard price books with their description and number of active products. */
  private static List<PricebookOption> pricebookOptions(Id currentId) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT Pricebook2Id pb, COUNT(Id) n
      FROM PricebookEntry
      WHERE
        IsActive = TRUE
        AND Product2.IsActive = TRUE
        AND Pricebook2.IsActive = TRUE
        AND Pricebook2.IsStandard = FALSE
      WITH USER_MODE
      GROUP BY Pricebook2Id
    ]) {
      counts.put((Id) ar.get('pb'), (Integer) ar.get('n'));
    }
    List<PricebookOption> result = new List<PricebookOption>();
    for (Pricebook2 pb : [
      SELECT Id, Name, Description
      FROM Pricebook2
      WHERE IsActive = TRUE AND IsStandard = FALSE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 50
    ]) {
      PricebookOption o = new PricebookOption();
      o.id = pb.Id;
      o.name = pb.Name;
      o.description = pb.Description;
      o.productCount = counts.containsKey(pb.Id) ? counts.get(pb.Id) : 0;
      o.isCurrent = pb.Id == currentId;
      result.add(o);
    }
    return result;
  }

  private static Boolean canOverride() {
    if (overrideForTest != null) {
      return overrideForTest;
    }
    return FeatureManagement.checkPermission(OVERRIDE_PERMISSION);
  }

  private static QuoteInfo toInfo(Quote q) {
    QuoteInfo info = new QuoteInfo();
    info.quoteId = q.Id;
    info.name = q.Name;
    info.quoteNumber = q.QuoteNumber;
    info.status = q.Status;
    info.expirationDate = q.ExpirationDate;
    info.totalPrice = q.TotalPrice;
    for (QuoteDocument d : [
      SELECT Id
      FROM QuoteDocument
      WHERE QuoteId = :q.Id
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ]) {
      info.pdfId = d.Id;
    }
    return info;
  }
}
