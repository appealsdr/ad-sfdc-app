/******************************************************************************
@description: Applies Lead ownership to the Opportunity created by conversion.
******************************************************************************/
public without sharing class LeadConversionOpportunityService {

    public static void applyOwnership(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        Map<Id, Id> opportunityToOpener = new Map<Id, Id>();
        for (Lead lead : newLeads) {
            Lead oldLead = oldMap == null ? null : oldMap.get(lead.Id);
            if (lead.IsConverted && lead.ConvertedOpportunityId != null
                    && (oldLead == null || !oldLead.IsConverted)
                    && lead.OwnerId != null
                    && lead.OwnerId.getSObjectType() == User.SObjectType) {
                opportunityToOpener.put(lead.ConvertedOpportunityId, lead.OwnerId);
            }
        }
        if (opportunityToOpener.isEmpty()) {
            return;
        }

        Boolean setCloserFromManager = isCloserFromManagerEnabled();
        Map<Id, Id> managerByOpener = new Map<Id, Id>();
        if (setCloserFromManager) {
            Set<Id> openerIds = new Set<Id>(opportunityToOpener.values());
            for (User opener : [
                SELECT Id, ManagerId
                FROM User
                WHERE Id IN :openerIds
            ]) {
                managerByOpener.put(opener.Id, opener.ManagerId);
            }
        }

        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        for (Id opportunityId : opportunityToOpener.keySet()) {
            Id openerId = opportunityToOpener.get(opportunityId);
            Opportunity updateRecord = new Opportunity(
                Id = opportunityId,
                Opportunity_Opener__c = openerId
            );
            if (setCloserFromManager && managerByOpener.get(openerId) != null) {
                updateRecord.Opportunity_Closer__c = managerByOpener.get(openerId);
            }
            opportunitiesToUpdate.add(updateRecord);
        }
        update opportunitiesToUpdate;
    }

    @TestVisible
    private static Boolean isCloserFromManagerEnabled() {
        Opportunity_Automation_Settings__c settings =
            Opportunity_Automation_Settings__c.getInstance();
        return settings == null
            || settings.Set_Closer_From_Opener_Manager__c == null
            || settings.Set_Closer_From_Opener_Manager__c;
    }
}
