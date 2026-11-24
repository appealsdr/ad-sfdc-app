public with sharing class PricebookEntryTableController {
  private static final List<String> DEFAULT_FIELDS = new List<String>{
    'Product2Id',
    'UnitPrice',
    'IsActive',
    'Deposit__c',
    'Payment_type__c'
  };
  private static final Integer MAX_ROWS = 1000;

  @AuraEnabled(cacheable=true)
  public static ViewModel getEntries(Id pricebookId, String fieldSetName) {
    if (
      pricebookId == null ||
      pricebookId.getSObjectType() != Pricebook2.SObjectType
    ) {
      throw new AuraHandledException('A valid Price Book record is required.');
    }
    if (!canViewEntries()) {
      throw new AuraHandledException(
        'You do not have access to this Price Book and its entries.'
      );
    }

    ViewModel result = new ViewModel();
    result.canCreateEntries = canCreateEntries();
    result.canUpdateEntries = canUpdateEntries();
    result.canDeleteEntries = canDeleteEntries();
    result.fields = resolveFields(fieldSetName, result);
    result.rows = new List<Row>();
    result.paymentTypes = new List<String>();
    if (
      Schema.sObjectType.PricebookEntry.fields.Payment_type__c.isAccessible()
    ) {
      for (
        Schema.PicklistEntry option : PricebookEntry.Payment_type__c.getDescribe()
          .getPicklistValues()
      ) {
        if (option.isActive()) {
          result.paymentTypes.add(option.getValue());
        }
      }
    }

    if (result.fields.isEmpty()) {
      result.warning = appendWarning(
        result.warning,
        'No readable Price Book Entry fields are available.'
      );
      return result;
    }

    List<String> selectFields = new List<String>{ 'Id' };
    for (FieldDescriptor field : result.fields) {
      selectFields.add(field.apiName);
      if (field.displayPath != null) {
        selectFields.add(field.displayPath);
      }
    }

    String query =
      'SELECT ' +
      String.join(selectFields, ',') +
      ' FROM PricebookEntry WHERE Pricebook2Id = :pricebookId ORDER BY Id LIMIT ' +
      MAX_ROWS;
    List<PricebookEntry> entries = (List<PricebookEntry>) Database.query(
      query,
      AccessLevel.USER_MODE
    );

    for (PricebookEntry entry : entries) {
      Row row = new Row();
      row.id = entry.Id;
      row.values = new Map<String, Object>();
      for (FieldDescriptor field : result.fields) {
        Object value = entry.get(field.apiName);
        if (field.apiName == 'Product2Id') {
          row.productId = (Id) value;
        }
        if (field.displayPath != null) {
          SObject relatedRecord = entry.getSObject(field.relationshipName);
          value = relatedRecord == null ? null : relatedRecord.get('Name');
        }
        row.values.put(field.apiName, value);
      }
      result.rows.add(row);
    }

    result.rowLimitReached = entries.size() == MAX_ROWS;
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static List<ProductOption> getAvailableProducts(Id pricebookId) {
    validatePricebookId(pricebookId);
    requireCreateAccess();
    Id standardPricebookId = getStandardPricebookId();
    Set<Id> existingProductIds = new Set<Id>();
    for (PricebookEntry existing : [
      SELECT Product2Id
      FROM PricebookEntry
      WHERE Pricebook2Id = :pricebookId
      WITH USER_MODE
    ]) {
      existingProductIds.add(existing.Product2Id);
    }
    List<ProductOption> options = new List<ProductOption>();
    for (PricebookEntry standardEntry : [
      SELECT Product2Id, Product2.Name, Product2.ProductCode, UnitPrice
      FROM PricebookEntry
      WHERE
        Pricebook2Id = :standardPricebookId
        AND IsActive = TRUE
        AND Product2.IsActive = TRUE
        AND Product2Id NOT IN :existingProductIds
      WITH USER_MODE
      ORDER BY Product2.Name
      LIMIT 1000
    ]) {
      ProductOption option = new ProductOption();
      option.productId = standardEntry.Product2Id;
      option.productName = standardEntry.Product2.Name;
      option.productCode = standardEntry.Product2.ProductCode;
      option.standardPrice = standardEntry.UnitPrice;
      options.add(option);
    }
    return options;
  }

  @AuraEnabled
  public static void addProducts(Id pricebookId, List<Id> productIds) {
    validatePricebookId(pricebookId);
    requireCreateAccess();
    Pricebook2 targetPricebook = [
      SELECT IsStandard
      FROM Pricebook2
      WHERE Id = :pricebookId
      WITH USER_MODE
    ];
    if (targetPricebook.IsStandard) {
      throw new AuraHandledException(
        'Use Salesforce Add Products to create Standard Price Book entries.'
      );
    }
    if (productIds == null || productIds.isEmpty()) {
      throw new AuraHandledException('Select at least one Product to add.');
    }
    Set<Id> requestedProductIds = new Set<Id>(productIds);
    Id standardPricebookId = getStandardPricebookId();
    Map<Id, Decimal> standardPrices = new Map<Id, Decimal>();
    for (PricebookEntry standardEntry : [
      SELECT Product2Id, UnitPrice
      FROM PricebookEntry
      WHERE
        Pricebook2Id = :standardPricebookId
        AND IsActive = TRUE
        AND Product2Id IN :requestedProductIds
      WITH USER_MODE
    ]) {
      standardPrices.put(standardEntry.Product2Id, standardEntry.UnitPrice);
    }
    if (standardPrices.size() != requestedProductIds.size()) {
      throw new AuraHandledException(
        'Every selected Product must have an active Standard Price Book entry.'
      );
    }
    Set<Id> existingProductIds = new Set<Id>();
    for (PricebookEntry existing : [
      SELECT Product2Id
      FROM PricebookEntry
      WHERE Pricebook2Id = :pricebookId AND Product2Id IN :requestedProductIds
      WITH USER_MODE
    ]) {
      existingProductIds.add(existing.Product2Id);
    }
    List<PricebookEntry> entries = new List<PricebookEntry>();
    for (Id productId : requestedProductIds) {
      if (existingProductIds.contains(productId)) {
        continue;
      }
      entries.add(
        new PricebookEntry(
          Pricebook2Id = pricebookId,
          Product2Id = productId,
          UnitPrice = standardPrices.get(productId),
          IsActive = true,
          UseStandardPrice = false
        )
      );
    }
    if (!entries.isEmpty()) {
      Database.insert(entries, AccessLevel.USER_MODE);
    }
  }

  @AuraEnabled
  public static void saveEntries(Id pricebookId, List<EntryUpdate> updates) {
    validatePricebookId(pricebookId);
    requireUpdateAccess();
    if (updates == null || updates.isEmpty()) {
      return;
    }
    Set<Id> entryIds = new Set<Id>();
    for (EntryUpdate item : updates) {
      if (item != null && item.entryId != null) {
        entryIds.add(item.entryId);
      }
    }
    Map<Id, PricebookEntry> existingById = new Map<Id, PricebookEntry>(
      [
        SELECT Id
        FROM PricebookEntry
        WHERE Id IN :entryIds AND Pricebook2Id = :pricebookId
        WITH USER_MODE
      ]
    );
    if (existingById.size() != entryIds.size()) {
      throw new AuraHandledException(
        'One or more Price Book Entries are unavailable for editing.'
      );
    }
    List<PricebookEntry> records = new List<PricebookEntry>();
    for (EntryUpdate item : updates) {
      if (item == null || item.entryId == null) {
        continue;
      }
      if (String.isBlank(item.paymentType)) {
        throw new AuraHandledException(
          'Select a Payment Type for every Price Book Entry.'
        );
      }
      if (
        item.paymentType == 'Deposit' &&
        (item.deposit == null ||
        item.deposit <= 0)
      ) {
        throw new AuraHandledException(
          'Enter a deposit greater than zero when Payment Type is Deposit.'
        );
      }
      records.add(
        new PricebookEntry(
          Id = item.entryId,
          UnitPrice = item.unitPrice,
          IsActive = item.active,
          Deposit__c = item.deposit,
          Payment_type__c = item.paymentType
        )
      );
    }
    if (!records.isEmpty()) {
      Database.update(records, AccessLevel.USER_MODE);
    }
  }

  @AuraEnabled
  public static void deleteEntry(Id pricebookId, Id entryId) {
    validatePricebookId(pricebookId);
    requireDeleteAccess();
    if (
      entryId == null ||
      entryId.getSObjectType() != PricebookEntry.SObjectType
    ) {
      throw new AuraHandledException(
        'A valid Price Book Entry record is required.'
      );
    }
    List<PricebookEntry> entries = [
      SELECT Id
      FROM PricebookEntry
      WHERE Id = :entryId AND Pricebook2Id = :pricebookId
      WITH USER_MODE
      LIMIT 1
    ];
    if (entries.isEmpty()) {
      throw new AuraHandledException(
        'The Price Book Entry is unavailable for deletion.'
      );
    }
    Database.delete(entries[0], AccessLevel.USER_MODE);
  }

  private static void validatePricebookId(Id pricebookId) {
    if (
      pricebookId == null ||
      pricebookId.getSObjectType() != Pricebook2.SObjectType
    ) {
      throw new AuraHandledException('A valid Price Book record is required.');
    }
  }

  private static Boolean canViewEntries() {
    return Schema.sObjectType.Pricebook2.isAccessible() &&
      Schema.sObjectType.PricebookEntry.isAccessible();
  }

  private static Boolean canCreateEntries() {
    return canViewEntries() &&
      Schema.sObjectType.Product2.isAccessible() &&
      Schema.sObjectType.PricebookEntry.isCreateable() &&
      PricebookEntry.Pricebook2Id.getDescribe().isCreateable() &&
      PricebookEntry.Product2Id.getDescribe().isCreateable() &&
      PricebookEntry.UnitPrice.getDescribe().isCreateable() &&
      PricebookEntry.IsActive.getDescribe().isCreateable() &&
      PricebookEntry.UseStandardPrice.getDescribe().isCreateable();
  }

  private static Boolean canUpdateEntries() {
    return canViewEntries() &&
      Schema.sObjectType.PricebookEntry.isUpdateable() &&
      PricebookEntry.UnitPrice.getDescribe().isUpdateable() &&
      PricebookEntry.IsActive.getDescribe().isUpdateable() &&
      PricebookEntry.Deposit__c.getDescribe().isUpdateable() &&
      PricebookEntry.Payment_type__c.getDescribe().isUpdateable();
  }

  private static Boolean canDeleteEntries() {
    return canViewEntries() && Schema.sObjectType.PricebookEntry.isDeletable();
  }

  private static void requireCreateAccess() {
    if (!canCreateEntries()) {
      throw new AuraHandledException(
        'You do not have permission to add Price Book Entries.'
      );
    }
  }

  private static void requireUpdateAccess() {
    if (!canUpdateEntries()) {
      throw new AuraHandledException(
        'You do not have permission to modify Price Book Entries.'
      );
    }
  }

  private static void requireDeleteAccess() {
    if (!canDeleteEntries()) {
      throw new AuraHandledException(
        'You do not have permission to delete Price Book Entries.'
      );
    }
  }

  private static Id getStandardPricebookId() {
    if (Test.isRunningTest()) {
      return Test.getStandardPricebookId();
    }
    return [
      SELECT Id
      FROM Pricebook2
      WHERE IsStandard = TRUE
      LIMIT 1
    ]
    .Id;
  }

  private static List<FieldDescriptor> resolveFields(
    String fieldSetName,
    ViewModel result
  ) {
    List<String> requestedFields = new List<String>();
    String normalizedName = String.isBlank(fieldSetName)
      ? null
      : fieldSetName.trim();

    if (normalizedName != null) {
      Schema.FieldSet configuredFieldSet = Schema.sObjectType.PricebookEntry.fieldSets
        .getMap()
        .get(normalizedName);
      if (configuredFieldSet == null) {
        result.warning =
          'The Price Book Entry field set "' +
          normalizedName.escapeHtml4() +
          '" was not found. Default fields are shown instead.';
      } else {
        for (Schema.FieldSetMember member : configuredFieldSet.getFields()) {
          requestedFields.add(member.getFieldPath());
        }
      }
    }

    if (requestedFields.isEmpty()) {
      requestedFields.addAll(DEFAULT_FIELDS);
      result.usingDefaultFields = true;
    }

    Map<String, Schema.SObjectField> fieldMap = Schema.sObjectType.PricebookEntry.fields.getMap();
    List<FieldDescriptor> fields = new List<FieldDescriptor>();
    List<String> skippedFields = new List<String>();

    for (String fieldPath : requestedFields) {
      if (fieldPath.contains('.') || !fieldMap.containsKey(fieldPath)) {
        skippedFields.add(fieldPath);
        continue;
      }

      Schema.DescribeFieldResult describe = fieldMap.get(fieldPath)
        .getDescribe();
      if (!describe.isAccessible()) {
        skippedFields.add(fieldPath);
        continue;
      }

      FieldDescriptor descriptor = new FieldDescriptor();
      descriptor.apiName = fieldPath;
      descriptor.label = describe.getLabel();
      descriptor.dataType = String.valueOf(describe.getType()).toLowerCase();
      descriptor.editable = describe.isUpdateable();

      if (describe.getType() == Schema.DisplayType.Reference) {
        descriptor.relationshipName = describe.getRelationshipName();
        List<Schema.SObjectType> referenceTypes = describe.getReferenceTo();
        if (
          descriptor.relationshipName != null &&
          referenceTypes.size() == 1 &&
          isNameFieldAccessible(referenceTypes[0])
        ) {
          descriptor.displayPath = descriptor.relationshipName + '.Name';
        }
      }
      fields.add(descriptor);
    }

    if (!skippedFields.isEmpty()) {
      result.warning = appendWarning(
        result.warning,
        'Fields unavailable because of configuration or field-level security: ' +
          String.join(skippedFields, ', ') +
          '.'
      );
    }
    return fields;
  }

  private static Boolean isNameFieldAccessible(Schema.SObjectType objectType) {
    Map<String, Schema.SObjectField> relatedFields = objectType.getDescribe()
      .fields.getMap();
    return relatedFields.containsKey('Name') &&
      relatedFields.get('Name').getDescribe().isAccessible();
  }

  private static String appendWarning(String existingWarning, String warning) {
    return String.isBlank(existingWarning)
      ? warning
      : existingWarning + ' ' + warning;
  }

  public class ViewModel {
    @AuraEnabled
    public List<FieldDescriptor> fields;
    @AuraEnabled
    public List<Row> rows;
    @AuraEnabled
    public String warning;
    @AuraEnabled
    public Boolean usingDefaultFields = false;
    @AuraEnabled
    public Boolean rowLimitReached = false;
    @AuraEnabled
    public List<String> paymentTypes;
    @AuraEnabled
    public Boolean canCreateEntries = false;
    @AuraEnabled
    public Boolean canUpdateEntries = false;
    @AuraEnabled
    public Boolean canDeleteEntries = false;
  }

  public class FieldDescriptor {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String dataType;
    @AuraEnabled
    public Boolean editable;
    @AuraEnabled
    public String relationshipName;
    @AuraEnabled
    public String displayPath;
  }

  public class Row {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id productId;
    @AuraEnabled
    public Map<String, Object> values;
  }

  public class ProductOption {
    @AuraEnabled
    public Id productId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public String productCode;
    @AuraEnabled
    public Decimal standardPrice;
  }

  public class EntryUpdate {
    @AuraEnabled
    public Id entryId;
    @AuraEnabled
    public Decimal unitPrice;
    @AuraEnabled
    public Boolean active;
    @AuraEnabled
    public Decimal deposit;
    @AuraEnabled
    public String paymentType;
  }
}
