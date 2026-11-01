/** Live case totals for the account being discussed on a CSM Call. */
public with sharing class CSMCaseDashboardController {
    public class Breakdown {
        @AuraEnabled public String caseType;
        @AuraEnabled public String caseTypeValue;
        @AuraEnabled public String categoryValue;
        @AuraEnabled public String category;
        @AuraEnabled public Integer openCount = 0;
        @AuraEnabled public Integer closedCount = 0;
    }

    public class StoreSummary {
        @AuraEnabled public Id storeId;
        @AuraEnabled public String storeName;
        @AuraEnabled public Integer openCount = 0;
        @AuraEnabled public Integer closedCount = 0;
        @AuraEnabled public Integer agingCount = 0;
        @AuraEnabled public Integer overdueCount = 0;
        @AuraEnabled public List<Breakdown> breakdowns = new List<Breakdown>();
        private Map<String, Breakdown> byCategory = new Map<String, Breakdown>();
    }

    public class Dashboard {
        @AuraEnabled public Integer openCount = 0;
        @AuraEnabled public Integer closedCount = 0;
        @AuraEnabled public Integer agingCount = 0;
        @AuraEnabled public Integer overdueCount = 0;
        @AuraEnabled public List<StoreSummary> stores = new List<StoreSummary>();
    }

    @AuraEnabled(cacheable=true)
    public static Dashboard getDashboard(Id callId) {
        Dashboard result = new Dashboard();
        if (callId == null) return result;
        CSM_Call__c call = [SELECT Account__c FROM CSM_Call__c WHERE Id = :callId WITH USER_MODE];
        Map<Id, StoreSummary> byStore = new Map<Id, StoreSummary>();
        for (Store__c store : [
            SELECT Id, Name FROM Store__c WHERE Account__c = :call.Account__c
            WITH USER_MODE ORDER BY Name, Id
        ]) {
            StoreSummary summary = new StoreSummary();
            summary.storeId = store.Id;
            summary.storeName = store.Name;
            byStore.put(store.Id, summary);
            result.stores.add(summary);
        }
        // Include store-linked cases even when the case's AccountId has not been populated.
        Set<Id> storeIds = byStore.keySet();
        for (AggregateResult row : [
            SELECT Store__c storeId, Store__r.Name storeName, Type caseType, Category__c category,
                IsClosed closed, COUNT(Id) quantity
            FROM Case WHERE AccountId = :call.Account__c OR Store__c IN :storeIds
            WITH USER_MODE
            GROUP BY Store__c, Store__r.Name, Type, Category__c, IsClosed
            ORDER BY Store__r.Name, Type, Category__c
        ]) {
            Id storeId = (Id)row.get('storeId');
            if (!byStore.containsKey(storeId)) {
                StoreSummary summary = new StoreSummary();
                summary.storeId = storeId;
                summary.storeName = storeId == null ? 'No store assigned' : (String)row.get('storeName');
                byStore.put(storeId, summary);
                result.stores.add(summary);
            }
            StoreSummary summary = byStore.get(storeId);
            String caseType = (String)row.get('caseType');
            String category = (String)row.get('category');
            String key = JSON.serialize(new List<String>{ caseType, category });
            if (!summary.byCategory.containsKey(key)) {
                Breakdown detail = new Breakdown();
                detail.caseTypeValue = caseType;
                detail.categoryValue = category;
                detail.caseType = String.isBlank(caseType) ? 'Unspecified type' : caseType;
                detail.category = String.isBlank(category) ? 'Unspecified category' : category;
                summary.byCategory.put(key, detail);
                summary.breakdowns.add(detail);
            }
            Breakdown detail = summary.byCategory.get(key);
            Integer quantity = (Integer)row.get('quantity');
            if ((Boolean)row.get('closed')) {
                detail.closedCount += quantity;
                summary.closedCount += quantity;
                result.closedCount += quantity;
            } else {
                detail.openCount += quantity;
                summary.openCount += quantity;
                result.openCount += quantity;
            }
        }
        Datetime agingCutoff = System.now().addDays(-7);
        Datetime overdueCutoff = System.now().addDays(-14);
        for (AggregateResult row : [
            SELECT Store__c storeId, COUNT(Id) quantity
            FROM Case WHERE (AccountId = :call.Account__c OR Store__c IN :storeIds)
                AND IsClosed = false AND CreatedDate < :agingCutoff
            WITH USER_MODE GROUP BY Store__c
        ]) {
            Integer quantity = (Integer)row.get('quantity');
            byStore.get((Id)row.get('storeId')).agingCount = quantity;
            result.agingCount += quantity;
        }
        for (AggregateResult row : [
            SELECT Store__c storeId, COUNT(Id) quantity
            FROM Case WHERE (AccountId = :call.Account__c OR Store__c IN :storeIds)
                AND IsClosed = false AND CreatedDate < :overdueCutoff
            WITH USER_MODE GROUP BY Store__c
        ]) {
            Integer quantity = (Integer)row.get('quantity');
            byStore.get((Id)row.get('storeId')).overdueCount = quantity;
            result.overdueCount += quantity;
        }
        return result;
    }
    /** Contracts are grouped by their explicit store, then the opportunity's store. */
    @AuraEnabled(cacheable=true)
    public static List<ServiceContract> getServiceContracts(Id callId) {
        if (callId == null) return new List<ServiceContract>();
        CSM_Call__c call = [SELECT Account__c FROM CSM_Call__c WHERE Id = :callId WITH USER_MODE];
        Set<Id> storeIds = new Map<Id, Store__c>([
            SELECT Id FROM Store__c WHERE Account__c = :call.Account__c WITH USER_MODE
        ]).keySet();
        return [
            SELECT Id, Name, ContractNumber, Status, StartDate, EndDate, Store__c, Store__r.Name,
                Opportunity__r.Store__c, Opportunity__r.Store__r.Name,
                (SELECT Id, Quantity, PricebookEntry.Product2Id, PricebookEntry.Product2.Name
                 FROM ContractLineItems ORDER BY LineItemNumber)
            FROM ServiceContract
            WHERE AccountId = :call.Account__c OR Store__c IN :storeIds
                OR (Store__c = null AND Opportunity__r.Store__c IN :storeIds)
            WITH USER_MODE ORDER BY StartDate DESC NULLS LAST, Name, Id
        ];
    }

    public class CasePage {
        @AuraEnabled public List<Case> records;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Id nextCursor;
    }

    /** Same account/store scope as the dashboard, with keyset pagination and user permissions. */
    @AuraEnabled
    public static CasePage getCases(Id callId, String metric, Boolean filterStore, Id storeId,
        Boolean filterBreakdown, String caseType, String category, Id afterId) {
        if (callId == null || !new Set<String>{'all', 'open', 'closed', 'aging', 'overdue'}.contains(metric)) {
            throw new AuraHandledException('Select a valid dashboard count.');
        }
        CSM_Call__c call = [SELECT Account__c FROM CSM_Call__c WHERE Id = :callId WITH USER_MODE];
        Set<Id> storeIds = new Map<Id, Store__c>([
            SELECT Id FROM Store__c WHERE Account__c = :call.Account__c WITH USER_MODE
        ]).keySet();
        Map<String, Object> binds = new Map<String, Object>{
            'accountId' => call.Account__c, 'storeIds' => storeIds,
            'storeId' => storeId, 'caseType' => caseType, 'category' => category, 'afterId' => afterId
        };
        String query = 'SELECT Id, CaseNumber, Subject, Status, Priority, CreatedDate, Type, Category__c, '
            + 'Store__r.Name, Owner.Name, ServiceContractId, ServiceContract.Name, Contract__c, Contract__r.Name, '
            + 'Contract_Line_Item__r.ServiceContractId, Contract_Line_Item__r.ServiceContract.Name, '
            + 'Contract_Line_Item__r.PricebookEntry.Product2.Name, Contract_Line_Item__r.Quantity FROM Case WHERE (AccountId = :accountId OR Store__c IN :storeIds)';
        if (filterStore == true) query += ' AND Store__c = :storeId';
        if (filterBreakdown == true) query += ' AND Type = :caseType AND Category__c = :category';
        if (metric == 'closed') query += ' AND IsClosed = true';
        else if (metric != 'all') query += ' AND IsClosed = false';
        if (metric == 'aging' || metric == 'overdue') {
            binds.put('cutoff', System.now().addDays(metric == 'aging' ? -7 : -14));
            query += ' AND CreatedDate < :cutoff';
        }
        if (afterId != null) query += ' AND Id > :afterId';
        query += ' ORDER BY Id ASC LIMIT 101';
        CasePage page = new CasePage();
        page.records = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        page.hasMore = page.records.size() > 100;
        if (page.hasMore) page.records.remove(100);
        page.nextCursor = page.records.isEmpty() ? null : page.records[page.records.size() - 1].Id;
        return page;
    }

}