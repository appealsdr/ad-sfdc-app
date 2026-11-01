@IsTest
private class QuoConversationBatchTest {

    private class QuoMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            if (req.getEndpoint().contains('/call-transcripts/')) {
                res.setBody('{"data":{"dialogue":[{"identifier":"+15551234567","content":"Hello there"}]}}');
            } else {
                res.setBody('{"data":{"participants":["+15551234567"],"lastActivityAt":"2026-01-01T00:00:00Z"}}');
            }
            return res;
        }
    }

    @IsTest
    static void populatesDescription() {
        insert new Quo_Setting__c(SetupOwnerId = UserInfo.getOrganizationId(), Api_Key__c = 'test-key');
        Task t = new Task(Subject = 'Call', Quo_Call_Id__c = 'AC123', Quo_ConversationId__c = 'CN123');
        insert t;

        Test.setMock(HttpCalloutMock.class, new QuoMock());
        Test.startTest();
        Database.executeBatch(new QuoConversationBatch(), 10);
        Test.stopTest();

        Task r = [SELECT Description FROM Task WHERE Id = :t.Id];
        System.assert(r.Description.contains('Hello there'));
        System.assert(r.Description.contains('Participants'));
    }

    @IsTest
    static void skipsWhenNoApiKey() {
        Task t = new Task(Subject = 'Call', Quo_Call_Id__c = 'AC123');
        insert t;
        Test.setMock(HttpCalloutMock.class, new QuoMock());
        Test.startTest();
        Database.executeBatch(new QuoConversationBatch(), 10);
        Test.stopTest();
        System.assertEquals(null, [SELECT Description FROM Task WHERE Id = :t.Id].Description);
    }

    @IsTest
    static void schedulableRuns() {
        Test.startTest();
        System.schedule('QuoTest', '0 0 0 1 1 ? 2099', new QuoConversationBatch());
        Test.stopTest();
    }
}