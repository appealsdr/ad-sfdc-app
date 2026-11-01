public class CaseTriggerControl {
    
    private static TriggerControl__c cs {
        get {
            if (cs == null) {
                cs = TriggerControl__c.getInstance();
            }
            return cs;
        }
        set;
    }
    
    public static Boolean isCaseTriggerEnabled() {
        return cs == null || cs.Case_Trigger_Enabled__c;
    }
    
    public static Boolean isValidateCaseLimitEnabled() {
        return cs == null || cs.Validate_Case__c;
    }
    
    public static Boolean isUpdateTotalCaseEnabled() {
        return cs == null || cs.Update_Total_Case__c;
    }
}