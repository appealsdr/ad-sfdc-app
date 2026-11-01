@IsTest
public class CaseTriggerControlTest {

   
    /* ---------------------------------------
       Test When All CheckBox TRUE
    ----------------------------------------*/
    @IsTest
    static void CheckBoxTrueTest() {

        TriggerControl__c setting = new TriggerControl__c(
            SetupOwnerId = UserInfo.getOrganizationId(), // Required for hierarchy setting
            Case_Trigger_Enabled__c = true,
            Validate_Case__c = true,
            Update_Total_Case__c = true
        );
        insert setting;

        Test.startTest();
        System.assertEquals(true, CaseTriggerControl.isCaseTriggerEnabled());
        System.assertEquals(true, CaseTriggerControl.isValidateCaseLimitEnabled());
        System.assertEquals(true, CaseTriggerControl.isUpdateTotalCaseEnabled());
        Test.stopTest();
    }

    /* ---------------------------------------
       Test When All CheckBox FALSE
    ----------------------------------------*/
    @IsTest
    static void CheckBoxFalseTest() {

        TriggerControl__c setting = new TriggerControl__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Case_Trigger_Enabled__c = false,
            Validate_Case__c = false,
            Update_Total_Case__c = false
        );
        insert setting;

        Test.startTest();
        System.assertEquals(false, CaseTriggerControl.isCaseTriggerEnabled());
        System.assertEquals(false, CaseTriggerControl.isValidateCaseLimitEnabled());
        System.assertEquals(false, CaseTriggerControl.isUpdateTotalCaseEnabled());
        Test.stopTest();
    }
}