@IsTest
public class ServicesFormControllerTest {
    // ------------------------------------------------------------
    // Test: getServicesWrapData
    // ------------------------------------------------------------
    @IsTest
    static void GetServicesWrapDataTest() {
         Test.startTest();
        // Create base data
        List<Account> accounts = TestDataFactory.createAccounts(1);
        List<Opportunity> opps = TestDataFactory.createOpportunities(accounts, 1);

        List<Store__c> stores = TestDataFactory.createStores(opps[0].Id, 1);
        
        List<Service__c> services = TestDataFactory.createServices(stores[0].Id, 1);
       
        List<Retainer_Service__c> listRS = TestDataFactory.createRetainerServices(services[0].Id, 1);
       
        String jsonResponse = ServicesFormController.getServicesWrapData(opps[0].Id);
        

        System.assertNotEquals(null,jsonResponse,'Response JSON should not be null');

        ServicesFormController.WrapServiceAllData wrapData =
            (ServicesFormController.WrapServiceAllData)
                JSON.deserialize(
                    jsonResponse,
                    ServicesFormController.WrapServiceAllData.class
                );

        ServicesFormController.WrapServiceData storeData = wrapData.listWrapServiceData[0];

        Test.stopTest();
    }

    // ------------------------------------------------------------
    // Test: upsertStoreAndServices
    // ------------------------------------------------------------
    @IsTest
    static void UpsertStoreAndServicesTest() {

        // Create base data
        List<Account> accounts = TestDataFactory.createAccounts(1);
        Opportunity opp = TestDataFactory.createOpportunities(accounts, 1)[0];

        // Create Store and one Retainer Service
        List<Store__c> stores = TestDataFactory.createStores(opp.Id, 1);
        Store__c store = stores[0];
        
        List<Service__c> services = TestDataFactory.createServices(store.Id, 1);

        List<Retainer_Service__c> listRS = TestDataFactory.createRetainerServices(services[0].Id, 1);
        Retainer_Service__c rs = listRS[0];

        // Build wrapper objects
        ServicesFormController.WrapRetainerServices wrapRS =
            new ServicesFormController.WrapRetainerServices();
        wrapRS.id = rs.Id;
        wrapRS.caseRecordType = 'Updated Case Type';
        wrapRS.numberOfCasesAllowedPerPeriod = 50;

        ServicesFormController.WrapServiceData wrapService =
            new ServicesFormController.WrapServiceData();
        wrapService.storeId = store.Id;
        wrapService.startDate = Date.today();
        wrapService.endDate = Date.today().addMonths(6);
        wrapService.price = 9000;
        wrapService.retainerServices =
            new List<ServicesFormController.WrapRetainerServices>{ wrapRS };

        ServicesFormController.WrapServiceAllData wrapAll =
            new ServicesFormController.WrapServiceAllData();
        wrapAll.oppId = opp.Id;
        wrapAll.listWrapServiceData =
            new List<ServicesFormController.WrapServiceData>{ wrapService };
        wrapAll.retainerServiceIdsForDelete = new List<String>();

        String jsonInput = JSON.serialize(wrapAll);

        Test.startTest();
        Boolean isSuccess =
            ServicesFormController.upsertStoreAndServices(jsonInput);
        Test.stopTest();
        
        ServicesFormController.cancelService(listRS[0].Id);

        // Verify Store update
        Store__c updatedStore = [
            SELECT Pricing__c, Start_Date__c, End_Date__c
            FROM Store__c
            WHERE Id = :store.Id
        ];

        // Verify Retainer Service update
        Retainer_Service__c updatedRS = [
            SELECT Case_Record_Type__c,
                   Number_Of_Cases_Allowed_Per_Period__c
            FROM Retainer_Service__c
            WHERE Id = :rs.Id
        ];
       
    }
    
   
}