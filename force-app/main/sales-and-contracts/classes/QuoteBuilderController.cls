/**
 * Quote-first workspace for the Opportunity record page.
 * Quotes own their lines; Opportunity products change only through explicit quote sync.
 */
public with sharing class QuoteBuilderController {
  @TestVisible
  private static final Decimal MAX_DISCOUNT_WITHOUT_APPROVAL = 15;
  @TestVisible
  private static final String OVERRIDE_PERMISSION = 'Quote_Discount_Override';
  @TestVisible
  private static final Integer MAX_LINES = 50;
  @TestVisible
  private static Boolean overrideForTest;

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
    public Id syncedQuoteId;
    @AuraEnabled
    public Decimal maxDiscount = MAX_DISCOUNT_WITHOUT_APPROVAL;
    @AuraEnabled
    public Boolean canOverrideDiscount = false;
    @AuraEnabled
    public List<CatalogItem> catalog = new List<CatalogItem>();
    @AuraEnabled
    public List<QuoteInfo> quotes = new List<QuoteInfo>();
    @AuraEnabled
    public List<PricebookOption> pricebooks = new List<PricebookOption>();
    @AuraEnabled
    public List<EmailTemplateOption> emailTemplates = new List<EmailTemplateOption>();
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
    public Id lineId;
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
    @AuraEnabled
    public Decimal totalPrice;
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
    public String notes;
    @AuraEnabled
    public Id pricebookId;
    @AuraEnabled
    public String pricebookName;
    @AuraEnabled
    public String recipientEmail;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public Datetime lastModifiedDate;
    @AuraEnabled
    public Id pdfId;
    @AuraEnabled
    public Boolean isSynced = false;
    @AuraEnabled
    public List<Line> lines = new List<Line>();
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

  public class EmailTemplateOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String folderName;
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
    ctx.syncedQuoteId = opp.SyncedQuoteId;
    ctx.canOverrideDiscount = canOverride();
    ctx.pricebooks = pricebookOptions(opp.Pricebook2Id);
    ctx.emailTemplates = activeEmailTemplates();
    if (opp.Pricebook2Id != null) {
      ctx.catalog = catalogFor(opp.Pricebook2Id);
    }
    for (Quote quoteRecord : [
      SELECT
        Id,
        Name,
        QuoteNumber,
        Status,
        ExpirationDate,
        TotalPrice,
        Description,
        Pricebook2Id,
        Pricebook2.Name,
        Email,
        Contact.Email,
        CreatedDate,
        LastModifiedDate,
        (SELECT Id FROM QuoteDocuments ORDER BY CreatedDate DESC LIMIT 1),
        (
          SELECT
            Id,
            PricebookEntryId,
            Product2.Name,
            Product2.Family,
            ListPrice,
            UnitPrice,
            Quantity,
            Discount,
            Description,
            TotalPrice
          FROM QuoteLineItems
          ORDER BY SortOrder, CreatedDate
        )
      FROM Quote
      WHERE OpportunityId = :opp.Id
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 100
    ]) {
      ctx.quotes.add(toInfo(quoteRecord, opp.SyncedQuoteId));
    }
    return ctx;
  }

  @AuraEnabled
  public static Context setPricebook(Id opportunityId, Id pricebookId) {
    Opportunity opp = loadOpportunity(opportunityId);
    if (opp.Pricebook2Id == pricebookId) {
      return getContext(opportunityId);
    }
    Integer lineCount = [
      SELECT COUNT()
      FROM OpportunityLineItem
      WHERE OpportunityId = :opp.Id
      WITH USER_MODE
    ];
    if (lineCount > 0) {
      throw new AuraHandledException(
        'Opportunity products already use the ' +
          opp.Pricebook2?.Name +
          ' price book. Remove or sync them before changing price books.'
      );
    }
    validatePricebook(pricebookId);
    update as user new Opportunity(Id = opp.Id, Pricebook2Id = pricebookId);
    return getContext(opportunityId);
  }

  @AuraEnabled
  public static QuoteInfo saveQuote(
    Id opportunityId,
    Id quoteId,
    Date expirationDate,
    String notes,
    List<LineInput> lines
  ) {
    Opportunity opp = loadOpportunity(opportunityId);
    if (opp.Pricebook2Id == null) {
      throw new AuraHandledException(
        'Choose a price book before building a quote.'
      );
    }
    Map<Id, PricebookEntry> entries = validateLines(opp.Pricebook2Id, lines);
    Id contactId = primaryContactId(opp.Id);
    Quote quoteRecord;
    Savepoint sp = Database.setSavepoint();
    try {
      if (quoteId == null) {
        Integer version =
          [
            SELECT COUNT()
            FROM Quote
            WHERE OpportunityId = :opp.Id
            WITH USER_MODE
          ] + 1;
        quoteRecord = new Quote(
          Name = (opp.Name + ' – Proposal v' + version).left(255),
          OpportunityId = opp.Id,
          Pricebook2Id = opp.Pricebook2Id,
          ContactId = contactId,
          ExpirationDate = expirationDate == null
            ? Date.today().addDays(14)
            : expirationDate,
          Description = cleanNotes(notes),
          Status = 'Draft'
        );
        insert as user quoteRecord;
      } else {
        quoteRecord = loadQuoteForUpdate(quoteId, opp.Id);
        List<QuoteLineItem> existing = [
          SELECT Id
          FROM QuoteLineItem
          WHERE QuoteId = :quoteRecord.Id
          WITH USER_MODE
        ];
        if (!existing.isEmpty()) {
          delete as user existing;
        }
        quoteRecord.ExpirationDate = expirationDate;
        quoteRecord.Description = cleanNotes(notes);
        if (quoteRecord.ContactId == null) {
          quoteRecord.ContactId = contactId;
        }
        update as user quoteRecord;
      }
      List<QuoteLineItem> quoteLines = new List<QuoteLineItem>();
      for (LineInput input : lines) {
        PricebookEntry entry = entries.get(input.pricebookEntryId);
        Decimal discount = input.discountPct == null
          ? 0
          : input.discountPct.setScale(2);
        quoteLines.add(
          new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = entry.Id,
            Quantity = input.quantity,
            UnitPrice = entry.UnitPrice,
            Discount = discount == 0 ? null : discount,
            Description = input.description == null
              ? null
              : input.description.trim().left(255)
          )
        );
      }
      insert as user quoteLines;
    } catch (Exception error) {
      Database.rollback(sp);
      throw handled('Could not save the quote', error);
    }
    return queryQuoteInfo(quoteRecord.Id, opp.SyncedQuoteId);
  }

  @AuraEnabled
  public static Context syncQuoteToOpportunity(Id opportunityId, Id quoteId) {
    Opportunity opp = loadOpportunity(opportunityId);
    Quote quoteRecord = loadQuoteForUpdate(quoteId, opp.Id);
    Integer lineCount = [
      SELECT COUNT()
      FROM QuoteLineItem
      WHERE QuoteId = :quoteRecord.Id
      WITH USER_MODE
    ];
    if (lineCount == 0) {
      throw new AuraHandledException(
        'Add at least one product before syncing this quote.'
      );
    }
    try {
      update as user new Opportunity(
        Id = opp.Id,
        SyncedQuoteId = quoteRecord.Id
      );
    } catch (Exception error) {
      throw handled('Could not sync the quote to the Opportunity', error);
    }
    return getContext(opportunityId);
  }

  @AuraEnabled
  public static Id generatePdf(Id quoteId) {
    Quote quoteRecord = loadQuoteForAccess(quoteId);
    Blob pdf = renderPdf(quoteRecord.Id);
    QuoteDocument document = new QuoteDocument(
      QuoteId = quoteRecord.Id,
      Document = pdf
    );
    insert as user document;
    return document.Id;
  }

  @AuraEnabled
  public static QuoteInfo sendQuote(
    Id quoteId,
    String recipientEmail,
    Id templateId
  ) {
    Quote quoteRecord = loadQuoteForAccess(quoteId);
    String recipient = String.isBlank(recipientEmail)
      ? resolveRecipient(quoteRecord)
      : recipientEmail.trim();
    if (String.isBlank(recipient) || !isValidEmail(recipient)) {
      throw new AuraHandledException('Enter a valid recipient email address.');
    }
    EmailTemplate selectedTemplate = loadEmailTemplate(templateId);
    Id mergeContactId = resolveMergeContactId(quoteRecord, recipient);
    if (selectedTemplate != null && mergeContactId == null) {
      throw new AuraHandledException(
        'Add a Contact to the Opportunity before using an email template.'
      );
    }
    Blob pdf = renderPdf(quoteRecord.Id);
    Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
    attachment.setFileName(
      (quoteRecord.QuoteNumber == null ? 'Quote' : quoteRecord.QuoteNumber) +
      '.pdf'
    );
    attachment.setContentType('application/pdf');
    attachment.setBody(pdf);
    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
    email.setToAddresses(new List<String>{ recipient });
    if (selectedTemplate == null) {
      email.setSubject(quoteRecord.Name);
      email.setPlainTextBody(
        'Hello,\n\nPlease find your quote for ' +
          quoteRecord.Opportunity.Name +
          ' attached.\n\nThank you,\nAppeals Doctor'
      );
    } else {
      email.setTemplateId(selectedTemplate.Id);
      email.setTargetObjectId(mergeContactId);
      email.setTreatTargetObjectAsRecipient(false);
      email.setWhatId(quoteRecord.OpportunityId);
    }
    email.setSaveAsActivity(false);
    email.setFileAttachments(
      new List<Messaging.EmailFileAttachment>{ attachment }
    );
    Messaging.SendEmailResult[] results = Messaging.sendEmail(
      new List<Messaging.SingleEmailMessage>{ email }
    );
    if (results.isEmpty() || !results[0].isSuccess()) {
      String reason = results.isEmpty()
        ? 'Unknown email error.'
        : results[0].getErrors()[0].getMessage();
      throw new AuraHandledException(
        'The quote email could not be sent: ' + reason
      );
    }
    insert as user new QuoteDocument(QuoteId = quoteRecord.Id, Document = pdf);
    update as user new Quote(Id = quoteRecord.Id, Status = 'Presented');
    insert as user new Task(
      WhatId = quoteRecord.OpportunityId,
      WhoId = mergeContactId,
      Subject = 'Email: ' +
        (selectedTemplate == null
          ? quoteRecord.Name
          : selectedTemplate.Subject),
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today(),
      Description = 'Quote ' +
        quoteRecord.Name +
        ' sent to ' +
        recipient +
        (selectedTemplate == null
          ? ' using the default quote email.'
          : ' using template "' + selectedTemplate.Name + '".')
    );
    Opportunity opp = [
      SELECT SyncedQuoteId
      FROM Opportunity
      WHERE Id = :quoteRecord.OpportunityId
      WITH USER_MODE
    ];
    return queryQuoteInfo(quoteRecord.Id, opp.SyncedQuoteId);
  }

  @TestVisible
  private static Blob renderPdf(Id quoteId) {
    if (Test.isRunningTest()) {
      return Blob.valueOf('quote pdf');
    }
    PageReference page = Page.QuoteBuilderPdf;
    page.getParameters().put('id', quoteId);
    return page.getContentAsPDF();
  }

  private static Map<Id, PricebookEntry> validateLines(
    Id pricebookId,
    List<LineInput> lines
  ) {
    lines = lines == null ? new List<LineInput>() : lines;
    if (lines.isEmpty()) {
      throw new AuraHandledException('Add at least one product to the quote.');
    }
    if (lines.size() > MAX_LINES) {
      throw new AuraHandledException(
        'A quote can have at most ' + MAX_LINES + ' lines.'
      );
    }
    Set<Id> entryIds = new Set<Id>();
    for (LineInput input : lines) {
      if (input == null || input.pricebookEntryId == null) {
        throw new AuraHandledException('A quote line is missing its product.');
      }
      entryIds.add(input.pricebookEntryId);
    }
    Map<Id, PricebookEntry> entries = new Map<Id, PricebookEntry>(
      [
        SELECT Id, UnitPrice, Product2.Name
        FROM PricebookEntry
        WHERE
          Id IN :entryIds
          AND Pricebook2Id = :pricebookId
          AND IsActive = TRUE
          AND Product2.IsActive = TRUE
        WITH USER_MODE
      ]
    );
    if (entries.size() != entryIds.size()) {
      throw new AuraHandledException(
        'One or more products are not active in this price book.'
      );
    }
    Boolean mayOverride = canOverride();
    for (LineInput input : lines) {
      PricebookEntry entry = entries.get(input.pricebookEntryId);
      Decimal quantity = input.quantity == null ? 0 : input.quantity;
      Decimal discount = input.discountPct == null ? 0 : input.discountPct;
      if (quantity <= 0 || quantity > 9999) {
        throw new AuraHandledException(
          'Quantity for "' +
            entry.Product2.Name +
            '" must be between 1 and 9999.'
        );
      }
      if (discount < 0 || discount > 100) {
        throw new AuraHandledException(
          'Discount for "' +
            entry.Product2.Name +
            '" must be between 0% and 100%.'
        );
      }
      if (discount > MAX_DISCOUNT_WITHOUT_APPROVAL && !mayOverride) {
        throw new AuraHandledException(
          'Discount for "' +
            entry.Product2.Name +
            '" is above ' +
            MAX_DISCOUNT_WITHOUT_APPROVAL +
            '% and needs manager approval.'
        );
      }
    }
    return entries;
  }

  private static List<CatalogItem> catalogFor(Id pricebookId) {
    List<CatalogItem> result = new List<CatalogItem>();
    for (PricebookEntry entry : [
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
        Pricebook2Id = :pricebookId
        AND IsActive = TRUE
        AND Product2.IsActive = TRUE
      WITH USER_MODE
      ORDER BY Product2.Family NULLS LAST, Product2.Name
      LIMIT 1000
    ]) {
      CatalogItem item = new CatalogItem();
      item.pricebookEntryId = entry.Id;
      item.productId = entry.Product2Id;
      item.name = entry.Product2.Name;
      item.code = entry.Product2.ProductCode;
      item.family = entry.Product2.Family;
      item.description = entry.Product2.Description;
      item.listPrice = entry.UnitPrice;
      result.add(item);
    }
    return result;
  }

  private static List<PricebookOption> pricebookOptions(Id currentId) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (AggregateResult row : [
      SELECT Pricebook2Id pricebookId, COUNT(Id) productCount
      FROM PricebookEntry
      WHERE
        IsActive = TRUE
        AND Product2.IsActive = TRUE
        AND Pricebook2.IsActive = TRUE
        AND Pricebook2.IsStandard = FALSE
      WITH USER_MODE
      GROUP BY Pricebook2Id
    ]) {
      counts.put(
        (Id) row.get('pricebookId'),
        (Integer) row.get('productCount')
      );
    }
    List<PricebookOption> result = new List<PricebookOption>();
    for (Pricebook2 pricebook : [
      SELECT Id, Name, Description
      FROM Pricebook2
      WHERE IsActive = TRUE AND IsStandard = FALSE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 50
    ]) {
      PricebookOption option = new PricebookOption();
      option.id = pricebook.Id;
      option.name = pricebook.Name;
      option.description = pricebook.Description;
      option.productCount = counts.containsKey(pricebook.Id)
        ? counts.get(pricebook.Id)
        : 0;
      option.isCurrent = pricebook.Id == currentId;
      result.add(option);
    }
    return result;
  }

  private static QuoteInfo queryQuoteInfo(Id quoteId, Id syncedQuoteId) {
    Quote quoteRecord = [
      SELECT
        Id,
        Name,
        QuoteNumber,
        Status,
        ExpirationDate,
        TotalPrice,
        Description,
        Pricebook2Id,
        Pricebook2.Name,
        Email,
        Contact.Email,
        CreatedDate,
        LastModifiedDate,
        (SELECT Id FROM QuoteDocuments ORDER BY CreatedDate DESC LIMIT 1),
        (
          SELECT
            Id,
            PricebookEntryId,
            Product2.Name,
            Product2.Family,
            ListPrice,
            UnitPrice,
            Quantity,
            Discount,
            Description,
            TotalPrice
          FROM QuoteLineItems
          ORDER BY SortOrder, CreatedDate
        )
      FROM Quote
      WHERE Id = :quoteId
      WITH USER_MODE
    ];
    return toInfo(quoteRecord, syncedQuoteId);
  }

  private static QuoteInfo toInfo(Quote quoteRecord, Id syncedQuoteId) {
    QuoteInfo info = new QuoteInfo();
    info.quoteId = quoteRecord.Id;
    info.name = quoteRecord.Name;
    info.quoteNumber = quoteRecord.QuoteNumber;
    info.status = quoteRecord.Status;
    info.expirationDate = quoteRecord.ExpirationDate;
    info.totalPrice = quoteRecord.TotalPrice;
    info.notes = quoteRecord.Description;
    info.pricebookId = quoteRecord.Pricebook2Id;
    info.pricebookName = quoteRecord.Pricebook2?.Name;
    info.recipientEmail = String.isNotBlank(quoteRecord.Email)
      ? quoteRecord.Email
      : quoteRecord.Contact?.Email;
    info.createdDate = quoteRecord.CreatedDate;
    info.lastModifiedDate = quoteRecord.LastModifiedDate;
    info.isSynced = quoteRecord.Id == syncedQuoteId;
    if (
      quoteRecord.QuoteDocuments != null &&
      !quoteRecord.QuoteDocuments.isEmpty()
    ) {
      info.pdfId = quoteRecord.QuoteDocuments[0].Id;
    }
    if (quoteRecord.QuoteLineItems != null) {
      for (QuoteLineItem quoteLine : quoteRecord.QuoteLineItems) {
        Line line = new Line();
        line.lineId = quoteLine.Id;
        line.pricebookEntryId = quoteLine.PricebookEntryId;
        line.name = quoteLine.Product2.Name;
        line.family = quoteLine.Product2.Family;
        line.listPrice = quoteLine.ListPrice == null
          ? quoteLine.UnitPrice
          : quoteLine.ListPrice;
        line.quantity = quoteLine.Quantity;
        line.discountPct = quoteLine.Discount == null ? 0 : quoteLine.Discount;
        line.description = quoteLine.Description;
        line.totalPrice = quoteLine.TotalPrice;
        info.lines.add(line);
      }
    }
    return info;
  }

  private static Opportunity loadOpportunity(Id opportunityId) {
    if (
      opportunityId == null ||
      opportunityId.getSObjectType() != Opportunity.SObjectType
    ) {
      throw new AuraHandledException(
        'Quote Builder only works on Opportunity records.'
      );
    }
    List<Opportunity> opportunities = [
      SELECT
        Id,
        Name,
        StageName,
        Pricebook2Id,
        Pricebook2.Name,
        Account.Name,
        SyncedQuoteId
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH USER_MODE
    ];
    if (opportunities.isEmpty()) {
      throw new AuraHandledException('Opportunity not found.');
    }
    return opportunities[0];
  }

  private static Quote loadQuoteForUpdate(Id quoteId, Id opportunityId) {
    if (quoteId == null || quoteId.getSObjectType() != Quote.SObjectType) {
      throw new AuraHandledException('Choose a valid quote.');
    }
    List<Quote> quotes = [
      SELECT Id, OpportunityId, Pricebook2Id, ContactId
      FROM Quote
      WHERE Id = :quoteId AND OpportunityId = :opportunityId
      WITH USER_MODE
    ];
    if (quotes.isEmpty()) {
      throw new AuraHandledException('Quote not found on this Opportunity.');
    }
    return quotes[0];
  }

  private static Quote loadQuoteForAccess(Id quoteId) {
    if (quoteId == null || quoteId.getSObjectType() != Quote.SObjectType) {
      throw new AuraHandledException('Choose a valid quote.');
    }
    List<Quote> quotes = [
      SELECT
        Id,
        Name,
        QuoteNumber,
        Status,
        Email,
        ContactId,
        Contact.Email,
        OpportunityId,
        Opportunity.Name
      FROM Quote
      WHERE Id = :quoteId
      WITH USER_MODE
    ];
    if (quotes.isEmpty()) {
      throw new AuraHandledException('Quote not found.');
    }
    return quotes[0];
  }

  private static void validatePricebook(Id pricebookId) {
    if (
      pricebookId == null ||
      [
        SELECT COUNT()
        FROM Pricebook2
        WHERE Id = :pricebookId AND IsActive = TRUE AND IsStandard = FALSE
        WITH USER_MODE
      ] == 0
    ) {
      throw new AuraHandledException('Choose an active price book.');
    }
  }

  private static Id primaryContactId(Id opportunityId) {
    for (OpportunityContactRole role : [
      SELECT ContactId
      FROM OpportunityContactRole
      WHERE OpportunityId = :opportunityId
      WITH USER_MODE
      ORDER BY IsPrimary DESC, CreatedDate
      LIMIT 1
    ]) {
      return role.ContactId;
    }
    return null;
  }

  private static String resolveRecipient(Quote quoteRecord) {
    if (String.isNotBlank(quoteRecord.Email))
      return quoteRecord.Email;
    if (String.isNotBlank(quoteRecord.Contact?.Email))
      return quoteRecord.Contact.Email;
    for (OpportunityContactRole role : [
      SELECT Contact.Email
      FROM OpportunityContactRole
      WHERE OpportunityId = :quoteRecord.OpportunityId AND Contact.Email != NULL
      WITH USER_MODE
      ORDER BY IsPrimary DESC, CreatedDate
      LIMIT 1
    ]) {
      return role.Contact.Email;
    }
    return null;
  }

  private static List<EmailTemplateOption> activeEmailTemplates() {
    List<EmailTemplateOption> options = new List<EmailTemplateOption>();
    for (EmailTemplate template : [
      SELECT Id, Name, Subject, Folder.Name
      FROM EmailTemplate
      WHERE IsActive = TRUE
      ORDER BY Folder.Name, Name
      LIMIT 200
    ]) {
      EmailTemplateOption option = new EmailTemplateOption();
      option.id = template.Id;
      option.name = template.Name;
      option.subject = template.Subject;
      option.folderName = template.Folder?.Name;
      options.add(option);
    }
    return options;
  }

  private static EmailTemplate loadEmailTemplate(Id templateId) {
    if (templateId == null)
      return null;
    if (templateId.getSObjectType() != EmailTemplate.SObjectType) {
      throw new AuraHandledException('Choose a valid email template.');
    }
    List<EmailTemplate> templates = [
      SELECT Id, Name, Subject
      FROM EmailTemplate
      WHERE Id = :templateId AND IsActive = TRUE
      LIMIT 1
    ];
    if (templates.isEmpty()) {
      throw new AuraHandledException(
        'The selected email template is not active.'
      );
    }
    return templates[0];
  }

  private static Id resolveMergeContactId(
    Quote quoteRecord,
    String recipientEmail
  ) {
    if (
      quoteRecord.ContactId != null &&
      quoteRecord.Contact?.Email == recipientEmail
    ) {
      return quoteRecord.ContactId;
    }
    for (OpportunityContactRole role : [
      SELECT ContactId, Contact.Email
      FROM OpportunityContactRole
      WHERE OpportunityId = :quoteRecord.OpportunityId
      WITH USER_MODE
      ORDER BY IsPrimary DESC, CreatedDate
    ]) {
      if (role.Contact.Email == recipientEmail)
        return role.ContactId;
    }
    return primaryContactId(quoteRecord.OpportunityId);
  }

  private static Boolean isValidEmail(String value) {
    return Pattern.matches('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$', value);
  }

  private static String cleanNotes(String notes) {
    return String.isBlank(notes) ? null : notes.trim().left(32000);
  }

  private static Boolean canOverride() {
    return overrideForTest == null
      ? FeatureManagement.checkPermission(OVERRIDE_PERMISSION)
      : overrideForTest;
  }

  private static AuraHandledException handled(String prefix, Exception error) {
    return new AuraHandledException(prefix + ': ' + error.getMessage());
  }
}
