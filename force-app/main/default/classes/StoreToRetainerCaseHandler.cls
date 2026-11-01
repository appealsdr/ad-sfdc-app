public with sharing class StoreToRetainerCaseHandler {
    
    public static void validateCaseLimit(List<Case> newList, Map<Id, Case> oldMap) {
        if (newList == null || newList.isEmpty()) return;
        
        /* -------------------------------
Collect Store Ids
--------------------------------*/
        Set<Id> storeIds = new Set<Id>();
        for (Case c : newList) {
            if (c.Store__c != null && c.RecordTypeId != null) {
                storeIds.add(c.Store__c);
            }
        }
        if (storeIds.isEmpty()) return;
        
        /* -------------------------------
Store → Opportunity Map
--------------------------------*/
        Map<Id, Id> storeToOpp = new Map<Id, Id>();
        for (Store__c st : [SELECT Id, Opportunity__c FROM Store__c WHERE Id IN :storeIds]) {
            if (st.Opportunity__c != null) {
                storeToOpp.put(st.Id, st.Opportunity__c);
            }
        }
        if (storeToOpp.isEmpty()) return;
        
        Set<Id> oppIds = new Set<Id>();
        oppIds.addAll(storeToOpp.values());
        
        /* -------------------------------
RecordType Id → Name
--------------------------------*/
        Map<Id, String> rtIdToName = new Map<Id, String>();
        for (Schema.RecordTypeInfo rt : Schema.SObjectType.Case.getRecordTypeInfos()) {
            rtIdToName.put(rt.getRecordTypeId(), rt.getName());
        }
        
        /* -------------------------------
Opportunity → Services
--------------------------------*/
        Map<Id, List<Service__c>> oppToServices = new Map<Id, List<Service__c>>();
        Set<Id> serviceIds = new Set<Id>();
        
        List<Service__c> servicesList = [SELECT Id, Store__c FROM Service__c WHERE Store__c IN :oppIds];
        if(servicesList.size() <= 0){
            for(Case c : newList){
                c.addError('You do not have Service'); 
                break;
            }
            return;
        }
        for (Service__c s :servicesList) {
            if (!oppToServices.containsKey(s.Store__c)) {
                oppToServices.put(s.Store__c, new List<Service__c>());
            }
            oppToServices.get(s.Store__c).add(s);
            serviceIds.add(s.Id);
        }
        if (serviceIds.isEmpty()) return;
        
        /* -------------------------------
Service → Retainer Services
--------------------------------*/
        Map<Id, List<Retainer_Service__c>> serviceToRetainers = new Map<Id, List<Retainer_Service__c>>();
        
        
        for (Retainer_Service__c rs : [SELECT Id, Service__c, Case_Record_Type__c,Number_Of_Cases_Allowed_Per_Period__c,Start_Date__c, End_Date__c FROM Retainer_Service__c WHERE Service__c IN :serviceIds]) {
            
            
            if (!serviceToRetainers.containsKey(rs.Service__c)) {
                serviceToRetainers.put(rs.Service__c, new List<Retainer_Service__c>());
            }
            serviceToRetainers.get(rs.Service__c).add(rs);
        }
        if (serviceToRetainers.isEmpty()) return;
        
        /* -------------------------------
Existing Case Count (DB)
--------------------------------*/
        Map<String, Integer> runningKeyToCount = new Map<String, Integer>();
        for (AggregateResult ar : [SELECT Opportunity__c oppId, RecordType.Name rtName, COUNT(Id) total FROM Case WHERE Opportunity__c IN :oppIds GROUP BY Opportunity__c, RecordType.Name]) {
            
            String key = ar.get('oppId') + '-' + ar.get('rtName');
            runningKeyToCount.put(key, (Integer) ar.get('total'));
        }
        
        Date todayDate = Date.today();
        
        /* -------------------------------
Validation Logic
--------------------------------*/
        for (Case c : newList) {
            
            if (c.hasErrors()) continue;
            if (c.Store__c == null) continue;
            if (!storeToOpp.containsKey(c.Store__c)) continue;
            
            Id oppId = storeToOpp.get(c.Store__c);
            List<Service__c> services = oppToServices.get(oppId);
            if (services == null) continue;
            
            String caseRtName = rtIdToName.get(c.RecordTypeId);
            if (caseRtName == null) continue;
            
            Boolean checkRetainerWithRecordType = false;
            for (Service__c svc : services) {
                
                List<Retainer_Service__c> retainers = serviceToRetainers.get(svc.Id);
                if (retainers == null) continue;
                
                // Find active retainer window
                Date startDateVar;
                Date endDateVar;
                Id deactiveRetainerId;
                
                for (Retainer_Service__c rs : retainers) {
                    // system.debug('rs.Case_Record_Type__c : '+rs.Case_Record_Type__c +' caseRtName : '+caseRtName);
                    if (rs.Case_Record_Type__c != caseRtName){
                        continue;
                    } else{
                        checkRetainerWithRecordType = true;
                    }
                    
                    if (startDateVar == null || rs.Start_Date__c < startDateVar) {
                        startDateVar = rs.Start_Date__c;
                    }
                    if (endDateVar == null || rs.End_Date__c > endDateVar) {
                        endDateVar = rs.End_Date__c;
                        deactiveRetainerId = rs.Id;   
                    }
                    
                }
                
                if (startDateVar == null || endDateVar == null) continue;
                
                // Date validation
                if (!(todayDate >= startDateVar && todayDate <= endDateVar)) {
                    c.addError('Case can only be created between ' + startDateVar.format() + ' and ' + endDateVar.format() + ' as per Retainer period.');
                    break;
                }
                
                // FIXED: Active Retainer Based On Today Date
                Id activeRetainerIds;
                Retainer_Service__c activeRetainers;
                for (Retainer_Service__c rs : retainers) {
                    
                    if (rs.Case_Record_Type__c != caseRtName) {
                        continue;
                    }
                    
                    checkRetainerWithRecordType = true;
                    
                    if (todayDate >= rs.Start_Date__c && todayDate <= rs.End_Date__c) {
                        activeRetainerIds = rs.Id;
                        activeRetainers = rs;
                        break;
                    }
                }
                
                if (activeRetainers == null) {
                    continue;
                }
                
                // Case count validation (BULK SAFE)
                for (Retainer_Service__c rs : retainers) {
                    if (rs.Id != activeRetainerIds) continue;
                    
                    String key = oppId + '-' + caseRtName;
                    Integer existing = runningKeyToCount.containsKey(key)
                        ? runningKeyToCount.get(key)
                        : 0;
                    
                    if (existing >= rs.Number_Of_Cases_Allowed_Per_Period__c) {
                        c.addError('You cannot create more than ' + rs.Number_Of_Cases_Allowed_Per_Period__c + ' cases for Record Type "' + caseRtName + ''); 
                        break;
                    }
                    
                    //  Increment for bulk inserts
                    runningKeyToCount.put(key, existing + 1);
                    
                }
            }
            
            if(! checkRetainerWithRecordType){
                c.addError('No Service Retainer found for this Record Type ' +caseRtName );
            }
        }
    }
}