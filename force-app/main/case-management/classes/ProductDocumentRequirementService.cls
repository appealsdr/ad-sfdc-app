public with sharing class ProductDocumentRequirementService {
  public static void createForCases(List<Case> cases) {
    if (cases == null || cases.isEmpty())
      return;

    Set<Id> contractLineItemIds = new Set<Id>();
    for (Case caseRecord : cases) {
      if (caseRecord.Id != null && caseRecord.Contract_Line_Item__c != null) {
        contractLineItemIds.add(caseRecord.Contract_Line_Item__c);
      }
    }
    if (contractLineItemIds.isEmpty())
      return;

    Map<Id, Id> productByLineItem = new Map<Id, Id>();
    Set<Id> productIds = new Set<Id>();
    for (ContractLineItem lineItem : [
      SELECT Id, PricebookEntry.Product2Id
      FROM ContractLineItem
      WHERE Id IN :contractLineItemIds
    ]) {
      Id productId = lineItem.PricebookEntry.Product2Id;
      productByLineItem.put(lineItem.Id, productId);
      productIds.add(productId);
    }
    if (productIds.isEmpty())
      return;

    Map<Id, List<Product_Document_Requirement__c>> requirementsByProduct = new Map<Id, List<Product_Document_Requirement__c>>();
    for (Product_Document_Requirement__c requirement : [
      SELECT
        Product__c,
        Name,
        Document_Template__c,
        Short_Description__c,
        Accepted_Format__c,
        Instructions__c
      FROM Product_Document_Requirement__c
      WHERE Product__c IN :productIds AND Active__c = TRUE
      ORDER BY Sort_Order__c, CreatedDate
    ]) {
      if (!requirementsByProduct.containsKey(requirement.Product__c)) {
        requirementsByProduct.put(
          requirement.Product__c,
          new List<Product_Document_Requirement__c>()
        );
      }
      requirementsByProduct.get(requirement.Product__c).add(requirement);
    }

    List<Required_File__c> requiredFiles = new List<Required_File__c>();
    for (Case caseRecord : cases) {
      Id productId = productByLineItem.get(caseRecord.Contract_Line_Item__c);
      for (
        Product_Document_Requirement__c requirement : requirementsByProduct.get(
            productId
          ) == null
          ? new List<Product_Document_Requirement__c>()
          : requirementsByProduct.get(productId)
      ) {
        requiredFiles.add(
          new Required_File__c(
            Case__c = caseRecord.Id,
            Name = requirement.Name,
            Document_Template__c = requirement.Document_Template__c,
            Short_Description__c = requirement.Short_Description__c,
            Accepted_Format__c = requirement.Accepted_Format__c,
            Instructions__c = requirement.Instructions__c
          )
        );
      }
    }
    if (!requiredFiles.isEmpty())
      insert requiredFiles;
  }
}
