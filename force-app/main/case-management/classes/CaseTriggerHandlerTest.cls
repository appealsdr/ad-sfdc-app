@IsTest
public class CaseTriggerHandlerTest {

    @TestSetup
    static void setupData() {

        /* -------------------------
           Enable the Case trigger
           (checkbox defaults are false,
            so tests must opt in)
        --------------------------*/
        insert new TriggerControl__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Case_Trigger_Enabled__c = true,
            Update_Total_Case__c = true,
            Validate_Case__c = false
        );

        /* -------------------------
           Create Opportunity
        --------------------------*/
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert opp;

        /* -------------------------
           Create Store
        --------------------------*/
        Store__c store = new Store__c(
            Name = 'Test Store',
            Opportunity__c = opp.Id
        );
        insert store;

        /* -------------------------
           Signed Contract so the
           Case_Custom_Error flow lets
           Cases be closed
        --------------------------*/
        insert new Contract__c(
            Opportunity__c = opp.Id,
            Status__c = 'Signed'
        );

        /* -------------------------
           Create Service
           (Service__c.Store__c stores Opportunity Id in your logic)
        --------------------------*/
        Service__c service = new Service__c(
            Name = 'Test Service',
            Store__c = opp.Id
        );
        insert service;

        /* -------------------------
           Get Existing Case RecordType
        --------------------------*/
        RecordType rt = [
            SELECT Id, Name 
            FROM RecordType 
            WHERE SObjectType = 'Case'
            LIMIT 1
        ];

        /* -------------------------
           Create Retainer
        --------------------------*/
        Retainer_Service__c rs = new Retainer_Service__c(
            Service__c = service.Id,
            Case_Record_Type__c = rt.Name,
            Start_Date__c = Date.today().addDays(-5),
            End_Date__c = Date.today().addDays(5),
            Total_Case__c = 0
        );
        insert rs;

        /* -------------------------
           Create Case
        --------------------------*/
        Case c = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Store__c = store.Id,
            Opportunity__c = opp.Id,
            RecordTypeId = rt.Id
        );
        insert c;
    }

    /* =====================================
       TEST METHOD
    ======================================*/
    @IsTest
    static void testUpdateTotalCases() {

        // Fetch inserted case
        Case c = [SELECT Id, Store__c FROM Case LIMIT 1];

        Test.startTest();
        CaseTriggerHandler.updateTotalCases(
            new List<Case>{c},
            null
        );
        Test.stopTest();

        // Verify Retainer updated
        Retainer_Service__c rs = [
            SELECT Id, Total_Case__c 
            FROM Retainer_Service__c 
            LIMIT 1
        ];

        System.assertEquals(1, rs.Total_Case__c,
            'Retainer total case count should be 1');
    }

    /* =====================================
       STORE LEVEL CASE COUNTS
    ======================================*/
    @IsTest
    static void testStoreCaseCountsOnInsert() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        // One open Case already exists from @TestSetup
        Store__c storeBefore = [
            SELECT Total_Cases__c, Total_Open_Cases__c, Total_Closed_Cases__c
            FROM Store__c WHERE Id = :store.Id
        ];
        System.assertEquals(1, storeBefore.Total_Cases__c, 'Setup Case should be counted');
        System.assertEquals(1, storeBefore.Total_Open_Cases__c, 'Setup Case should be open');
        System.assertEquals(0, storeBefore.Total_Closed_Cases__c, 'No closed Cases yet');

        Test.startTest();
        insert new Case(Subject = 'Second Case', Status = 'New', Store__c = store.Id);
        Test.stopTest();

        Store__c storeAfter = [
            SELECT Total_Cases__c, Total_Open_Cases__c, Total_Closed_Cases__c
            FROM Store__c WHERE Id = :store.Id
        ];
        System.assertEquals(2, storeAfter.Total_Cases__c, 'Both Cases should be counted');
        System.assertEquals(2, storeAfter.Total_Open_Cases__c, 'Both Cases should be open');
        System.assertEquals(0, storeAfter.Total_Closed_Cases__c, 'No closed Cases yet');
    }

    @IsTest
    static void testStoreCaseCountsOnClose() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Case c = [SELECT Id, Status FROM Case LIMIT 1];

        Test.startTest();
        c.Status = 'Closed';
        update c;
        Test.stopTest();

        Store__c st = [
            SELECT Total_Cases__c, Total_Open_Cases__c, Total_Closed_Cases__c
            FROM Store__c WHERE Id = :store.Id
        ];
        System.assertEquals(1, st.Total_Cases__c, 'Total should stay at 1');
        System.assertEquals(0, st.Total_Open_Cases__c, 'Case is no longer open');
        System.assertEquals(1, st.Total_Closed_Cases__c, 'Case should count as closed');
    }

    @IsTest
    static void testStoreCaseCountsOnDeleteAndUndelete() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        delete c;

        Store__c storeAfterDelete = [
            SELECT Total_Cases__c, Total_Open_Cases__c, Total_Closed_Cases__c
            FROM Store__c WHERE Id = :store.Id
        ];
        System.assertEquals(0, storeAfterDelete.Total_Cases__c, 'Deleted Case should not count');
        System.assertEquals(0, storeAfterDelete.Total_Open_Cases__c, 'Deleted Case should not count as open');

        undelete c;
        Test.stopTest();

        Store__c storeAfterUndelete = [
            SELECT Total_Cases__c, Total_Open_Cases__c, Total_Closed_Cases__c
            FROM Store__c WHERE Id = :store.Id
        ];
        System.assertEquals(1, storeAfterUndelete.Total_Cases__c, 'Undeleted Case should count again');
        System.assertEquals(1, storeAfterUndelete.Total_Open_Cases__c, 'Undeleted Case should count as open');
    }

    @IsTest
    static void testStoreCaseCountsOnReparent() {

        Store__c oldStore = [SELECT Id, Opportunity__c FROM Store__c LIMIT 1];
        Store__c newStore = new Store__c(Name = 'Other Store', Opportunity__c = oldStore.Opportunity__c);
        insert newStore;

        Case c = [SELECT Id, Store__c FROM Case LIMIT 1];

        Test.startTest();
        c.Store__c = newStore.Id;
        update c;
        Test.stopTest();

        Map<Id, Store__c> stores = new Map<Id, Store__c>([
            SELECT Total_Cases__c, Total_Open_Cases__c
            FROM Store__c WHERE Id IN (:oldStore.Id, :newStore.Id)
        ]);

        System.assertEquals(0, stores.get(oldStore.Id).Total_Cases__c,
            'Previous Store should be decremented');
        System.assertEquals(1, stores.get(newStore.Id).Total_Cases__c,
            'New Store should be incremented');
        System.assertEquals(1, stores.get(newStore.Id).Total_Open_Cases__c,
            'New Store Case should be open');
    }
}