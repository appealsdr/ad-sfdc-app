trigger TaskTrigger on Task (after insert, after update, after delete, after undelete) {
    TriggerFrameworkService.triggerObj = 'Task';
    new TaskTriggerHandler().run();
}