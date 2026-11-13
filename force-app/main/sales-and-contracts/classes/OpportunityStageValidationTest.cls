@IsTest
private class OpportunityStageValidationTest {
  @TestSetup
  static void setupData() {
    List<Account> accounts = TestDataFactory.createAccounts(1);
    TestDataFactory.createOpportunities(accounts, 1);
  }

  @IsTest
  static void closedLostRequiresReasonAndNotes() {
    Opportunity opp = [SELECT Id, StageName FROM Opportunity LIMIT 1];
    opp.StageName = 'Closed Lost';

    Database.SaveResult missingBoth = Database.update(opp, false);
    Assert.isFalse(missingBoth.isSuccess());
    String combinedErrors = errors(missingBoth);
    Assert.isTrue(combinedErrors.contains('Select a Loss Reason'));
    Assert.isTrue(combinedErrors.contains('Enter Loss Reason Notes'));

    opp.Loss_Reason__c = firstLossReason();
    Database.SaveResult missingNotes = Database.update(opp, false);
    Assert.isFalse(missingNotes.isSuccess());
    Assert.isTrue(errors(missingNotes).contains('Enter Loss Reason Notes'));

    opp.Loss_Reason_Notes__c = 'Client selected another provider after review.';
    Database.SaveResult complete = Database.update(opp, false);
    Assert.isTrue(complete.isSuccess(), errors(complete));
  }

  private static String firstLossReason() {
    for (
      Schema.PicklistEntry entry : Opportunity.Loss_Reason__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive())
        return entry.getValue();
    }
    Assert.fail('Loss Reason must have at least one active value.');
    return null;
  }

  private static String errors(Database.SaveResult result) {
    List<String> messages = new List<String>();
    for (Database.Error error : result.getErrors()) {
      messages.add(error.getMessage());
    }
    return String.join(messages, ' | ');
  }
}
