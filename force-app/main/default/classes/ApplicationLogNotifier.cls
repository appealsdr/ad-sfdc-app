/** Resolves the "Application Logs" public group to email addresses and exposes Slack config to Flow. */
public without sharing class ApplicationLogNotifier {
  public class Result {
    @InvocableVariable
    public String emailAddresses;
    @InvocableVariable
    public String slackChannelId;
  }

  @InvocableMethod(label='Resolve Application Log Recipients')
  public static List<Result> resolve(List<String> unused) {
    Result r = new Result();
    Set<Id> userIds = new Set<Id>();
    Set<Id> groupIds = new Set<Id>();
    for (Group g : [
      SELECT Id
      FROM Group
      WHERE DeveloperName = 'Application_Logs' AND Type = 'Regular'
    ]) {
      groupIds.add(g.Id);
    }
    Set<Id> visited = new Set<Id>();
    Integer depth = 0;
    while (!groupIds.isEmpty() && depth < 5) {
      visited.addAll(groupIds);
      Set<Id> next = new Set<Id>();
      for (GroupMember m : [
        SELECT UserOrGroupId
        FROM GroupMember
        WHERE GroupId IN :groupIds
      ]) {
        if (String.valueOf(m.UserOrGroupId).startsWith('005'))
          userIds.add(m.UserOrGroupId);
        else if (!visited.contains(m.UserOrGroupId))
          next.add(m.UserOrGroupId);
      }
      groupIds = next;
      depth++;
    }
    List<String> emails = new List<String>();
    for (User u : [
      SELECT Email
      FROM User
      WHERE Id IN :userIds AND IsActive = TRUE
    ]) {
      emails.add(u.Email);
    }
    r.emailAddresses = String.join(emails, ',');
    Application_Log_Setting__mdt s = Application_Log_Setting__mdt.getInstance(
      'Default'
    );
    r.slackChannelId = s == null ? null : s.Slack_Channel_Id__c;
    return new List<Result>{ r };
  }
}
