@IsTest
public class StoreToRetainerCaseHandlerTest {

    @TestSetup
    public static void setupData(){

        /* ---------------------------------
           Enable Trigger via Custom Setting
        ----------------------------------*/
        TriggerControl__c setting = new TriggerControl__c(
            Case_Trigger_Enabled__c = true,
            Validate_Case__c = true,
            Update_Total_Case__c = true
        );
        insert setting;

        /* ---------------------------------
           Account
        ----------------------------------*/
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        /* ---------------------------------
           Opportunity
        ----------------------------------*/
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        /* ---------------------------------
           Store
        ----------------------------------*/
        Store__c str = new Store__c(
            Name = 'Test Store',
            Account__c = acc.Id,
            Opportunity__c = opp.Id
        );
        insert str;

        /* ---------------------------------
           Service (Store__c stores Opp Id)
        ----------------------------------*/
        Service__c svc = new Service__c(
            Name = 'Test Service',
            Store__c = opp.Id
        );
        insert svc;

        /* ---------------------------------
           Get RecordType safely
        ----------------------------------*/
        RecordType rt = [
            SELECT Id, Name
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND IsActive = true
            LIMIT 1
        ];

        /* ---------------------------------
           Retainer Service (Active Window)
        ----------------------------------*/
        Retainer_Service__c rs = new Retainer_Service__c(
            Service__c = svc.Id,
            Case_Record_Type__c = rt.Name,
            Number_Of_Cases_Allowed_Per_Period__c = 1,
            Start_Date__c = Date.today().addDays(-5),
            End_Date__c = Date.today().addDays(5)
        );
        insert rs;
    }

    /* =====================================
       POSITIVE TEST – Case Allowed
    ======================================*/
    @IsTest
    static void caseAllowedTest() {

        Store__c store = [SELECT Id, Opportunity__c FROM Store__c LIMIT 1];

        Id rtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case'
            AND IsActive = true
            LIMIT 1
        ].Id;

        Case c = new Case(
            Subject = 'Allowed Case',
            Store__c = store.Id,
            Opportunity__c = store.Opportunity__c,
            RecordTypeId = rtId
        );

        Test.startTest();
        insert c;
        Test.stopTest();

        System.assertNotEquals(null, c.Id);
    }

    /* =====================================
       NEGATIVE – Limit Exceeded
    ======================================*/
    @IsTest
    static void caseLimitExceededTest() {

        Store__c store = [SELECT Id, Opportunity__c FROM Store__c LIMIT 1];

        Id rtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case'
            AND IsActive = true
            LIMIT 1
        ].Id;

        // First case (allowed)
        insert new Case(
            Subject = 'First Case',
            Store__c = store.Id,
            Opportunity__c = store.Opportunity__c,
            RecordTypeId = rtId
        );

        // Second case (should fail)
        Case c2 = new Case(
            Subject = 'Second Case',
            Store__c = store.Id,
            Opportunity__c = store.Opportunity__c,
            RecordTypeId = rtId
        );

        Test.startTest();
        try {
            insert c2;
            System.assert(false, 'Expected limit error');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('You cannot create more than')
            );
        }
        Test.stopTest();
    }

    /* =====================================
       NEGATIVE – No Service
    ======================================*/
    @IsTest
    static void noServiceTest() {

        Opportunity opp = new Opportunity(
            Name = 'Opp Without Service',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Store__c newStore = new Store__c(
            Name = 'Store Without Service',
            Opportunity__c = opp.Id
        );
        insert newStore;

        Id rtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case'
            AND IsActive = true
            LIMIT 1
        ].Id;

        Case c = new Case(
            Subject = 'No Service Case',
            Store__c = newStore.Id,
            Opportunity__c = opp.Id,
            RecordTypeId = rtId
        );

        Test.startTest();
        try {
            insert c;
            System.assert(false, 'Expected service error');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('You do not have Service')
            );
        }
        Test.stopTest();
    }

    /* =====================================
       NEGATIVE – Outside Date Range
    ======================================*/
    @IsTest
    static void outsideRetainerDateTest() {

        Store__c store = [SELECT Id, Opportunity__c FROM Store__c LIMIT 1];

        Id rtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case'
            AND IsActive = true
            LIMIT 1
        ].Id;

        // Expire retainer
        Retainer_Service__c rs = [
            SELECT Id FROM Retainer_Service__c LIMIT 1
        ];
        rs.Start_Date__c = Date.today().addDays(-10);
        rs.End_Date__c = Date.today().addDays(-5);
        update rs;

        Case c = new Case(
            Subject = 'Expired Case',
            Store__c = store.Id,
            Opportunity__c = store.Opportunity__c,
            RecordTypeId = rtId
        );

        Test.startTest();
        try {
            insert c;
            System.assert(false, 'Expected date validation error');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Case can only be created between')
            );
        }
        Test.stopTest();
    }
}