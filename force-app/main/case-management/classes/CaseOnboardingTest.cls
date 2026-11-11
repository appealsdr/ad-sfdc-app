@IsTest
private class CaseOnboardingTest {
    private static final String CONFIG_A = '{\n  "steps": ["Start", "Review"],\n  "required": true\n}';
    private static final String CONFIG_B = '{"steps":["Verify"],"required":false}';
    private static final String EXISTING_CONFIG = '{"steps":["Existing"]}';

    @TestSetup
    static void setupData() {
        insert new TriggerControl__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Case_Trigger_Enabled__c = true,
            Validate_Case__c = false,
            Update_Total_Case__c = false
        );

        Account account = new Account(Name = 'AD-56 onboarding account');
        insert account;

        List<Product2> products = new List<Product2>{
            new Product2(Name = 'AD-56 onboarding A', IsActive = true, Onboarding_Config__c = CONFIG_A),
            new Product2(Name = 'AD-56 onboarding B', IsActive = true, Onboarding_Config__c = CONFIG_B),
            new Product2(Name = 'AD-56 onboarding empty', IsActive = true)
        };
        insert products;

        Id pricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Product2 product : products) {
            entries.add(new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,
                UnitPrice = 100,
                IsActive = true,
                Payment_type__c = 'Full Price'
            ));
        }
        insert entries;

        ServiceContract contract = new ServiceContract(
            Name = 'AD-56 onboarding contract',
            AccountId = account.Id,
            Pricebook2Id = pricebookId,
            StartDate = Date.today()
        );
        insert contract;

        List<ContractLineItem> lines = new List<ContractLineItem>();
        for (PricebookEntry entry : entries) {
            lines.add(new ContractLineItem(
                ServiceContractId = contract.Id,
                PricebookEntryId = entry.Id,
                Quantity = 1,
                UnitPrice = 100
            ));
        }
        insert lines;
    }

    @IsTest
    static void copiesProductConfigForBulkInsert() {
        List<Case> cases = makeCases(200);

        Test.startTest();
        insert cases;
        Test.stopTest();

        Map<Id, Case> savedCases = new Map<Id, Case>([
            SELECT Case_Onboarding__c FROM Case WHERE Id IN :cases
        ]);
        System.assertEquals(200, savedCases.size(), 'All cases should be inserted.');
        for (Integer i = 0; i < cases.size(); i++) {
            System.assertEquals(expectedConfig(i), savedCases.get(cases[i].Id).Case_Onboarding__c,
                'Linked cases must copy the exact product config; unlinked cases must keep their config.');
        }
    }

    @IsTest
    static void populatesBeforeInsertWithOneQueryAndNoDml() {
        List<Case> cases = makeCases(200);

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        CaseTriggerHandler.copyProductOnboardingConfig(null);
        CaseTriggerHandler.copyProductOnboardingConfig(new List<Case>());
        CaseTriggerHandler.copyProductOnboardingConfig(new List<Case>{
            new Case(Case_Onboarding__c = EXISTING_CONFIG)
        });
        System.assertEquals(queriesBefore, Limits.getQueries(),
            'Cases without contract lines should not require a query.');

        CaseTriggerHandler.copyProductOnboardingConfig(cases);
        System.assertEquals(queriesBefore + 1, Limits.getQueries(),
            'All contract lines should be loaded in one query.');
        System.assertEquals(dmlBefore, Limits.getDmlStatements(),
            'The before-insert handler must populate the incoming records without DML.');
        Test.stopTest();

        for (Integer i = 0; i < cases.size(); i++) {
            System.assertEquals(null, cases[i].Id, 'Cases should still be unsaved.');
            System.assertEquals(expectedConfig(i), cases[i].Case_Onboarding__c,
                'The configuration must be populated before the case is inserted.');
        }
    }

    @IsTest
    static void changingContractLineOnUpdateKeepsCopiedConfig() {
        List<Case> cases = makeCases(2);
        Case caseRecord = cases[0];
        insert caseRecord;
        System.assertEquals(CONFIG_A, [
            SELECT Case_Onboarding__c FROM Case WHERE Id = :caseRecord.Id
        ].Case_Onboarding__c, 'The original product config should be copied on insert.');

        Case updatedCase = new Case(
            Id = caseRecord.Id,
            Contract_Line_Item__c = cases[1].Contract_Line_Item__c
        );
        Test.startTest();
        update updatedCase;
        Test.stopTest();

        System.assertEquals(CONFIG_A, [
            SELECT Case_Onboarding__c FROM Case WHERE Id = :caseRecord.Id
        ].Case_Onboarding__c, 'Updating the case must not replace its onboarding config.');
    }

    @IsTest
    static void disabledTriggerKeepsExistingConfig() {
        TriggerControl__c setting = [
            SELECT Id, Case_Trigger_Enabled__c FROM TriggerControl__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        ];
        setting.Case_Trigger_Enabled__c = false;
        update setting;
        Case caseRecord = makeCases(1)[0];

        Test.startTest();
        insert caseRecord;
        Test.stopTest();

        System.assertEquals(EXISTING_CONFIG, [
            SELECT Case_Onboarding__c FROM Case WHERE Id = :caseRecord.Id
        ].Case_Onboarding__c, 'Disabling the Case trigger should also disable the onboarding copy.');
    }

    private static List<Case> makeCases(Integer count) {
        Map<String, Id> lineIdsByProduct = new Map<String, Id>();
        for (ContractLineItem line : [
            SELECT Id, PricebookEntry.Product2.Name FROM ContractLineItem
        ]) {
            lineIdsByProduct.put(line.PricebookEntry.Product2.Name, line.Id);
        }

        List<Id> lineIds = new List<Id>{
            lineIdsByProduct.get('AD-56 onboarding A'),
            lineIdsByProduct.get('AD-56 onboarding B'),
            lineIdsByProduct.get('AD-56 onboarding empty'),
            null
        };
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            cases.add(new Case(
                Subject = 'AD-56 onboarding case ' + i,
                Status = 'New',
                Origin = 'Phone',
                Contract_Line_Item__c = lineIds[Math.mod(i, 4)],
                Case_Onboarding__c = EXISTING_CONFIG
            ));
        }
        return cases;
    }

    private static String expectedConfig(Integer index) {
        Integer groupIndex = Math.mod(index, 4);
        if (groupIndex == 0) return CONFIG_A;
        if (groupIndex == 1) return CONFIG_B;
        if (groupIndex == 2) return null;
        return EXISTING_CONFIG;
    }
}
