@IsTest
public class OpportunityDataSendersApiTest {

    /* =========================================================
       MOCK CLASSES
    ========================================================= */

    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"status":"success","checkout_url":"https://payment.com/checkout/123"}');
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    /* =========================================================
       TEST DATA CREATION
    ========================================================= */

    private static Id createTestData(Boolean withConfig) {

        Account acc = new Account(
            Name = 'Test Account',
            Primary_Email__c = 'test@mail.com'
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10),
            Amount = 5000,
            AccountId = acc.Id
        );
        insert opp;

        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john@test.com',
            Phone = '1234567890',
            Client__c = acc.Id
        );
        insert con;

        Store__c store = new Store__c(
            Name = 'Amazon Store',
            Account__c = acc.Id,
            Seller_ID__c = 'SELLER-001'
        );
        insert store;

        Case cs = new Case(
            Subject = 'Test Case',
            Store__c = store.Id,
            Opportunity__c = opp.Id,
            Amazon_Store_Name__c = 'AmazonTest',
            Status = 'New'
        );
        insert cs;

        Service__c service = new Service__c(
            Name = 'Monthly Service',
            Store__c = opp.Id,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addMonths(1),
            Contract_For_Month__c = 1,
            Price__c = 1000
        );
        insert service;

        Retainer_Service__c ret = new Retainer_Service__c(
           
            Service__c = service.Id,
            Case_Record_Type__c = 'Suspended Accounts',
           // Store_Opportunity__c = opp.Id,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addMonths(1),
            Amount_Per_Month__c = 500,
            Total_Case__c = 5,
            Number_Of_Cases_Allowed_Per_Period__c = 2
        );
        insert ret;

        if (withConfig) {
            Appeals_WebhookApi__c config = new Appeals_WebhookApi__c(
                Name = 'Default',
                EndPoint_URL__c = 'https://example.com/api/opportunity',
                Api_Key__c = 'XYZ12345'
            );
            insert config;
        }

        return opp.Id;
    }

    /* =========================================================
       FLOW METHOD TEST
    ========================================================= */

    @IsTest
    static void SendOpportunityData_FromFlowTest() {

        Id oppId = createTestData(true);

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        OpportunityDataSendersApi.InputParams param =
            new OpportunityDataSendersApi.InputParams();
        param.opportunityId = oppId;
        param.action = 'Create';

        Test.startTest();
        OpportunityDataSendersApi.sendOpportunityData(
            new List<OpportunityDataSendersApi.InputParams>{param});
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Checkout_URL__c
            FROM Opportunity
            WHERE Id = :oppId
        ];

        System.assertNotEquals(null, updatedOpp.Checkout_URL__c);

        System.assertEquals(1,
            [SELECT COUNT() FROM Application_Log__c]);
    }

    /* =========================================================
       TRIGGER METHOD TEST
    ========================================================= */

    @IsTest
    static void SendOpportunityData_FromTriggerTest() {

        Id oppId = createTestData(true);

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        OpportunityDataSendersApi.sendOpportunityDatabyTrigger(
            new Set<Id>{oppId}, 'Update');
        Test.stopTest();

        System.assert(
            [SELECT COUNT() FROM Application_Log__c] > 0
        );
    }

    /* =========================================================
       ERROR RESPONSE TEST
    ========================================================= */

    @IsTest
    static void ErrorResponseTest() {

        Id oppId = createTestData(true);

        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        OpportunityDataSendersApi.sendOpportunityDatabyTrigger(
            new Set<Id>{oppId}, 'Update');
        Test.stopTest();

        Application_Log__c logRec = [
            SELECT Error__c
            FROM Application_Log__c
            LIMIT 1
        ];

        System.assert(logRec.Error__c.contains('HTTP 500'));
    }

    /* =========================================================
       EMPTY PARAM TEST
    ========================================================= */

    @IsTest
    static void EmptyParamsTest() {
        Test.startTest();
        OpportunityDataSendersApi.sendOpportunityData(
            new List<OpportunityDataSendersApi.InputParams>());
        Test.stopTest();
    }

    /* =========================================================
       MISSING CONFIG TEST
    ========================================================= */

    @IsTest
    static void MissingConfigTest() {

        Id oppId = createTestData(false);

        Test.startTest();
        OpportunityDataSendersApi.sendToExternalAPI(
            '{"object_type":"Opportunity"}',
            oppId
        );
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Application_Log__c]);
    }

    /* =========================================================
       EMPTY BODY TEST
    ========================================================= */

    @IsTest
    static void EmptyBodyTest() {
        Test.startTest();
        OpportunityDataSendersApi.sendToExternalAPI('', null);
        Test.stopTest();
    }
    @IsTest
   static void OpportunityDataWrapperCoverageTest() {

    // Create Wrapper
    OpportunityDataWrapper wrapper = new OpportunityDataWrapper();
    wrapper.object_type = 'Opportunity';
    wrapper.action = 'Create';
    wrapper.timestamp = String.valueOf(System.now());

    // Data
    wrapper.data = new OpportunityDataWrapper.Data();
    wrapper.data.link_expiration = '30';
    wrapper.data.CurrencyIsoCode = 'USD';

    // Customer
    wrapper.data.customer = new OpportunityDataWrapper.Customer();
    wrapper.data.customer.Id = '001XXXX';
    wrapper.data.customer.Name = 'Test Account';
    wrapper.data.customer.PrimaryEmail = 'test@test.com';

    // Opportunity
    OpportunityDataWrapper.Opportunity oppWrap =
        new OpportunityDataWrapper.Opportunity();
    oppWrap.Id = '006XXXX';
    oppWrap.Name = 'Test Opp';
    oppWrap.Amount = 5000;
    oppWrap.StageName = 'Prospecting';
    oppWrap.CloseDate = Date.today();

    // Service
    OpportunityDataWrapper.Service service =
        new OpportunityDataWrapper.Service();
    service.serviceId = 'SERV001';
    service.serviceName = 'Monthly Service';
    service.startDate = Date.today();
    service.endDate = Date.today().addMonths(1);
    service.months = 1;
    service.amountPerMonth = 1000;

    // Retainer Service
    OpportunityDataWrapper.RetainerService ret =
        new OpportunityDataWrapper.RetainerService();
    ret.retainerServiceNo = 'RET001';
    ret.caseRecordType = 'Suspended Accounts';
    ret.amountPerMonth = 500;
    ret.totalCase = 5;

    service.RetainerServices = new List<OpportunityDataWrapper.RetainerService>{ret};
    oppWrap.Services = new List<OpportunityDataWrapper.Service>{service};

    wrapper.data.customer.Opportunities =
        new List<OpportunityDataWrapper.Opportunity>{oppWrap};

    // Contact
    OpportunityDataWrapper.Contact contact =
        new OpportunityDataWrapper.Contact();
    contact.Id = '003XXXX';
    contact.FirstName = 'John';
    contact.LastName = 'Doe';
    contact.Email = 'john@test.com';

    wrapper.data.customer.Contacts =
        new List<OpportunityDataWrapper.Contact>{contact};

    // Store
    OpportunityDataWrapper.Store store =
        new OpportunityDataWrapper.Store();
    store.Id = 'a01XXXX';
    store.Name = 'Amazon Store';
    store.SellerId = 'SELLER-001';

    // CaseRecord
    OpportunityDataWrapper.CaseRecord caseRec =
        new OpportunityDataWrapper.CaseRecord();
    caseRec.id = '500XXXX';
    caseRec.caseNumber = '00001001';
    caseRec.status = 'New';
    caseRec.subject = 'Test Case';

    store.Cases =
        new List<OpportunityDataWrapper.CaseRecord>{caseRec};

    wrapper.data.customer.stores =
        new List<OpportunityDataWrapper.Store>{store};

    // Convert to JSON
    String jsonOutput = wrapper.toJson();
    System.assertNotEquals(null, jsonOutput);

    // Parse back
    OpportunityDataWrapper parsed =
        OpportunityDataWrapper.parse(jsonOutput);

    System.assertEquals('Opportunity', parsed.object_type);
    System.assertEquals('Test Account',
        parsed.data.customer.Name);
}
}