trigger TimeTrackingTrigger on Time_Tracking__c (before insert, before update) {
    TimeTrackingActiveUserService.applyActiveUserKey(Trigger.new);
}
