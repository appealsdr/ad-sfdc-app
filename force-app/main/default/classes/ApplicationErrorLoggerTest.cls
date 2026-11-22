@IsTest
private class ApplicationErrorLoggerTest {
  private static Exception boom() {
    try {
      throw new IllegalArgumentException('boom password=hunter2 a@b.com');
    } catch (Exception e) {
      return e;
    }
  }

  @IsTest
  static void captureBuildsEventWithMappedFieldsAndSanitizes() {
    List<Account> accts = new List<Account>{
      new Account(Name = 'A'),
      new Account(Name = 'B')
    };
    insert accts;
    String cid = ApplicationErrorLogger.capture(
      boom(),
      'CaseTrigger',
      'Account',
      'AFTER_INSERT',
      accts
    );
    // second capture of same failure must not publish again
    ApplicationErrorLogger.capture(boom(), 'CaseTrigger', 'Account', 'AFTER_INSERT', accts);
    System.assertEquals(1, ApplicationErrorLogger.publishedEvents.size());
    Application_Error_Event__e e = ApplicationErrorLogger.publishedEvents[0];
    System.assertEquals(cid, e.Correlation_Id__c);
    System.assertEquals('Trigger:CaseTrigger', e.Component_Name__c);
    System.assert(e.Error__c.contains('IllegalArgumentException'));
    System.assert(!e.Error__c.contains('hunter2'));
    System.assert(!e.Error__c.contains('a@b.com'));
    System.assert(e.Body__c.contains(cid));
    System.assert(e.Body__c.contains(accts[0].Id));
    System.assert(e.Body__c.contains('"recordCount":2'));
    System.assert(e.Response__c.contains('OriginalTransaction=RolledBack'));
  }

  @IsTest
  static void correlationIdIsDeterministic() {
    Exception e = boom();
    System.assertEquals(
      ApplicationErrorLogger.buildCorrelationId('r', 'c', 'o', e),
      ApplicationErrorLogger.buildCorrelationId('r', 'c', 'o', e)
    );
  }

  @IsTest
  static void truncateRespectsLimit() {
    String big = 'x'.repeat(40000);
    Integer max = Application_Log__c.Error__c.getDescribe().getLength();
    System.assertEquals(max, ApplicationErrorLogger.truncate(big, max).length());
    System.assertEquals('short', ApplicationErrorLogger.truncate('short', max));
  }

  @IsTest
  static void publishedEventCreatesExactlyOneLog() {
    Test.startTest();
    ApplicationErrorLogger.capture(boom(), 'CaseTrigger', 'Case', 'AFTER_INSERT', null);
    Test.getEventBus().deliver();
    Test.stopTest();
    List<Application_Log__c> logs = [
      SELECT Component_Name__c, Error__c, Body__c, Response__c
      FROM Application_Log__c
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals('Trigger:CaseTrigger', logs[0].Component_Name__c);
    System.assert(logs[0].Error__c.contains('boom'));
  }

  @IsTest
  static void duplicateEventsInOneBatchCreateOneLog() {
    Application_Error_Event__e e = new Application_Error_Event__e(
      Correlation_Id__c = 'ERR-1',
      Component_Name__c = 'Trigger:X',
      Error__c = 'e',
      Body__c = 'b',
      Response__c = 'r'
    );
    ApplicationErrorLogger.persistEvents(
      new List<Application_Error_Event__e>{ e, e }
    );
    System.assertEquals(1, [SELECT COUNT() FROM Application_Log__c]);
  }

  @IsTest
  static void logTransportFailureDoesNotThrow() {
    ApplicationErrorLogger.forcePublishFailure = true;
    String cid = ApplicationErrorLogger.capture(boom(), 'T', 'Case', 'AFTER_INSERT', null);
    System.assertNotEquals(null, cid);
  }

  @IsTest
  static void applicationLogObjectIsNotLoggedRecursively() {
    System.assertEquals(
      null,
      ApplicationErrorLogger.capture(boom(), 'T', 'Application_Log__c', 'AFTER_INSERT', null)
    );
    System.assertEquals(0, ApplicationErrorLogger.publishedEvents.size());
  }

  @IsTest
  static void successfulTransactionCreatesNoLog() {
    Test.startTest();
    insert new Account(Name = 'ok');
    Test.getEventBus().deliver();
    Test.stopTest();
    System.assertEquals(0, [SELECT COUNT() FROM Application_Log__c]);
  }

  @IsTest
  static void notifierResolvesGroupMembers() {
    Group g = [SELECT Id FROM Group WHERE DeveloperName = 'Application_Logs' LIMIT 1];
    List<ApplicationLogNotifier.Result> r = ApplicationLogNotifier.resolve(
      new List<String>{ 'x' }
    );
    System.assertEquals(1, r.size());
    System.assertNotEquals(null, g);
  }
}
