trigger LeadConversionTrigger on Lead (after update) {
    LeadConversionOpportunityService.applyOwnership(Trigger.new, Trigger.oldMap);
}
