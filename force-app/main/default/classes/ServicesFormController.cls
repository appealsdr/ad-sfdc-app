public with sharing class ServicesFormController {
    public ServicesFormController() {

    }

    @AuraEnabled
    public static String getServicesWrapData(String recordId) {
        try {

            
            WrapServiceAllData objWrapAllData = new WrapServiceAllData();
            List<WrapServiceData> listWrapServices = new List<WrapServiceData>();
            
            // List<String> listCloseStatus = getCaseClosedStatus();
            // Map<String, Object> mapStatus = getCaseStatusByLabel();

            Integer index = 0;
            for (Service__c  itrService : [
                SELECT  Id,Start_Date__c, End_Date__c, Store_Services__c,  Store_Services__r.Name, Contract_For_Month__c, Price__c, 
                    (SELECT Id,Name, Case_Record_Type__c, Number_Of_Cases_Allowed_Per_Period__c, Amount_Per_Month__c, Month__c, Year__c, Start_Date__c, End_Date__c  FROM Retainer_Services__r Order by Case_Record_Type__c ASC, Start_Date__c Asc  )  
                FROM Service__c  
                WHERE Store_Services__r.Opportunity__c !=  null AND Store_Services__r.Opportunity__c = :recordId
            ]) {
                
                WrapServiceData objWrap = new WrapServiceData();
                if (itrService.Retainer_Services__r !=null && itrService.Retainer_Services__r.size() > 0) {
                    objWrap.index = ++index;
                    objWrap.serviceId = itrService.Id;
                    objWrap.storeId = itrService.Store_Services__c;
                    objWrap.storeName = itrService.Store_Services__r.Name;
                    objWrap.startDate = itrService.Start_Date__c;
                    objWrap.endDate = itrService.End_Date__c;
                    objWrap.price =  Integer.valueOf(itrService.Price__c);
                    objWrap.contractForMonth = itrService.Contract_For_Month__c;
                    objWrap.retainerServices = new List<WrapRetainerServices>();
                    objWrap.showDeleteButton = false;//itrService.Retainer_Services__r.size() > 1 ;
                   
                    Integer indexRS = 0;
                    for (Retainer_Service__c itrRS : itrService.Retainer_Services__r) {
                        WrapRetainerServices objWrapRS = new WrapRetainerServices();
                        objWrapRS.index = ++indexRS;
                        objWrapRS.id = itrRS.Id;
                        objWrapRS.caseRecordType = itrRS.Case_Record_Type__c;
                        objWrapRS.numberOfCasesAllowedPerPeriod = Integer.valueOf(itrRS.Number_Of_Cases_Allowed_Per_Period__c);
                         objWrapRS.amountPerMonth  = itrRS.Amount_Per_Month__c;
                        objWrapRS.month = Integer.valueOf(itrRS.Month__c);
                        objWrapRS.year = Integer.valueOf(itrRS.Year__c);
                        objWrapRS.startDate = itrRS.Start_Date__c;
                        objWrapRS.endDate = itrRS.End_Date__c;
                        objWrap.retainerServices.add(objWrapRS);
                    }
                    listWrapServices.add(objWrap);
                }
            }

            objWrapAllData.listWrapServiceData = listWrapServices;
            objWrapAllData.oppId = recordId;
            objWrapAllData.retainerServiceIdsForDelete = new List<String>();
            System.debug('objWrapAllData==>'+objWrapAllData);
            return JSON.serialize(objWrapAllData);
        } catch (Exception e) {
            String errorMsg = 'Error: Line no: ' + e.getLineNumber() + ' --Message: ' + e.getMessage() + ' --StackTrace: ' + e.getStackTraceString();
            System.debug('errorMsg==>'+errorMsg);
            throw new AuraHandledException(e.getMessage());
        }
    }

     @AuraEnabled
    public static Boolean upsertStoreAndServices(String strWrapServiceAllData) {
        Boolean isSuccess = true;
        try {
            WrapServiceAllData objWrapAllData = (WrapServiceAllData)JSON.deserialize(strWrapServiceAllData, WrapServiceAllData.class);
            System.debug('objWrapAllData==>'+objWrapAllData);
        
            List<Service__c> listService = new List<Service__c>();
            Map<Integer, List<Retainer_Service__c >> mapIdxRetServices = new Map<Integer, List<Retainer_Service__c > >();
            if (objWrapAllData.listWrapServiceData != null && objWrapAllData.listWrapServiceData.size() > 0) {
                
                for (Integer i=0; i < objWrapAllData.listWrapServiceData.size(); i++) {
                    
                    WrapServiceData objWrap  = objWrapAllData.listWrapServiceData[i];
                    if (String.isBlank(objWrap.storeId)) continue;
                    
                    Service__c objService = new Service__c(
                        Start_Date__c = objWrap.startDate, 
                        Contract_For_Month__c = objWrap.contractForMonth,
                        End_Date__c = objWrap.endDate, Price__c = objWrap.price,
                        Store_Services__c = objWrap.storeId,
                        Store__c = String.isNotBlank(objWrapAllData.oppId) ? objWrapAllData.oppId : null
                    );

                    String startDt = objWrap.startDate.year() + '-' +
                        String.valueOf(objWrap.startDate.month()).leftPad(2, '0') + '-' +
                        String.valueOf(objWrap.startDate.day()).leftPad(2, '0');

                    String endDt = objWrap.endDate.year() + '-' +
                        String.valueOf(objWrap.endDate.month()).leftPad(2, '0') + '-' +
                        String.valueOf(objWrap.endDate.day()).leftPad(2, '0');

                    objService.Name = objWrap.storeName + ' (' + startDt + ' to ' + endDt + ')';


                    if (String.isNotBlank(objWrap.serviceId)) {
                        objService.Id = objWrap.serviceId;
                    }

                    listService.add(objService);

                    if (objWrap.retainerServices != null && objWrap.retainerServices.size() > 0) {

                        List<Retainer_Service__c> listRetainerService = new List<Retainer_Service__c>();

                        for (WrapRetainerServices objWrapRS : objWrap.retainerServices) {
                            Retainer_Service__c objRS = new Retainer_Service__c();
                            if (String.isNotBlank(objWrapRS.id)) {
                                objRS.Id = objWrapRS.id;
                            }

                            objRS.Case_Record_Type__c = objWrapRS.caseRecordType;
                            objRS.Number_Of_Cases_Allowed_Per_Period__c = objWrapRS.numberOfCasesAllowedPerPeriod;
                            objRS.Amount_Per_Month__c = objWrapRS.amountPerMonth;
                            objRS.Month__c = objWrapRS.month;
                            objRS.Year__c = objWrapRS.year;
                            objRS.Start_Date__c = objWrapRS.startDate;
                            objRS.End_Date__c = objWrapRS.endDate;


                            listRetainerService.add(objRS);
                            mapIdxRetServices.put(i, listRetainerService);
                        }  
                    }
                }
            }

            System.debug('listService==>'+listService.size());
            if (listService.size() > 0) {
                upsert listService;
            }

            System.debug('mapIdxRetServices==>'+mapIdxRetServices.size());
            if (mapIdxRetServices.size() > 0) {
                List<Retainer_Service__c> listRSToUpsert = new List<Retainer_Service__c>();
                for (Integer i=0; i<listService.size(); i++) {
                    if (mapIdxRetServices.containsKey(i)) {
                        for (Retainer_Service__c objRS : mapIdxRetServices.get(i)) {
                            objRS.Service__c = listService[i].Id;
                            listRSToUpsert.add(objRS);
                        }
                    }
                }

                if (listRSToUpsert.size() > 0) {
                    upsert listRSToUpsert;
                }  
            }
        } catch (Exception e) {
            String errorMsg = 'Error: Line no: ' + e.getLineNumber() + ' --Message: ' + e.getMessage() + ' --StackTrace: ' + e.getStackTraceString();
            isSuccess = false;
            insertAppLog(e, 'upsertStoreAndServices');
        }

        return isSuccess;
    }



    public static void insertAppLog(Exception e, String methodName) {
        String errorMsg = 'Error: Line no: ' + e.getLineNumber() + ' --Message: ' + e.getMessage() + ' --StackTrace: ' + e.getStackTraceString();
        Application_Log__c log = new Application_Log__c(
            Component_Name__c = 'Apex Class: ServicesFormController, Function: ' + methodName,
            Error__c = errorMsg
        );
        insert log;

    }

    @AuraEnabled
    public static Boolean cancelService(String serviceId) {
        Boolean isSuccess = false;
        List<Case> listCaseToUpdate = new List<Case>();
        List<String> listCloseStatus = getCaseClosedStatus();
        Map<String, Object> mapStatus = getCaseStatusByLabel();

        //Store__c it is a Opportunity as it was already created this way
        List<Service__c> listService = [SELECT Id, Status__c, Store__c, Store_Services__c FROM Service__c WHERE Id =: serviceId];
        if (listService.size() > 0) {
            for (Case itrCase : [
                SELECT Id, Status FROM Case 
                WHERE Status NOT IN: listCloseStatus 
                    AND  Store__c != null AND Store__c =: listService[0].Store_Services__c 
            ]) {
                itrCase.Status = (String)mapStatus.get('Canceled');
                listCaseToUpdate.add(itrCase);
            }

            if (listCaseToUpdate.size() > 0) {
                Update listCaseToUpdate;
            }

            Store__c objStore = new Store__c(
                Id = listService[0].Store_Services__c,
                Opportunity__c = null
            );
            
            Update objStore;

            listService[0].Status__c = (String)mapStatus.get('Canceled');
            Update listService[0];
            isSuccess = true;

        } else {
            System.debug('Service not found for this record id: '+serviceId);
        }

        return isSuccess;
    }

    public static Map<String, Object> getCaseStatusByLabel() {
        String lableVal = Label.Case_Status;
        return (Map<String, Object>)JSON.deserializeUntyped(lableVal);
    }


    public static List<String> getCaseClosedStatus() {
        List<String> listCloseStatus = new List<String>();
        Map<String, Object> mapObject = getCaseStatusByLabel();
        if (mapObject.containsKey('CLOSE_STATUS_FOR_CANCEL_SERVICE')) {
            String closeStatus = (String)mapObject.get('CLOSE_STATUS_FOR_CANCEL_SERVICE');
            for (String status : closeStatus.split(',')) {
                status = status.trim();
                listCloseStatus.add(status);
            }
        }
        return listCloseStatus;
    }

    public class WrapServiceAllData {
       public String oppId;
       public List<WrapServiceData> listWrapServiceData; 
       public List<String> retainerServiceIdsForDelete; 
    }

  
    public class WrapServiceData {
        public Integer index;	//xxxx
        public String serviceId;	//xxxx
        public String storeId;	//xxxx
        public String storeName;	//xxxx
        public Decimal contractForMonth;
        public Date startDate;	//2021-01-01
        public Date endDate;
        public String contractLength;	//3 months
        public String retainerPeriod;	//Monthly
        public Integer price;	//$7,000
        public WrapRetainerServices[] retainerServices;
        public Boolean swithStoreSection = true;
        public Boolean showDeleteButton = false;  
    }

    public class WrapRetainerServices {
        public Integer index;	//xxxx
        public Id id;	//Violations
        public String caseRecordType;	//Violations
        public Integer numberOfCasesAllowedPerPeriod;	//30
        public Decimal amountPerMonth;	//30
        public Integer month;	//30
        public Integer year;	//30
        public Date startDate;	//2021-01-01
        public Date endDate;
        public Boolean showDeleteButton = false;  
    }
}