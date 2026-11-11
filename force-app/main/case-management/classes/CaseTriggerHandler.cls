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

    public static void updateTotalCases(List<Case> caseList, Map<Id, Case> oldMap) {
        if (caseList == null || caseList.isEmpty()) return;

        /* ---------------------------------
           Collect Store Ids
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
           Store → Opportunity
        ----------------------------------*/
        Map<Id, Id> storeToOpp = new Map<Id, Id>();
        for (Store__c st : [SELECT Id, Opportunity__c FROM Store__c WHERE Id IN :storeIds AND Opportunity__c != null]) {

            storeToOpp.put(st.Id, st.Opportunity__c);
        }

        if (storeToOpp.isEmpty()) return;

        Set<Id> oppIds = new Set<Id>();
        oppIds.addAll(storeToOpp.values());

        /* ---------------------------------
           RecordTypeId → Name
        ----------------------------------*/
        Map<Id, String> rtIdToName = new Map<Id, String>();
        for (RecordType rt : [SELECT Id, Name FROM RecordType WHERE SObjectType = 'Case']) {

            rtIdToName.put(rt.Id, rt.Name);
        }

        /* ---------------------------------
           Fetch Services (Opp based)
        ----------------------------------*/
        Map<Id, Id> serviceToOpp = new Map<Id, Id>();
        for (Service__c s : [SELECT Id, Store__c FROM Service__c WHERE Store__c IN :oppIds]) {
 
            serviceToOpp.put(s.Id, s.Store__c);
        }
        if (serviceToOpp.isEmpty()) return;

        /* ---------------------------------
           Fetch Retainers
        ----------------------------------*/
        List<Retainer_Service__c> retainers = [SELECT Id, Service__c, Case_Record_Type__c,Start_Date__c, End_Date__c,Total_Case__c FROM Retainer_Service__c WHERE Service__c IN :serviceToOpp.keySet()];

        if (retainers.isEmpty()) return;

        /* ---------------------------------
           Fetch ALL relevant cases (date aware)
        ----------------------------------*/
        List<Case> allCases = [SELECT Id, Opportunity__c, RecordTypeId, CreatedDate FROM Case WHERE Opportunity__c IN :oppIds];

        /* ---------------------------------
           Retainer Key → Case Count
        ----------------------------------*/
        Map<Id, Integer> retainerToCount = new Map<Id, Integer>();

        for (Case c : allCases) {

            String rtName = rtIdToName.get(c.RecordTypeId);
            if (rtName == null) continue;

            Date caseDate = c.CreatedDate.date();

            for (Retainer_Service__c rs : retainers) {

                if (rs.Case_Record_Type__c != rtName) continue;
                if (rs.Start_Date__c == null || rs.End_Date__c == null) continue;

                if (caseDate >= rs.Start_Date__c &&
                    caseDate <= rs.End_Date__c &&
                    serviceToOpp.get(rs.Service__c) == c.Opportunity__c) {

                    Integer cnt = retainerToCount.containsKey(rs.Id)
                        ? retainerToCount.get(rs.Id)
                        : 0;

                    retainerToCount.put(rs.Id, cnt + 1);
                }
            }
        }

        /* ---------------------------------
           Update Retainers
        ----------------------------------*/
        List<Retainer_Service__c> toUpdate = new List<Retainer_Service__c>();

        for (Retainer_Service__c rs : retainers) {
            Integer total = retainerToCount.containsKey(rs.Id)
                ? retainerToCount.get(rs.Id)
                : 0;

            if (rs.Total_Case__c != total) {
                rs.Total_Case__c = total;
                toUpdate.add(rs);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
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
