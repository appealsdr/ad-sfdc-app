public with sharing class PricingVisibilityController {

@AuraEnabled(cacheable=true)
public static Boolean isPricingVisible() {
    
    User u = [
        SELECT Id, Username, Email 
        FROM User 
        WHERE Id = :UserInfo.getUserId()
    ];
    
    List<Field_Visibility_Config__mdt> configs = [
        SELECT User_Name__c, Email__c, Is_Active__c
        FROM Field_Visibility_Config__mdt
        WHERE Is_Active__c = true AND UseCase__c = 'Case Pricing Visibility'
    ];
    
    for(Field_Visibility_Config__mdt c : configs){
        if(c.User_Name__c == u.Username &&
            c.Email__c == u.Email){
            return true;
        }
    }
    
    return false;
}
}