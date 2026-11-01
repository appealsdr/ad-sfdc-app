/**
 * Backs the relatedOpportunities LWC shown on Case and CSM_Call__c record pages:
 * lists Opportunities linked through Opportunity.Case__c / Opportunity.CSM_Call__c
 * and creates a new upsell Opportunity with products in one step.
 *
 * Defaults for a new Opportunity are applied here (not in the browser):
 *   Case__c / CSM_Call__c  -> the current record
 *   AccountId              -> Case.AccountId / CSM_Call__c.Account__c
 *   Type                   -> 'Technician Upsell' (Case) / 'CSM Upsell' (CSM Call)
 *   StageName ("Status")   -> 'New'
 *   CloseDate ("Start Date") -> today
 *   Pricebook2Id           -> price book named in the component config (default "Service")
 *   ForecastCategoryName   -> 'Pipeline'
 *   Store__c               -> chosen by the user from the Account's stores (same rule as the
 *                             Opportunity.Store__c lookup filter); preselected from Case.Store__c;
 *                             required whenever the Account has at least one store
 *   Description            -> entered by the user (required)
 */
public with sharing class RelatedOpportunitiesController {

    public class RelatedOpportunitiesException extends Exception {}

    @TestVisible private static final String STAGE_NEW = 'New';
    @TestVisible private static final String FORECAST_PIPELINE = 'Pipeline';
    @TestVisible private static final String TYPE_CASE = 'Technician Upsell';
    @TestVisible private static final String TYPE_CSM_CALL = 'CSM Upsell';

    public class SourceContext {
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String sourceName;     // Case number or CSM Call name
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String opportunityType;
        @AuraEnabled public String stageName = STAGE_NEW;
        @AuraEnabled public String forecastCategory = FORECAST_PIPELINE;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Id pricebookId;
        @AuraEnabled public String pricebookName;
        @AuraEnabled public String defaultOpportunityName;
        @AuraEnabled public Id defaultStoreId;
        @AuraEnabled public List<StoreOption> stores = new List<StoreOption>();
    }

    public class StoreOption {
        @AuraEnabled public Id storeId;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public String sellerId;
        @AuraEnabled public String status;
        @AuraEnabled public String marketplaces;
    }

    public class ProductOption {
        @AuraEnabled public Id pricebookEntryId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public String family;
        @AuraEnabled public Decimal unitPrice;
    }

    public class LineInput {
        @AuraEnabled public Id pricebookEntryId { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
    }

    // ---------------------------------------------------------------- reads

    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunities(Id recordId) {
        String lookup = lookupField(recordId);
        return Database.query(
            'SELECT Id, Name, StageName, Type, Amount, CloseDate, ForecastCategoryName, Owner.Name, CreatedDate'
            + ' FROM Opportunity WHERE ' + lookup + ' = :recordId'
            + ' WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 200'
        );
    }

    @AuraEnabled(cacheable=true)
    public static SourceContext getContext(Id recordId, String pricebookName) {
        lookupField(recordId); // validates the object type
        SourceContext ctx = new SourceContext();
        ctx.startDate = Date.today();

        if (recordId.getSobjectType() == Case.SObjectType) {
            Case c = [SELECT CaseNumber, AccountId, Account.Name, Store__c FROM Case WHERE Id = :recordId WITH USER_MODE];
            ctx.objectLabel = 'Case';
            ctx.sourceName = c.CaseNumber;
            ctx.accountId = c.AccountId;
            ctx.accountName = c.Account?.Name;
            ctx.opportunityType = TYPE_CASE;
            ctx.defaultStoreId = c.Store__c;
        } else {
            CSM_Call__c call = [SELECT Name, Account__c, Account__r.Name FROM CSM_Call__c WHERE Id = :recordId WITH USER_MODE];
            ctx.objectLabel = 'CSM Call';
            ctx.sourceName = call.Name;
            ctx.accountId = call.Account__c;
            ctx.accountName = call.Account__r?.Name;
            ctx.opportunityType = TYPE_CSM_CALL;
        }

        ctx.stores = storesFor(ctx.accountId);
        if (ctx.defaultStoreId != null && !containsStore(ctx.stores, ctx.defaultStoreId)) {
            ctx.defaultStoreId = null; // Case store belongs to another account; the lookup filter would reject it
        }

        Pricebook2 pb = findPricebook(pricebookName);
        ctx.pricebookId = pb.Id;
        ctx.pricebookName = pb.Name;
        ctx.defaultOpportunityName = defaultName(ctx);
        return ctx;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductOption> getProducts(String pricebookName) {
        Pricebook2 pb = findPricebook(pricebookName);
        List<ProductOption> result = new List<ProductOption>();
        for (PricebookEntry pbe : [
            SELECT Id, UnitPrice, Product2.Name, Product2.ProductCode, Product2.Family
            FROM PricebookEntry
            WHERE Pricebook2Id = :pb.Id AND IsActive = true AND Product2.IsActive = true
            WITH USER_MODE
            ORDER BY Product2.Name
            LIMIT 1000
        ]) {
            ProductOption o = new ProductOption();
            o.pricebookEntryId = pbe.Id;
            o.productName = pbe.Product2.Name;
            o.productCode = pbe.Product2.ProductCode;
            o.family = pbe.Product2.Family;
            o.unitPrice = pbe.UnitPrice;
            result.add(o);
        }
        return result;
    }

    // ---------------------------------------------------------------- create

    @AuraEnabled
    public static Id createOpportunity(
        Id recordId, String pricebookName, String opportunityName, Id storeId, String description, List<LineInput> lines
    ) {
        if (String.isBlank(description)) {
            throw new AuraHandledException('Enter a description for this Opportunity.');
        }
        if (lines == null || lines.isEmpty()) {
            throw new AuraHandledException('Select at least one product.');
        }
        SourceContext ctx = getContext(recordId, pricebookName);
        if (ctx.accountId == null) {
            throw new AuraHandledException('This ' + ctx.objectLabel + ' has no Account, so an Opportunity cannot be created.');
        }
        if (storeId == null && !ctx.stores.isEmpty()) {
            throw new AuraHandledException('Select a store for this Opportunity.');
        }
        if (storeId != null && !containsStore(ctx.stores, storeId)) {
            throw new AuraHandledException('The selected store does not belong to ' + ctx.accountName + '.');
        }

        // Prices always come from the price book, never from the browser.
        Set<Id> entryIds = new Set<Id>();
        for (LineInput line : lines) {
            if (line.pricebookEntryId == null || line.quantity == null || line.quantity <= 0) {
                throw new AuraHandledException('Every selected product needs a quantity greater than 0.');
            }
            entryIds.add(line.pricebookEntryId);
        }
        Map<Id, PricebookEntry> entries = new Map<Id, PricebookEntry>([
            SELECT Id, UnitPrice FROM PricebookEntry
            WHERE Id IN :entryIds AND Pricebook2Id = :ctx.pricebookId AND IsActive = true
            WITH USER_MODE
        ]);
        if (entries.size() != entryIds.size()) {
            throw new AuraHandledException('One or more products are not active in the ' + ctx.pricebookName + ' price book.');
        }

        Opportunity opp = new Opportunity(
            Name = String.isNotBlank(opportunityName) ? opportunityName.trim().left(120) : ctx.defaultOpportunityName,
            AccountId = ctx.accountId,
            Type = ctx.opportunityType,
            StageName = STAGE_NEW,
            CloseDate = ctx.startDate,
            Pricebook2Id = ctx.pricebookId,
            ForecastCategoryName = FORECAST_PIPELINE,
            Store__c = storeId,
            Description = description.trim().left(32000)
        );
        opp.put(lookupField(recordId), recordId);

        Savepoint sp = Database.setSavepoint();
        try {
            insert as user opp;
            List<OpportunityLineItem> items = new List<OpportunityLineItem>();
            for (LineInput line : lines) {
                items.add(new OpportunityLineItem(
                    OpportunityId = opp.Id,
                    PricebookEntryId = line.pricebookEntryId,
                    Quantity = line.quantity,
                    UnitPrice = entries.get(line.pricebookEntryId).UnitPrice
                ));
            }
            insert as user items;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not create the Opportunity: ' + e.getMessage());
        }
        return opp.Id;
    }

    // ---------------------------------------------------------------- helpers

    @TestVisible
    private static String lookupField(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('No record.');
        }
        Schema.SObjectType t = recordId.getSobjectType();
        if (t == Case.SObjectType) {
            return 'Case__c';
        }
        if (t == CSM_Call__c.SObjectType) {
            return 'CSM_Call__c';
        }
        throw new AuraHandledException('Related Opportunities only works on Case and CSM Call records.');
    }

    private static Pricebook2 findPricebook(String pricebookName) {
        String name = String.isBlank(pricebookName) ? 'Service' : pricebookName.trim();
        List<Pricebook2> books = [
            SELECT Id, Name FROM Pricebook2 WHERE Name = :name AND IsActive = true WITH USER_MODE LIMIT 1
        ];
        if (books.isEmpty()) {
            throw new AuraHandledException('No active price book named "' + name + '".');
        }
        return books[0];
    }

    /** Stores the Opportunity.Store__c lookup filter allows: Store__c.Account__c = Opportunity.AccountId. */
    private static List<StoreOption> storesFor(Id accountId) {
        List<StoreOption> result = new List<StoreOption>();
        if (accountId == null) {
            return result;
        }
        for (Store__c s : [
            SELECT Id, Name, Seller_ID__c, Status__c, Marketplaces__c
            FROM Store__c WHERE Account__c = :accountId
            WITH USER_MODE ORDER BY Name LIMIT 200
        ]) {
            StoreOption o = new StoreOption();
            o.storeId = s.Id;
            o.name = s.Name;
            o.sellerId = s.Seller_ID__c;
            o.status = s.Status__c;
            o.marketplaces = s.Marketplaces__c == null ? null : s.Marketplaces__c.replace(';', ', ');
            List<String> parts = new List<String>{ s.Name };
            if (String.isNotBlank(s.Seller_ID__c)) {
                parts.add(s.Seller_ID__c);
            }
            if (String.isNotBlank(s.Status__c)) {
                parts.add(s.Status__c);
            }
            o.label = String.join(parts, ' · ');
            result.add(o);
        }
        return result;
    }

    private static Boolean containsStore(List<StoreOption> stores, Id storeId) {
        for (StoreOption s : stores) {
            if (s.storeId == storeId) {
                return true;
            }
        }
        return false;
    }

    private static String defaultName(SourceContext ctx) {
        String account = String.isNotBlank(ctx.accountName) ? ctx.accountName : ctx.objectLabel + ' ' + ctx.sourceName;
        return (account + ' - ' + ctx.opportunityType + ' - ' + ctx.startDate.format()).left(120);
    }
}