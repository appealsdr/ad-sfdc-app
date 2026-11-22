public with sharing class StoreOpportunityAccountLinkService {
  @TestVisible private static Boolean forceFailure = false;

  private class ForcedTestException extends Exception {}

  public static void populateBlankAccounts(List<Store__c> stores) {
    if (forceFailure) throw new ForcedTestException('Forced test failure');
    Set<Id> opportunityIds = new Set<Id>();
    for (Store__c store : stores) {
      if (store.Account__c == null && store.Opportunity__c != null) {
        opportunityIds.add(store.Opportunity__c);
      }
    }

    if (opportunityIds.isEmpty()) {
      return;
    }

    Map<Id, Opportunity> opportunitiesById = new Map<Id, Opportunity>([
      SELECT AccountId
      FROM Opportunity
      WHERE Id IN :opportunityIds
    ]);
    for (Store__c store : stores) {
      Opportunity opportunity = opportunitiesById.get(store.Opportunity__c);
      if (
        store.Account__c == null &&
        opportunity != null &&
        opportunity.AccountId != null
      ) {
        store.Account__c = opportunity.AccountId;
      }
    }
  }
}
