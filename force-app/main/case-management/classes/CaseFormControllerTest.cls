@IsTest
public class CaseFormControllerTest {

    /* ============================================================
       TEST SETUP (Single Source of Truth)
       ============================================================ */
    @TestSetup
    static void setupData() {

        // Create Account(s)
        List<Account> accounts = TestDataFactory.createAccounts(1);
        System.assertEquals(1, accounts.size());

        // Create Opportunity(s)
        List<Opportunity> opps =
            TestDataFactory.createOpportunities(accounts, 1);
        System.assertEquals(1, opps.size());
        
        // Create Store
        List<Store__c> stores = TestDataFactory.createStores(opps[0].Id, 1);
        System.assertEquals(1, stores.size());
        stores[0].Account__c = accounts[0].Id;
        Update stores[0];

        // Service Type Pricing (Used by LWC)
        insert new Service_Type_Pricing__c(
            Service_Type__c = 'Account At Risk of Deactivation',
            Total_Price__c = 1000,
            Deposit_Upfront__c = 200
        );
    }

    /* ============================================================
       getAllFieldSetInfo
       ============================================================ */
    @IsTest
    static void testGetAllFieldSetInfo() {

        Test.startTest();
        List<CaseUtil.CaseFieldSetWrapper> result =
            CaseFormController.getAllFieldSetInfo();
        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Field set info must not be null'
        );
    }

    /* ============================================================
       getPricingInfo
       ============================================================ */
    @IsTest
    static void testGetPricingInfo() {

        Test.startTest();
        Map<String, Service_Type_Pricing__c> pricingMap =
            CaseFormController.getPricingInfo(
                new List<String>{ 'Account At Risk of Deactivation' }
            );
        Test.stopTest();

        System.assertEquals(
            1,
            pricingMap.size(),
            'Exactly one pricing record expected'
        );

        System.assert(
            pricingMap.containsKey('account at risk of deactivation'),
            'Key must be lowercase service type'
        );
    }

    /* ============================================================
       upsertCases – INSERT
       ============================================================ */
    @IsTest
    static void testUpsertCases_Insert() {
        
        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Id caseRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByName()
            .values()[0]
            .getRecordTypeId();

        String jsonPayload =
            '[{' +
                '"storeId":"'+ store.Id + '",' +
                '"cases":[{' +
                    '"recordTypeId":"' + caseRtId + '",' +
                    '"fields":[' +
                        '{ "apiName":"Subject","value":"Production Insert Test" },' +
                        '{ "apiName":"Status","value":"New" }' +
                    '],' +
                    '"priceFields":[]}' +
                ']' +
            '}]'; 

        Test.startTest();
        Boolean isSuccess =
            CaseFormController.upsertCases(jsonPayload, opp.Id);
        Test.stopTest();

        System.assertEquals(
            true,
            isSuccess,
            'Insert must return true'
        );

        List<Case> insertedCases = [
            SELECT Subject, Opportunity__c
            FROM Case
            WHERE Opportunity__c = :opp.Id
        ];

        System.assertEquals(
            1,
            insertedCases.size(),
            'One case should be inserted'
        );

        System.assertEquals(
            'Production Insert Test',
            insertedCases[0].Subject
        );
    }

    /* ============================================================
       upsertCases – UPDATE
       ============================================================ */
    @IsTest
    static void testUpsertCases_Update() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Case existingCase = new Case(
            AccountId = acc.Id,
            Opportunity__c = opp.Id,
            Subject = 'Old Subject',
            Status = 'New'
        );
        insert existingCase;

        Id caseRtId = Schema.SObjectType.Case
            .getRecordTypeInfosByName()
            .values()[0]
            .getRecordTypeId();

        String jsonPayload =
            '[{' +
                '"storeId":"'+ store.Id + '",' +
                '"cases":[{' +
                    '"id":"' + existingCase.Id + '",' +
                    '"recordTypeId":"' + caseRtId + '",' +
                    '"fields":[{' +
                        '"apiName":"Subject","value":"Updated Subject"' +
                    '}],' +
                    '"priceFields":[]}' +
                ']' +
            '}]';

        Test.startTest();
        Boolean isSuccess =
            CaseFormController.upsertCases(jsonPayload, opp.Id);
        Test.stopTest();

        System.assertEquals(
            true,
            isSuccess,
            'Update must return true'
        );

        Case updated =
            [SELECT Subject FROM Case WHERE Id = :existingCase.Id];

        System.assertEquals(
            'Updated Subject',
            updated.Subject,
            'Subject must be updated'
        );
    }

    /* ============================================================
       upsertCases – INVALID OPPORTUNITY
       ============================================================ */
    @IsTest
    static void testUpsertCases_InvalidOpportunity() {

        Test.startTest();
        Boolean result =
            CaseFormController.upsertCases(
                '[]',
                '006000000000000AAA'
            );
        Test.stopTest();

        System.assertEquals(
            false,
            result,
            'Must return false for invalid Opportunity'
        );
    }
}