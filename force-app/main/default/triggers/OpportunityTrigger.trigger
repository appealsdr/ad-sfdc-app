trigger OpportunityTrigger on Opportunity (before insert, before update, before delete, after insert, after Update, after delete, after undelete) { 
    TriggerFrameworkService.triggerObj = 'Opportunity';
    new OpportunityTriggerHandler().run();
}