@IsTest
private class StoreOpportunityAccountLinkTest {
  @TestSetup
  static void setupData() {
    Account first = new Account(Name = 'Store Link Account A');
    Account second = new Account(Name = 'Store Link Account B');
    insert new List<Account>{ first, second };
    insert new List<Opportunity>{
      new Opportunity(
        Name = 'Store Link Opportunity A',
        AccountId = first.Id,
        StageName = 'Meeting Booked',
        CloseDate = Date.today().addDays(30)
      ),
      new Opportunity(
        Name = 'Store Link Opportunity B',
        AccountId = second.Id,
        StageName = 'Meeting Booked',
        CloseDate = Date.today().addDays(30)
      ),
      new Opportunity(
        Name = 'Store Link Opportunity Without Account',
        StageName = 'Meeting Booked',
        CloseDate = Date.today().addDays(30)
      )
    };
  }

  @IsTest
  static void creatingStoreFromOpportunityLinksItsAccount() {
    Opportunity opp = opportunity('Store Link Opportunity A');
    Store__c store = new Store__c(
      Name = 'Linked Store',
      Opportunity__c = opp.Id
    );
    Test.startTest();
    insert store;
    Test.stopTest();
    Assert.areEqual(
      opp.AccountId,
      [SELECT Account__c FROM Store__c WHERE Id = :store.Id].Account__c
    );
  }

  @IsTest
  static void explicitlySelectedAccountIsPreservedOnInsertAndUpdate() {
    Opportunity first = opportunity('Store Link Opportunity A');
    Opportunity second = opportunity('Store Link Opportunity B');
    Store__c store = new Store__c(
      Name = 'Explicit Account Store',
      Opportunity__c = first.Id,
      Account__c = second.AccountId
    );
    insert store;
    Assert.areEqual(
      second.AccountId,
      [SELECT Account__c FROM Store__c WHERE Id = :store.Id].Account__c
    );
    Test.startTest();
    store.Description__c = 'Keep the explicit Account';
    update store;
    Test.stopTest();
    Assert.areEqual(
      second.AccountId,
      [SELECT Account__c FROM Store__c WHERE Id = :store.Id].Account__c
    );
  }

  @IsTest
  static void addingOpportunityLaterFillsBlankAccount() {
    Store__c store = new Store__c(Name = 'Opportunity Added Later');
    insert store;
    Opportunity opp = opportunity('Store Link Opportunity A');
    Test.startTest();
    store.Opportunity__c = opp.Id;
    update store;
    Test.stopTest();
    Assert.areEqual(
      opp.AccountId,
      [SELECT Account__c FROM Store__c WHERE Id = :store.Id].Account__c
    );
  }

  @IsTest
  static void storesWithoutSourceAccountStayBlank() {
    Opportunity opp = opportunity('Store Link Opportunity Without Account');
    List<Store__c> stores = new List<Store__c>{
      new Store__c(Name = 'No Opportunity'),
      new Store__c(
        Name = 'Opportunity Without Account',
        Opportunity__c = opp.Id
      )
    };
    Test.startTest();
    insert stores;
    Test.stopTest();
    Set<Id> storeIds = new Map<Id, Store__c>(stores).keySet();
    for (Store__c saved : [
      SELECT Account__c
      FROM Store__c
      WHERE Id IN :storeIds
    ]) {
      Assert.isNull(saved.Account__c);
    }
  }

  @IsTest
  static void bulkStoreCreationUsesEachOpportunityAccount() {
    Opportunity first = opportunity('Store Link Opportunity A');
    Opportunity second = opportunity('Store Link Opportunity B');
    List<Store__c> stores = new List<Store__c>();
    for (Integer i = 0; i < 200; i++) {
      stores.add(
        new Store__c(
          Name = 'Bulk Linked Store ' + i,
          Opportunity__c = Math.mod(i, 2) == 0 ? first.Id : second.Id
        )
      );
    }
    Test.startTest();
    insert stores;
    Test.stopTest();
    Set<Id> storeIds = new Map<Id, Store__c>(stores).keySet();
    List<Store__c> savedStores = [
      SELECT Opportunity__c, Account__c
      FROM Store__c
      WHERE Id IN :storeIds
    ];
    Assert.areEqual(200, savedStores.size());
    for (Store__c saved : savedStores) {
      Assert.areEqual(
        saved.Opportunity__c == first.Id ? first.AccountId : second.AccountId,
        saved.Account__c
      );
    }
  }

  private static Opportunity opportunity(String name) {
    return [SELECT Id, AccountId FROM Opportunity WHERE Name = :name];
  }
}
