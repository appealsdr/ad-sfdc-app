/**
 * Pulls the Quo (OpenPhone) conversation for Tasks that carry a Quo call and/or
 * conversation id and writes the result into Task.Description.
 *
 * Run once:   Database.executeBatch(new QuoConversationBatch(), 10);
 * Schedule:   System.schedule('Quo Conversation Sync', '0 0 * * * ?', new QuoConversationBatch());
 *
 * Tasks are picked up while Description is blank; once populated they are skipped.
 * The API key lives in the protected hierarchy custom setting Quo_Setting__c.
 */
public with sharing class QuoConversationBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

    @TestVisible private static final String BASE_URL = 'https://api.openphone.com/v1';
    private static final Integer MAX_DESCRIPTION = 32000;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Quo_Call_Id__c, Quo_ConversationId__c, Description
            FROM Task
            WHERE (Quo_Call_Id__c != NULL OR Quo_ConversationId__c != NULL)
              
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Task> scope) {
        String apiKey = Quo_Setting__c.getInstance().Api_Key__c;
        if (String.isBlank(apiKey)) {
            System.debug(LoggingLevel.ERROR, 'QuoConversationBatch: Quo_Setting__c.Api_Key__c is not set');
            return;
        }

        List<Task> toUpdate = new List<Task>();
        for (Task t : scope) {
            try {
                List<String> parts = new List<String>();
                if (String.isNotBlank(t.Quo_ConversationId__c)) {
                    String convo = fetchConversation(apiKey, t.Quo_ConversationId__c);
                    if (convo != null) { parts.add(convo); }
                }
                if (String.isNotBlank(t.Quo_Call_Id__c)) {
                    String call = fetchCallTranscript(apiKey, t.Quo_Call_Id__c);
                    if (call != null) { parts.add(call); }
                }
                if (!parts.isEmpty()) {
                    t.Description = String.join(parts, '\n\n').abbreviate(MAX_DESCRIPTION);
                    toUpdate.add(t);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'QuoConversationBatch: task ' + t.Id + ' failed: ' + e.getMessage());
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    public void finish(Database.BatchableContext bc) {}

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new QuoConversationBatch(), 10);
    }

    // GET /v1/conversations/{id} -> participants + last activity
    private static String fetchConversation(String apiKey, String conversationId) {
        Map<String, Object> body = get(apiKey, '/conversations/' + EncodingUtil.urlEncode(conversationId, 'UTF-8'));
        if (body == null) { return null; }
        Map<String, Object> data = (Map<String, Object>) body.get('data');
        if (data == null) { return null; }
        String text = 'Quo conversation ' + conversationId;
        if (data.get('participants') != null) {
            text += '\nParticipants: ' + String.join((List<Object>) data.get('participants'), ', ');
        }
        if (data.get('lastActivityAt') != null) {
            text += '\nLast activity: ' + data.get('lastActivityAt');
        }
        return text;
    }

    // GET /v1/call-transcripts/{callId} -> dialogue lines
    private static String fetchCallTranscript(String apiKey, String callId) {
        Map<String, Object> body = get(apiKey, '/call-transcripts/' + EncodingUtil.urlEncode(callId, 'UTF-8'));
        if (body == null) { return null; }
        Map<String, Object> data = (Map<String, Object>) body.get('data');
        if (data == null || data.get('dialogue') == null) { return null; }
        List<String> lines = new List<String>{ 'Quo call transcript ' + callId };
        for (Object o : (List<Object>) data.get('dialogue')) {
            Map<String, Object> d = (Map<String, Object>) o;
            String who = String.valueOf(d.get('identifier') != null ? d.get('identifier') : d.get('userId'));
            lines.add(who + ': ' + d.get('content'));
        }
        return String.join(lines, '\n');
    }

    private static Map<String, Object> get(String apiKey, String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + path);
        req.setMethod('GET');
        req.setHeader('Authorization', apiKey);
        req.setHeader('Accept', 'application/json');
        req.setTimeout(30000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 404) { return null; }
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException('Quo API ' + path + ' returned ' + res.getStatusCode());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
}