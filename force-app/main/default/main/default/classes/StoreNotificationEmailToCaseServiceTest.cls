@IsTest
private class StoreNotificationEmailToCaseServiceTest {

    private static final String STORE_ADDRESS = 'seller-alpha@notifications.example.com';

    @TestSetup
    static void setupData() {

        // The Case trigger is off by default; leave it off so these tests
        // exercise the email service alone.
        insert new TriggerControl__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Case_Trigger_Enabled__c = false
        );

        // The Case_BeforeSave flow forces Status = 'Draft' on insert, and the
        // Case_Custom_Error flow then blocks any status change unless the
        // Case's Opportunity has a signed Contract. Give the Store one so
        // these tests can close a Case.
        Opportunity opp = new Opportunity(
            Name = 'Alpha Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert opp;

        insert new Contract__c(
            Opportunity__c = opp.Id,
            Status__c = 'Signed'
        );

        insert new Store__c(
            Name = 'Alpha Store',
            Opportunity__c = opp.Id,
            Amazon_Notification_Email__c = STORE_ADDRESS
        );
    }

    /* =====================================================
       Helpers
    ======================================================*/
    private static Messaging.InboundEmail buildEmail(String subject, String body, List<String> toAddresses) {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = subject;
        email.plainTextBody = body;
        email.fromAddress = 'notice@amazon.com';
        email.fromName = 'Amazon Seller Central';
        email.toAddresses = toAddresses;
        return email;
    }

    private static Messaging.InboundEnvelope buildEnvelope(String toAddress) {
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        env.fromAddress = 'notice@amazon.com';
        env.toAddress = toAddress;
        return env;
    }

    private static Messaging.InboundEmailResult run(Messaging.InboundEmail email, Messaging.InboundEnvelope env) {
        return new StoreNotificationEmailToCaseService().handleInboundEmail(email, env);
    }

    private static Case newCase(Id storeId, String asin) {
        return new Case(Store__c = storeId, ASIN__c = asin, Subject = 'Case for ' + asin);
    }

    /* =====================================================
       Matching
    ======================================================*/
    @IsTest
    static void attachesToOpenCaseMatchingAsin() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Case other = newCase(store.Id, 'B000000001');
        Case wanted = newCase(store.Id, 'B0B6P34PB9');
        insert new List<Case>{ other, wanted };

        Test.startTest();
        Messaging.InboundEmailResult res = run(
            buildEmail('Policy warning', 'Your listing ASIN: B0B6P34PB9 was removed.',
                       new List<String>{ STORE_ADDRESS }),
            buildEnvelope(STORE_ADDRESS)
        );
        Test.stopTest();

        System.assertEquals(true, res.success, 'Handler should accept the email');

        List<EmailMessage> msgs = [SELECT Id, ParentId, Incoming, Subject FROM EmailMessage];
        System.assertEquals(1, msgs.size(), 'One EmailMessage should be created');
        System.assertEquals(wanted.Id, msgs[0].ParentId, 'Should attach to the ASIN-matching Case');
        System.assertEquals(true, msgs[0].Incoming, 'Inbound email should be flagged incoming');

        Performance_Notifications__c pn = [
            SELECT Match_Status__c, Case__c, Store__c, ASIN__c FROM Performance_Notifications__c
        ];
        System.assertEquals('Matched', pn.Match_Status__c, 'Should be logged as matched');
        System.assertEquals(wanted.Id, pn.Case__c, 'Staging record should point at the Case');
        System.assertEquals('B0B6P34PB9', pn.ASIN__c, 'ASIN should be captured');
    }

    @IsTest
    static void fallsBackToNewestOpenCaseWithoutAsin() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Case older = newCase(store.Id, 'B000000001');
        Case newest = newCase(store.Id, 'B000000002');
        // Separate DML so the CaseNumber tiebreaker orders them predictably.
        insert older;
        insert newest;

        Test.startTest();
        run(buildEmail('General notice', 'No product identifier in this message.',
                       new List<String>{ STORE_ADDRESS }),
            buildEnvelope(STORE_ADDRESS));
        Test.stopTest();

        EmailMessage msg = [SELECT ParentId FROM EmailMessage];
        System.assertEquals(newest.Id, msg.ParentId, 'Should fall back to the newest open Case');

        Performance_Notifications__c pn = [SELECT Match_Status__c FROM Performance_Notifications__c];
        System.assertEquals('Matched', pn.Match_Status__c, 'Fallback still counts as matched');
    }

    @IsTest
    static void ignoresClosedCasesWhenMatchingAsin() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Case closedWithAsin = newCase(store.Id, 'B0B6P34PB9');
        Case openOther = newCase(store.Id, 'B000000009');
        insert new List<Case>{ closedWithAsin, openOther };

        closedWithAsin.Status = 'Closed';
        update closedWithAsin;

        Test.startTest();
        run(buildEmail('Policy warning', 'ASIN: B0B6P34PB9 flagged.',
                       new List<String>{ STORE_ADDRESS }),
            buildEnvelope(STORE_ADDRESS));
        Test.stopTest();

        EmailMessage msg = [SELECT ParentId FROM EmailMessage];
        System.assertEquals(openOther.Id, msg.ParentId,
            'Closed Cases are not eligible, so the open Case wins');
    }

    /* =====================================================
       Never creates a Case
    ======================================================*/
    @IsTest
    static void unknownAddressIsStagedAndCreatesNoCase() {

        Integer casesBefore = [SELECT COUNT() FROM Case];

        Test.startTest();
        run(buildEmail('Stray notice', 'ASIN: B0B6P34PB9',
                       new List<String>{ 'nobody@notifications.example.com' }),
            buildEnvelope('nobody@notifications.example.com'));
        Test.stopTest();

        System.assertEquals(casesBefore, [SELECT COUNT() FROM Case],
            'Unmatched email must never create a Case');
        System.assertEquals(0, [SELECT COUNT() FROM EmailMessage],
            'Unmatched email must not create an EmailMessage');

        Performance_Notifications__c pn = [
            SELECT Match_Status__c, Store__c, Case__c FROM Performance_Notifications__c
        ];
        System.assertEquals('No Store Match', pn.Match_Status__c, 'Should be staged as unmatched');
        System.assertEquals(null, pn.Store__c, 'No Store should be linked');
        System.assertEquals(null, pn.Case__c, 'No Case should be linked');
    }

    @IsTest
    static void storeWithNoOpenCasesIsStaged() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];

        Test.startTest();
        run(buildEmail('Notice', 'ASIN: B0B6P34PB9', new List<String>{ STORE_ADDRESS }),
            buildEnvelope(STORE_ADDRESS));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Case], 'No Case should be created');
        System.assertEquals(0, [SELECT COUNT() FROM EmailMessage], 'No EmailMessage without a Case');

        Performance_Notifications__c pn = [
            SELECT Match_Status__c, Store__c FROM Performance_Notifications__c
        ];
        System.assertEquals('No Case Match', pn.Match_Status__c, 'Should be staged as no Case match');
        System.assertEquals(store.Id, pn.Store__c, 'Store is known even when no Case matched');
    }

    /* =====================================================
       Address resolution
    ======================================================*/
    @IsTest
    static void matchesStoreAddressFromForwardingHeader() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Case c = newCase(store.Id, 'B000000001');
        insert c;

        // Mailbox forwarding rewrote the To line; the original recipient
        // survives only in a Delivered-To header.
        Messaging.InboundEmail email = buildEmail('Forwarded notice', 'Body text',
            new List<String>{ 'notifications-inbox@example.com' });

        Messaging.InboundEmail.Header h = new Messaging.InboundEmail.Header();
        h.name = 'Delivered-To';
        h.value = STORE_ADDRESS;
        email.headers = new List<Messaging.InboundEmail.Header>{ h };

        Test.startTest();
        run(email, buildEnvelope('notifications-inbox@example.com'));
        Test.stopTest();

        EmailMessage msg = [SELECT ParentId FROM EmailMessage];
        System.assertEquals(c.Id, msg.ParentId, 'Should match the Store from the forwarding header');
    }

    @IsTest
    static void matchesStoreAddressWrappedInDisplayName() {

        Store__c store = [SELECT Id FROM Store__c LIMIT 1];
        Case c = newCase(store.Id, 'B000000001');
        insert c;

        Test.startTest();
        run(buildEmail('Notice', 'Body text',
                       new List<String>{ 'Alpha Store <' + STORE_ADDRESS.toUpperCase() + '>' }),
            buildEnvelope(null));
        Test.stopTest();

        EmailMessage msg = [SELECT ParentId FROM EmailMessage];
        System.assertEquals(c.Id, msg.ParentId,
            'Display-name wrapping and casing should not defeat the match');
    }

    @IsTest
    static void blankEmailIsHandledWithoutThrowing() {

        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = null;
        email.plainTextBody = null;

        Test.startTest();
        Messaging.InboundEmailResult res = run(email, null);
        Test.stopTest();

        System.assertEquals(true, res.success, 'A malformed email should still be accepted');

        Performance_Notifications__c pn = [
            SELECT Subject__c, Body__c, Match_Status__c FROM Performance_Notifications__c
        ];
        System.assertEquals('No Subject', pn.Subject__c, 'Subject should fall back');
        System.assertEquals('No Body', pn.Body__c, 'Body should fall back');
        System.assertEquals('No Store Match', pn.Match_Status__c, 'Nothing to match on');
    }
}