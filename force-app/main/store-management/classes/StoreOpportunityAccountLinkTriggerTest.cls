@IsTest
private class StoreOpportunityAccountLinkTriggerTest {
  @IsTest
  static void logsAndRethrowsUnexpectedTriggerFailure() {
    ApplicationErrorLogger.publishedEvents.clear();
    StoreOpportunityAccountLinkService.forceFailure = true;

    Test.startTest();
    try {
      insert new Store__c(Name = 'Forced trigger failure');
      Assert.fail('The trigger must rethrow the original exception');
    } catch (DmlException ex) {
      Assert.isTrue(
        ex.getMessage().contains('Forced test failure'),
        'The original service exception should be preserved'
      );
    } finally {
      StoreOpportunityAccountLinkService.forceFailure = false;
    }
    Test.stopTest();

    Assert.areEqual(
      1,
      ApplicationErrorLogger.publishedEvents.size(),
      'The trigger failure should be sent to the application logger'
    );
  }
}
