trigger StoreOpportunityAccountLinkTrigger on Store__c(
  before insert,
  before update
) {
  try {
    StoreOpportunityAccountLinkService.populateBlankAccounts(Trigger.new);
  } catch (Exception ex) {
    ApplicationErrorLogger.capture(ex, 'StoreOpportunityAccountLinkTrigger');
    throw ex;
  }
}
