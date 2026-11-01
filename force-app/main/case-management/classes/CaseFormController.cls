public with sharing class CaseFormController {
    public CaseFormController() {

    }

    @AuraEnabled(cacheable=true)
    public static List<CaseUtil.CaseFieldSetWrapper> getAllFieldSetInfo() {
        List<CaseUtil.CaseFieldSetWrapper> listCaseFieldSet = new List<CaseUtil.CaseFieldSetWrapper>();
        try {
            listCaseFieldSet = CaseUtil.getFieldSetFromCase('Case');
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }

        return listCaseFieldSet;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Service_Type_Pricing__c>  getPricingInfo(List<String> listRtLabel) {
        System.debug('listRtLabel==>'+listRtLabel);
        Map<String, Service_Type_Pricing__c> mapServiceTypePrice = new Map<String, Service_Type_Pricing__c>();
        if (listRtLabel != null && !listRtLabel.isEmpty()) {
            for (Service_Type_Pricing__c itrSTP : [
                SELECT Id, Service_Type__c, Total_Price__c, Deposit_Upfront__c  
                FROM Service_Type_Pricing__c 
                WHERE Service_Type__c !=null and Service_Type__c IN:listRtLabel  LIMIT 40000
            ]) {
             
                mapServiceTypePrice.put((itrSTP.Service_Type__c + '').toLowerCase(), itrSTP);
            }
        }

        return mapServiceTypePrice;
    }

    @AuraEnabled
    public static Boolean upsertCases(String strWrapCaseAllData, String oppId) {
        Boolean isSuccess = false;

        List<Opportunity> listOpp = [SELECT Id, AccountId FROM Opportunity WHERE Id = :oppId LIMIT 1];
        if (listOpp.size() == 0) {
            return isSuccess;
        }

        try {
            System.debug('strWrapCaseAllData==>'+strWrapCaseAllData);
            List<Case> listCase = new List<Case>();

            List<Object> listWrapCases = (List<Object>)JSON.deserializeUntyped(strWrapCaseAllData);
            for (Object itrWrap : listWrapCases) {
                Map<String, Object> mapWrapCases = (Map<String, Object>)itrWrap;
                String storeId = (String)mapWrapCases.get('storeId');
                if (String.isBlank(storeId)) {
                    continue;
                }

                List<Object> cases = (List<Object>)mapWrapCases.get('cases');
                for (Object itrCaseRec : cases) {
                    Map<String, Object> itrCase = (Map<String, Object>)itrCaseRec;
                    Case objCase = new Case();
                    String caseId = (String)itrCase.get('id');
                    if (String.isNotBlank(caseId) ) {
                        objCase.put('Id' , caseId);
                    }
                    objCase.put('Store__c' , storeId);
                    objCase.put('Opportunity__c' , listOpp[0].Id);
                    objCase.put('AccountId' , listOpp[0].AccountId);
                    objCase.put('RecordTypeId' , itrCase.get('recordTypeId'));
                    
                    if (itrCase.get('ownerId') != null && itrCase.get('ownerId') != '') {
                        objCase.put('OwnerId' , itrCase.get('ownerId'));
                    }
                    if (itrCase.get('ownerName') != null && itrCase.get('ownerName') != '') {
                        objCase.put('Owner_Name__c' , itrCase.get('ownerName'));
                    }

                    List<Object> fields = (List<Object>)itrCase.get('fields');
                    List<Object> pricefields = (List<Object>)itrCase.get('priceFields');
                    fields.addAll(pricefields);
                    
                    if (fields == null || fields.size() == 0) continue;

                    for (Object itrField : fields) {
                        Map<String, Object> mapField = (Map<String, Object>)itrField;
                        String fieldApiName = (String)mapField.get('apiName');
                        String value = mapField.get('value') != null ? String.valueOf(mapField.get('value')) : null;
                        System.debug('fieldApiName:'+fieldApiName+ ' --Value--'+value);
                       
                        if (String.isNotBlank(fieldApiName) && String.isNotBlank(value) ) {
                            objCase = CaseUtil.setFieldValue(objCase, fieldApiName, mapField.get('value'));
                        }
                    }

                    // Handle rush fee: set Rush_Fee__c flag, elevate Priority, and add $900 to pricing
                    Boolean rushFee = (Boolean)itrCase.get('rushFee');
                    if (rushFee != null && rushFee) {
                        objCase.put('Rush_Fee__c', true);
                        objCase.put('Priority', 'High');
                        // When pricing fields were not submitted by the user (non-pricing user),
                        // look up the service type default price and add the $900 rush fee on top
                        if (objCase.get('Total_Price__c') == null) {
                            String rtId = (String)itrCase.get('recordTypeId');
                            if (String.isNotBlank(rtId)) {
                                RecordType rt = [SELECT Name FROM RecordType WHERE Id = :rtId LIMIT 1];
                                List<Service_Type_Pricing__c> stpList = [
                                    SELECT Total_Price__c, Deposit_Upfront__c
                                    FROM Service_Type_Pricing__c
                                    WHERE Service_Type__c = :rt.Name
                                    LIMIT 1
                                ];
                                if (!stpList.isEmpty()) {
                                    Decimal baseTotal = stpList[0].Total_Price__c != null ? stpList[0].Total_Price__c : 0;
                                    Decimal baseDeposit = stpList[0].Deposit_Upfront__c != null ? stpList[0].Deposit_Upfront__c : 0;
                                    objCase.put('Total_Price__c', baseTotal + 900);
                                    objCase.put('Deposit_Upfront__c', baseDeposit + 900);
                                }
                            }
                        }
                    }

                    listCase.add(objCase);
                }
            }

            System.debug('listCase==>'+listCase.size());
            if (listCase.size() > 0) {
                Database.upsert(listCase, true);
                isSuccess = true;
            }
            
        } catch (DmlException e) {

            System.debug(
                'Error: Line No-' + e.getLineNumber() + '--Message--' + e.getMessage()
            );

            String validationMsg = e.getDmlMessage(0);

            // Remove Salesforce technical prefix if present
            if (validationMsg.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION')) {
                validationMsg = validationMsg.substringAfter(
                    'FIELD_CUSTOM_VALIDATION_EXCEPTION,'
                ).trim();
            }

            throw new AuraHandledException(validationMsg);
        }
        catch (Exception e) {
            System.debug(
                'Error: Line No-' + e.getLineNumber() + '--Message--' + e.getMessage()
            );
            // Generic user-friendly error
            throw new AuraHandledException('Something went wrong. Please contact your administrator.');
        }

      return isSuccess;
    }

    public class WrapCaseCompData {
        @AuraEnabled public List<String> fieldLabel;
    }
    
}