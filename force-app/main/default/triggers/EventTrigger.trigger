trigger EventTrigger on Event (after insert, after update, after delete, after undelete) {
    TriggerFrameworkService.triggerObj = 'Event';
    new EventTriggerHandler().run();
}