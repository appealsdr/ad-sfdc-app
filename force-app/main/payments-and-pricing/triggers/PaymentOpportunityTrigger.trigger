trigger PaymentOpportunityTrigger on Payment__c(
  before insert,
  before update,
  after insert,
  after update
) {
  try {
    if (Trigger.isBefore) {
      PaymentOpportunityService.populateOpportunity(Trigger.new);
    }
    if (Trigger.isAfter) {
      PaymentOpportunityService.closePaidOpportunities(
        Trigger.new,
        Trigger.isUpdate ? (Map<Id, Payment__c>) Trigger.oldMap : null
      );
      PaymentOpportunityService.updateContractPaidAmounts(
        Trigger.new,
        Trigger.isUpdate ? (Map<Id, Payment__c>) Trigger.oldMap : null
      );
      PaymentOpportunityService.createCasesForFirstPayments(
        Trigger.new,
        Trigger.isUpdate ? (Map<Id, Payment__c>) Trigger.oldMap : null
      );
    }
  } catch (Exception ex) {
    ApplicationErrorLogger.capture(ex, 'PaymentOpportunityTrigger');
    throw ex;
  }
}
