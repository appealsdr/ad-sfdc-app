trigger ApplicationErrorEventTrigger on Application_Error_Event__e(
  after insert
) {
  ApplicationErrorLogger.persistEvents(Trigger.new);
}
