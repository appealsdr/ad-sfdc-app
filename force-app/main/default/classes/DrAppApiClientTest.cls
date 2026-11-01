@isTest
private class DrAppApiClientTest {

    private class DrAppMock implements HttpCalloutMock {
        Integer statusCode = 200;
        String body = '{"account":{"vuid":"acc-uuid","sfdcAccountId":"001x"},"contact":{"vuid":"user-uuid","sfdcContactId":"003x"},'
            + '"stores":[{"vuid":"store-uuid","name":"Acme US Store","sfdcStoreId":"a0Xx"}],"username":"jdoe","temporaryPassword":"Temp123!"}';
        HttpRequest lastRequest;

        public HttpResponse respond(HttpRequest req) {
            lastRequest = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/reset-password')) {
                res.setBody('{"userId":"u-1","username":"jdoe","temporaryPassword":"Temp123!"}');
            } else {
                res.setBody(body);
            }
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Dr_App_Api_Setting__c setting = Dr_App_Api_Setting__c.getOrgDefaults();
        setting.Api_Key__c = 'test-key';
        upsert setting;
    }

    private static DrAppApiClient.ProvisionRequest buildRequest() {
        DrAppApiClient.ProvisionRequest req = new DrAppApiClient.ProvisionRequest();
        req.companyName = 'Acme Co';
        req.firstName = 'Jane';
        req.lastName = 'Doe';
        req.email = 'jane.doe@example.com';
        req.phone = '555-1234';
        req.website = 'https://example.com';
        return req;
    }

    @isTest
    static void testProvisionAccountSuccess() {
        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        Test.startTest();
        DrAppApiClient.ProvisionResponse res = DrAppApiClient.provisionAccount(buildRequest());
        Test.stopTest();

        System.assertEquals('acc-uuid', res.account.vuid);
        System.assertEquals('001x', res.account.sfdcAccountId);
        System.assertEquals('user-uuid', res.contact.vuid);
        System.assertEquals('003x', res.contact.sfdcContactId);
        System.assertEquals(1, res.stores.size());
        System.assertEquals('Acme US Store', res.stores[0].name);
        System.assertEquals('store-uuid', res.stores[0].vuid);
        System.assertEquals('a0Xx', res.stores[0].sfdcStoreId);
        System.assertEquals('jdoe', res.username);
        System.assertEquals('Temp123!', res.temporaryPassword);
    }

    @isTest
    static void testProvisionAccountWithStores() {
        DrAppApiClient.ProvisionRequest req = buildRequest();
        DrAppApiClient.StoreRequest store = new DrAppApiClient.StoreRequest();
        store.name = 'Acme US Store';
        store.marketplaces = 'US;CA';
        store.sellerId = 'A1B2C3';
        req.stores = new List<DrAppApiClient.StoreRequest>{ store };

        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        Test.startTest();
        DrAppApiClient.ProvisionResponse res = DrAppApiClient.provisionAccount(req);
        Test.stopTest();

        System.assertEquals(1, res.stores.size());
        System.assertEquals('store-uuid', res.stores[0].vuid);
    }

    @isTest
    static void testProvisionAccountSendsSfdcIds() {
        DrAppApiClient.ProvisionRequest req = buildRequest();
        req.sfdcAccountId = '001000000000001';
        req.sfdcContactId = '003000000000001';
        DrAppApiClient.StoreRequest store = new DrAppApiClient.StoreRequest();
        store.name = 'Acme US Store';
        store.sfdcStoreId = 'a0X000000000001';
        req.stores = new List<DrAppApiClient.StoreRequest>{ store };

        DrAppMock mock = new DrAppMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        DrAppApiClient.provisionAccount(req);
        Test.stopTest();

        String sentBody = mock.lastRequest.getBody();
        System.assert(sentBody.contains('"sfdcAccountId":"001000000000001"'), 'Request should include the Salesforce Account Id.');
        System.assert(sentBody.contains('"sfdcContactId":"003000000000001"'), 'Request should include the Salesforce Contact Id.');
        System.assert(sentBody.contains('"sfdcStoreId":"a0X000000000001"'), 'Request should include the Salesforce Store Id.');
    }

    @isTest
    static void testProvisionAccountMissingRequiredFields() {
        DrAppApiClient.ProvisionRequest req = new DrAppApiClient.ProvisionRequest();
        req.firstName = 'Jane';

        Boolean threw = false;
        try {
            DrAppApiClient.provisionAccount(req);
        } catch (DrAppApiClient.DrAppApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('required'));
        }
        System.assert(threw, 'Expected an exception for missing required fields.');
    }

    @isTest
    static void testProvisionAccountApiError() {
        DrAppMock mock = new DrAppMock();
        mock.statusCode = 500;
        mock.body = '{"error":"boom"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Boolean threw = false;
        Test.startTest();
        try {
            DrAppApiClient.provisionAccount(buildRequest());
        } catch (DrAppApiClient.DrAppApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('500'));
        }
        Test.stopTest();

        System.assert(threw, 'Expected an exception when the API returns an error status.');
    }

    @isTest
    static void testResetPasswordSuccess() {
        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        Test.startTest();
        DrAppApiClient.ResetPasswordResponse res = DrAppApiClient.resetPassword(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals('u-1', res.userId);
        System.assertEquals('Temp123!', res.temporaryPassword);
    }

    @isTest
    static void testResetPasswordMissingContactId() {
        Boolean threw = false;
        try {
            DrAppApiClient.resetPassword(null);
        } catch (DrAppApiClient.DrAppApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('required'));
        }
        System.assert(threw, 'Expected an exception for a missing contactId.');
    }
}