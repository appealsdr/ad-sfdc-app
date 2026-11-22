public class CaseTriggerHandler {

    public static void copyProductOnboardingConfig(List<Case> caseList) {
        if (caseList == null || caseList.isEmpty()) return;

        Set<Id> contractLineItemIds = new Set<Id>();
        for (Case c : caseList) {
            if (c.Contract_Line_Item__c != null) {
                contractLineItemIds.add(c.Contract_Line_Item__c);
            }
        }

        if (contractLineItemIds.isEmpty()) return;

        Map<Id, ContractLineItem> contractLineItems = new Map<Id, ContractLineItem>([
            SELECT Id, PricebookEntry.Product2.Onboarding_Config__c
            FROM ContractLineItem
            WHERE Id IN :contractLineItemIds
        ]);

        for (Case c : caseList) {
            ContractLineItem lineItem = contractLineItems.get(c.Contract_Line_Item__c);
            if (lineItem != null) {
                c.Case_Onboarding__c = lineItem.PricebookEntry.Product2.Onboarding_Config__c;
            }
        }
    }

    /* =====================================================
       Store level Case roll-up
       Total_Cases__c / Total_Open_Cases__c / Total_Closed_Cases__c
    ======================================================*/
    public static void updateStoreCaseCounts(List<Case> caseList, Map<Id, Case> oldMap) {
        if (caseList == null || caseList.isEmpty()) return;

        /* ---------------------------------
           Collect Store Ids (new + old so
           re-parented / deleted Cases are
           recalculated on both sides)
        ----------------------------------*/
        Set<Id> storeIds = new Set<Id>();
        for (Case c : caseList) {
            if (c.Store__c != null) {
                storeIds.add(c.Store__c);
            }
            if (oldMap != null && oldMap.containsKey(c.Id)) {
                Case oldC = oldMap.get(c.Id);
                if (oldC.Store__c != null) {
                    storeIds.add(oldC.Store__c);
                }
            }
        }

        if (storeIds.isEmpty()) return;

        /* ---------------------------------
           Aggregate Cases per Store
        ----------------------------------*/
        Map<Id, Integer> openCount = new Map<Id, Integer>();
        Map<Id, Integer> closedCount = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT Store__c storeId, IsClosed isClosed, COUNT(Id) caseCount
            FROM Case
            WHERE Store__c IN :storeIds
            GROUP BY Store__c, IsClosed
        ]) {
            Id storeId = (Id) ar.get('storeId');
            Integer cnt = (Integer) ar.get('caseCount');

            if ((Boolean) ar.get('isClosed')) {
                closedCount.put(storeId, cnt);
            } else {
                openCount.put(storeId, cnt);
            }
        }

        /* ---------------------------------
           Update Stores (only when changed)
        ----------------------------------*/
        List<Store__c> toUpdate = new List<Store__c>();

        for (Store__c st : [
            SELECT Id, Total_Cases__c, Total_Open_Cases__c, Total_Closed_Cases__c
            FROM Store__c
            WHERE Id IN :storeIds
        ]) {
            Integer opened = openCount.containsKey(st.Id) ? openCount.get(st.Id) : 0;
            Integer closed = closedCount.containsKey(st.Id) ? closedCount.get(st.Id) : 0;
            Integer total = opened + closed;

            if (st.Total_Cases__c != total ||
                st.Total_Open_Cases__c != opened ||
                st.Total_Closed_Cases__c != closed) {

                st.Total_Cases__c = total;
                st.Total_Open_Cases__c = opened;
                st.Total_Closed_Cases__c = closed;
                toUpdate.add(st);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
