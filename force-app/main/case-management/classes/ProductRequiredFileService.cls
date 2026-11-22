/**
 * Clones product template Required Files onto newly created Cases.
 * A template is a Required_File__c with Product__c set and no Case__c.
 * Each clone has no Product__c and points back to its template via Source_Required_File__c.
 */
public with sharing class ProductRequiredFileService {
  public static void createForCases(List<Case> cases) {
    if (cases == null || cases.isEmpty())
      return;

    Set<Id> lineItemIds = new Set<Id>();
    for (Case caseRecord : cases) {
      if (caseRecord.Id != null && caseRecord.Contract_Line_Item__c != null) {
        lineItemIds.add(caseRecord.Contract_Line_Item__c);
      }
    }
    if (lineItemIds.isEmpty())
      return;

    Map<Id, Id> productByLineItem = new Map<Id, Id>();
    List<ContractLineItem> lineItems = [
      SELECT Id, PricebookEntry.Product2Id
      FROM ContractLineItem
      WHERE Id IN :lineItemIds
    ];
    for (ContractLineItem lineItem : lineItems) {
      Id productId = lineItem.PricebookEntry?.Product2Id;
      if (productId != null)
        productByLineItem.put(lineItem.Id, productId);
    }
    if (productByLineItem.isEmpty())
      return;

    Map<Id, List<Required_File__c>> templatesByProduct = new Map<Id, List<Required_File__c>>();
    List<Required_File__c> templates = [
      SELECT
        Id,
        Product__c,
        Name,
        Document_Template__c,
        Short_Description__c,
        Accepted_Format__c,
        Instructions__c
      FROM Required_File__c
      WHERE
        Product__c IN :productByLineItem.values()
        AND Case__c = NULL
        AND Active__c = TRUE
      ORDER BY Sort_Order__c, CreatedDate
    ];
    for (Required_File__c template : templates) {
      if (!templatesByProduct.containsKey(template.Product__c)) {
        templatesByProduct.put(template.Product__c, new List<Required_File__c>());
      }
      templatesByProduct.get(template.Product__c).add(template);
    }
    if (templatesByProduct.isEmpty())
      return;

    List<Required_File__c> clones = new List<Required_File__c>();
    for (Case caseRecord : cases) {
      Id productId = productByLineItem.get(caseRecord.Contract_Line_Item__c);
      List<Required_File__c> productTemplates = templatesByProduct.get(productId);
      if (productTemplates == null)
        continue;
      for (Required_File__c template : productTemplates) {
        clones.add(
          new Required_File__c(
            Case__c = caseRecord.Id,
            Source_Required_File__c = template.Id,
            Name = template.Name,
            Document_Template__c = template.Document_Template__c,
            Short_Description__c = template.Short_Description__c,
            Accepted_Format__c = template.Accepted_Format__c,
            Instructions__c = template.Instructions__c
          )
        );
      }
    }
    if (!clones.isEmpty())
      insert clones;
  }
}
