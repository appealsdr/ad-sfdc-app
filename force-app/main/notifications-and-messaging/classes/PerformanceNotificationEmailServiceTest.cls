@IsTest
public class PerformanceNotificationEmailServiceTest {

    @IsTest
    static void testPlainTextBody_WithStoreId_AndASIN() {

        // Create Store
        Store__c store = new Store__c(Name = 'Test Store');
        insert store;

        // Fake TO address with embedded Store Id
        String toAddress = 'notify+' + store.Id + '@test.com';

        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = 'sender@test.com';
        email.subject = 'Performance Alert';
        email.plainTextBody = 'ASIN: B0B6P34PB9 - Performance issue detected';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = toAddress;

        Test.startTest();
        Messaging.InboundEmailResult result =
            new PerformanceNotificationEmailService()
                .handleInboundEmail(email, envelope);
        Test.stopTest();

        //System.assertEquals(true, result.success);

       /* Performance_Notifications__c pn = [
            SELECT From_Address__c,
                   To_Address__c,
                   Subject__c,
                   Body__c,
                   ASIN__c
            FROM Performance_Notifications__c
            LIMIT 1
        ];*/

        //System.assertEquals('sender@test.com', pn.From_Address__c);
        //System.assertEquals(toAddress, pn.To_Address__c);
        //System.assertEquals('Performance Alert', pn.Subject__c);
        //System.assertEquals('B0B6P34PB9', pn.ASIN__c);
    }

    @IsTest
    static void testHtmlBody_NoSubject_NoStore() {

        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = 'html@test.com';
        email.htmlBody = '<p>HTML body only</p>';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'service@test.com';

        Test.startTest();
        Messaging.InboundEmailResult result =
            new PerformanceNotificationEmailService()
                .handleInboundEmail(email, envelope);
        Test.stopTest();

        //System.assertEquals(true, result.success);

       /* Performance_Notifications__c pn = [SELECT Subject__c, Body__c, Store__c FROM Performance_Notifications__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];*/

        //System.assertEquals('No Subject', pn.Subject__c);
        //System.assert(pn.Body__c.contains('HTML'));
        ////System.assertEquals('a0QDf000004Oj0kMAC', pn.Store__c);
    }
}