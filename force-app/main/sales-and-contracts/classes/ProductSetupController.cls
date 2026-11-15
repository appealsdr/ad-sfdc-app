public with sharing class ProductSetupController {
  public class SetupData {
    @AuraEnabled
    public List<PricebookRow> pricebooks { get; set; }
    @AuraEnabled
    public List<TemplateRow> templates { get; set; }
    @AuraEnabled
    public List<RequirementRow> requirements { get; set; }
    @AuraEnabled
    public List<String> paymentTypes { get; set; }
  }

  public class PricebookRow {
    @AuraEnabled
    public Id pricebookId { get; set; }
    @AuraEnabled
    public String pricebookName { get; set; }
    @AuraEnabled
    public Boolean isStandard { get; set; }
    @AuraEnabled
    public Id pricebookEntryId { get; set; }
    @AuraEnabled
    public Boolean selected { get; set; }
    @AuraEnabled
    public Decimal unitPrice { get; set; }
    @AuraEnabled
    public Decimal deposit { get; set; }
    @AuraEnabled
    public String paymentType { get; set; }
    @AuraEnabled
    public Boolean isActive { get; set; }
  }

  public class TemplateRow {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String shortDescription { get; set; }
    @AuraEnabled
    public String acceptedFormat { get; set; }
    @AuraEnabled
    public String instructions { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
  }

  public class RequirementRow {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public Id templateId { get; set; }
    @AuraEnabled
    public String shortDescription { get; set; }
    @AuraEnabled
    public String acceptedFormat { get; set; }
    @AuraEnabled
    public String instructions { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
    @AuraEnabled
    public Integer sortOrder { get; set; }
  }

  public class PricebookInput {
    @AuraEnabled
    public Id pricebookId { get; set; }
    @AuraEnabled
    public Boolean selected { get; set; }
    @AuraEnabled
    public Decimal unitPrice { get; set; }
    @AuraEnabled
    public Decimal deposit { get; set; }
    @AuraEnabled
    public String paymentType { get; set; }
  }

  public class RequirementInput {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public Id templateId { get; set; }
    @AuraEnabled
    public String shortDescription { get; set; }
    @AuraEnabled
    public String acceptedFormat { get; set; }
    @AuraEnabled
    public String instructions { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static SetupData getSetup(Id productId) {
    validateProduct(productId);
    SetupData data = new SetupData();
    data.pricebooks = buildPricebookRows(productId);
    data.templates = buildTemplateRows();
    data.requirements = buildRequirementRows(productId);
    data.paymentTypes = new List<String>();
    for (
      Schema.PicklistEntry entry : PricebookEntry.Payment_type__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive())
        data.paymentTypes.add(entry.getValue());
    }
    return data;
  }

  @AuraEnabled
  public static SetupData savePricebooks(
    Id productId,
    List<PricebookInput> rows
  ) {
    validateProduct(productId);
    if (rows == null)
      rows = new List<PricebookInput>();

    Set<Id> pricebookIds = new Set<Id>();
    for (PricebookInput row : rows) {
      if (row != null && row.pricebookId != null)
        pricebookIds.add(row.pricebookId);
    }
    Map<Id, Pricebook2> pricebooks = new Map<Id, Pricebook2>(
      [
        SELECT Id, IsStandard
        FROM Pricebook2
        WHERE Id IN :pricebookIds AND IsActive = TRUE
      ]
    );
    Map<Id, PricebookEntry> existingByPricebook = new Map<Id, PricebookEntry>();
    for (PricebookEntry entry : [
      SELECT Id, Pricebook2Id, UnitPrice, Deposit__c, Payment_type__c, IsActive
      FROM PricebookEntry
      WHERE Product2Id = :productId AND Pricebook2Id IN :pricebookIds
    ]) {
      existingByPricebook.put(entry.Pricebook2Id, entry);
    }

    Boolean standardSelected = false;
    Boolean customSelected = false;
    for (PricebookInput row : rows) {
      if (row == null || row.pricebookId == null || row.selected != true)
        continue;
      Pricebook2 pricebook = pricebooks.get(row.pricebookId);
      if (pricebook == null)
        throw handled('Select an active price book.');
      if (row.unitPrice == null || row.unitPrice < 0) {
        throw handled(
          'Enter a non-negative list price for every selected price book.'
        );
      }
      if (
        row.paymentType == 'Deposit' &&
        (row.deposit == null ||
        row.deposit <= 0)
      ) {
        throw handled(
          'Enter a deposit greater than zero when Payment Type is Deposit.'
        );
      }
      if (pricebook.IsStandard)
        standardSelected = true;
      else
        customSelected = true;
    }
    if (customSelected && !standardSelected) {
      throw handled(
        'Add the product to the Standard Price Book before using custom price books.'
      );
    }

    List<PricebookEntry> standardInserts = new List<PricebookEntry>();
    List<PricebookEntry> customInserts = new List<PricebookEntry>();
    List<PricebookEntry> updates = new List<PricebookEntry>();
    for (PricebookInput row : rows) {
      if (row == null || row.pricebookId == null)
        continue;
      Pricebook2 pricebook = pricebooks.get(row.pricebookId);
      if (pricebook == null)
        continue;
      PricebookEntry existing = existingByPricebook.get(row.pricebookId);
      if (row.selected == true) {
        if (existing == null) {
          PricebookEntry created = new PricebookEntry(
            Product2Id = productId,
            Pricebook2Id = row.pricebookId,
            UnitPrice = row.unitPrice,
            Deposit__c = row.deposit,
            Payment_type__c = row.paymentType,
            IsActive = true,
            UseStandardPrice = false
          );
          if (pricebook.IsStandard)
            standardInserts.add(created);
          else
            customInserts.add(created);
        } else {
          existing.UnitPrice = row.unitPrice;
          existing.Deposit__c = row.deposit;
          existing.Payment_type__c = row.paymentType;
          existing.IsActive = true;
          existing.UseStandardPrice = false;
          updates.add(existing);
        }
      } else if (existing != null && existing.IsActive) {
        existing.IsActive = false;
        updates.add(existing);
      }
    }
    if (!standardInserts.isEmpty())
      insert standardInserts;
    if (!customInserts.isEmpty())
      insert customInserts;
    if (!updates.isEmpty())
      update updates;
    return getSetup(productId);
  }

  @AuraEnabled
  public static SetupData saveRequirements(
    Id productId,
    List<RequirementInput> rows
  ) {
    validateProduct(productId);
    if (rows == null)
      rows = new List<RequirementInput>();

    Set<Id> incomingIds = new Set<Id>();
    Set<Id> templateIds = new Set<Id>();
    for (RequirementInput row : rows) {
      if (row == null)
        continue;
      if (row.id != null)
        incomingIds.add(row.id);
      if (row.templateId != null)
        templateIds.add(row.templateId);
    }
    Map<Id, Product_Document_Requirement__c> existing = new Map<Id, Product_Document_Requirement__c>(
      [
        SELECT Id, Product__c
        FROM Product_Document_Requirement__c
        WHERE Product__c = :productId
      ]
    );
    for (Id rowId : incomingIds) {
      if (!existing.containsKey(rowId))
        throw handled(
          'A document requirement does not belong to this product.'
        );
    }
    Map<Id, Document_Template__c> templates = new Map<Id, Document_Template__c>(
      [
        SELECT
          Id,
          Name,
          Short_Description__c,
          Accepted_Format__c,
          Instructions__c,
          Object_Api_Name__c
        FROM Document_Template__c
        WHERE Id IN :templateIds
      ]
    );

    List<Product_Document_Requirement__c> saves = new List<Product_Document_Requirement__c>();
    Integer position = 0;
    for (RequirementInput row : rows) {
      if (row == null)
        continue;
      position++;
      Document_Template__c template = row.templateId == null
        ? null
        : templates.get(row.templateId);
      if (row.templateId != null && template == null)
        throw handled('Select an available document template.');
      if (
        template != null &&
        template.Object_Api_Name__c != null &&
        template.Object_Api_Name__c != 'Case'
      ) {
        throw handled(
          'Product document templates must be available for Case records.'
        );
      }
      String name = String.isBlank(row.name) && template != null
        ? template.Name
        : row.name;
      if (String.isBlank(name))
        throw handled('Enter a name for every required document.');

      Product_Document_Requirement__c requirement = new Product_Document_Requirement__c(
        Id = row.id,
        Product__c = productId,
        Name = name.trim(),
        Document_Template__c = row.templateId,
        Short_Description__c = valueOrTemplate(
          row.shortDescription,
          template == null ? null : template.Short_Description__c
        ),
        Accepted_Format__c = valueOrTemplate(
          row.acceptedFormat,
          template == null ? null : template.Accepted_Format__c
        ),
        Instructions__c = valueOrTemplate(
          row.instructions,
          template == null ? null : template.Instructions__c
        ),
        Active__c = row.active != false,
        Sort_Order__c = position
      );
      saves.add(requirement);
    }
    if (!saves.isEmpty())
      upsert saves;

    List<Product_Document_Requirement__c> removals = new List<Product_Document_Requirement__c>();
    for (Product_Document_Requirement__c requirement : existing.values()) {
      if (!incomingIds.contains(requirement.Id))
        removals.add(requirement);
    }
    if (!removals.isEmpty())
      delete removals;
    return getSetup(productId);
  }

  private static List<PricebookRow> buildPricebookRows(Id productId) {
    Map<Id, PricebookEntry> entries = new Map<Id, PricebookEntry>();
    for (PricebookEntry entry : [
      SELECT Id, Pricebook2Id, UnitPrice, Deposit__c, Payment_type__c, IsActive
      FROM PricebookEntry
      WHERE Product2Id = :productId
    ]) {
      entries.put(entry.Pricebook2Id, entry);
    }
    List<PricebookRow> rows = new List<PricebookRow>();
    for (Pricebook2 pricebook : [
      SELECT Id, Name, IsStandard
      FROM Pricebook2
      WHERE IsActive = TRUE
      ORDER BY IsStandard DESC, Name
    ]) {
      PricebookEntry entry = entries.get(pricebook.Id);
      PricebookRow row = new PricebookRow();
      row.pricebookId = pricebook.Id;
      row.pricebookName = pricebook.Name;
      row.isStandard = pricebook.IsStandard;
      row.pricebookEntryId = entry?.Id;
      row.selected = entry?.IsActive == true;
      row.unitPrice = entry?.UnitPrice;
      row.deposit = entry?.Deposit__c;
      row.paymentType = entry?.Payment_type__c;
      row.isActive = entry?.IsActive == true;
      rows.add(row);
    }
    return rows;
  }

  private static List<TemplateRow> buildTemplateRows() {
    List<TemplateRow> rows = new List<TemplateRow>();
    for (Document_Template__c template : [
      SELECT
        Id,
        Name,
        Short_Description__c,
        Accepted_Format__c,
        Instructions__c,
        Active__c
      FROM Document_Template__c
      WHERE Object_Api_Name__c = NULL OR Object_Api_Name__c = 'Case'
      ORDER BY Name
    ]) {
      TemplateRow row = new TemplateRow();
      row.id = template.Id;
      row.name = template.Name;
      row.shortDescription = template.Short_Description__c;
      row.acceptedFormat = template.Accepted_Format__c;
      row.instructions = template.Instructions__c;
      row.active = template.Active__c;
      rows.add(row);
    }
    return rows;
  }

  private static List<RequirementRow> buildRequirementRows(Id productId) {
    List<RequirementRow> rows = new List<RequirementRow>();
    for (Product_Document_Requirement__c requirement : [
      SELECT
        Id,
        Name,
        Document_Template__c,
        Short_Description__c,
        Accepted_Format__c,
        Instructions__c,
        Active__c,
        Sort_Order__c
      FROM Product_Document_Requirement__c
      WHERE Product__c = :productId
      ORDER BY Sort_Order__c, CreatedDate
    ]) {
      RequirementRow row = new RequirementRow();
      row.id = requirement.Id;
      row.name = requirement.Name;
      row.templateId = requirement.Document_Template__c;
      row.shortDescription = requirement.Short_Description__c;
      row.acceptedFormat = requirement.Accepted_Format__c;
      row.instructions = requirement.Instructions__c;
      row.active = requirement.Active__c;
      row.sortOrder = requirement.Sort_Order__c == null
        ? null
        : Integer.valueOf(requirement.Sort_Order__c);
      rows.add(row);
    }
    return rows;
  }

  private static void validateProduct(Id productId) {
    if (
      productId == null ||
      productId.getSObjectType() != Product2.SObjectType
    ) {
      throw handled('Product Id is required.');
    }
    if ([SELECT COUNT() FROM Product2 WHERE Id = :productId] == 0) {
      throw handled('Product was not found.');
    }
  }

  private static String valueOrTemplate(String value, String templateValue) {
    return String.isBlank(value) ? templateValue : value;
  }

  private static AuraHandledException handled(String message) {
    return new AuraHandledException(message);
  }
}
