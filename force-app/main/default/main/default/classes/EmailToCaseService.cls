/**
 * Inbound handler for the Amazon violation-notification mailbox.
 *
 * Unlike StoreNotificationEmailToCaseService (which only ever attaches mail to
 * an existing open Case and never creates one), this handler CREATES a new
 * Case for every email whose recipient address matches a Store's configured
 * notification address.
 *
 * Matching:
 *   1. The store-specific address the email was sent to identifies the Store
 *      (Store__c.Amazon_Notification_Email__c).
 *   2. On match, a Case is created and linked to that Store, its Account, and
 *      its Contact, with the Case owner set to the Store owner. Any ASIN
 *      found in the subject/body is captured on Case.ASIN__c.
 *   3. When no Store matches the recipient address, no Case is created; the
 *      email is staged on Performance_Notifications__c for manual review.
 */
global class EmailToCaseService implements Messaging.InboundEmailHandler {

    private static final Integer BODY_LIMIT = 32000;

    @TestVisible
    private enum MatchOutcome { MATCHED, NO_STORE, ERROR }

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        // Always accept. Bouncing would send noise back to Amazon, and an
        // unmatched email is a staging record here, not a delivery failure.
        result.success = true;

        try {
            route(email, envelope);
        } catch (Exception e) {
            stage(email, envelope, null, null, MatchOutcome.ERROR,
                  e.getTypeName() + ': ' + e.getMessage());
        }

        return result;
    }

    /* =====================================================
       Routing
    ======================================================*/
    private static void route(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {

        String bodyText = bestBody(email);
        String asin = extractASIN(bodyText + ' ' + (email.subject == null ? '' : email.subject));

        Store__c store = findStore(email, envelope);

        if (store == null) {
            stage(email, envelope, bodyText, asin, MatchOutcome.NO_STORE,
                  'No Store has an Amazon Notification Email matching this email.');
            return;
        }

        Case newCase = new Case(
            Subject     = String.isBlank(email.subject) ? 'No Subject' : email.subject.left(255),
            Description = truncate(bodyText),
            ASIN__c     = asin,
            Store__c    = store.Id,
            AccountId   = store.Account__c,
            ContactId   = store.Contact__c,
            OwnerId     = store.OwnerId
        );
        insert newCase;

        insert buildEmailMessage(email, envelope, newCase.Id);
    }

    /* =====================================================
       Address -> Store
    ======================================================*/
    private static Store__c findStore(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {

        List<String> candidates = candidateAddresses(email, envelope);
        if (candidates.isEmpty()) return null;

        Map<String, Store__c> byAddress = new Map<String, Store__c>();
        for (Store__c st : [
            SELECT Id, Name, Amazon_Notification_Email__c, Account__c, Contact__c, OwnerId
            FROM Store__c
            WHERE Amazon_Notification_Email__c IN :candidates
        ]) {
            byAddress.put(st.Amazon_Notification_Email__c.toLowerCase(), st);
        }

        if (byAddress.isEmpty()) return null;

        // Walk candidates in priority order so the envelope recipient beats
        // a CC or the sender when more than one address maps to a Store.
        for (String addr : candidates) {
            if (byAddress.containsKey(addr)) {
                return byAddress.get(addr);
            }
        }
        return null;
    }

    /**
     * Every address the store-specific value could plausibly arrive on, in
     * priority order. Forwarding from the notification mailbox often rewrites
     * the To line, so the forwarding headers are checked too.
     */
    @TestVisible
    private static List<String> candidateAddresses(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {

        List<String> ordered = new List<String>();
        Set<String> seen = new Set<String>();

        if (envelope != null) addAddress(ordered, seen, envelope.toAddress);
        addAddresses(ordered, seen, email.toAddresses);

        if (email.headers != null) {
            for (Messaging.InboundEmail.Header h : email.headers) {
                if (h.name == null) continue;
                String n = h.name.toLowerCase();
                if (n == 'delivered-to' || n == 'x-forwarded-to' ||
                    n == 'x-original-to' || n == 'x-forwarded-for' || n == 'x-apparently-to') {
                    addAddress(ordered, seen, h.value);
                }
            }
        }

        addAddresses(ordered, seen, email.ccAddresses);
        addAddress(ordered, seen, email.fromAddress);

        return ordered;
    }

    private static void addAddresses(List<String> ordered, Set<String> seen, List<String> raw) {
        if (raw == null) return;
        for (String r : raw) {
            addAddress(ordered, seen, r);
        }
    }

    private static void addAddress(List<String> ordered, Set<String> seen, String raw) {
        String addr = normalizeAddress(raw);
        if (addr != null && !seen.contains(addr)) {
            seen.add(addr);
            ordered.add(addr);
        }
    }

    /** 'Store Name <store+1@x.com>' -> 'store+1@x.com' */
    @TestVisible
    private static String normalizeAddress(String raw) {
        if (String.isBlank(raw)) return null;

        String addr = raw.trim();
        Matcher m = Pattern.compile('<([^>]+)>').matcher(addr);
        if (m.find()) {
            addr = m.group(1).trim();
        }
        return addr.contains('@') ? addr.toLowerCase() : null;
    }

    /* =====================================================
       ASIN extraction
    ======================================================*/
    @TestVisible
    private static String extractASIN(String text) {
        if (String.isBlank(text)) return null;

        Matcher m = Pattern.compile('\\bASIN\\s*[:\\-]?\\s*([A-Z0-9]{10})\\b')
                           .matcher(text.toUpperCase());
        return m.find() ? m.group(1) : null;
    }

    private static String bestBody(Messaging.InboundEmail email) {
        return String.isNotBlank(email.plainTextBody) ? email.plainTextBody : email.htmlBody;
    }

    /* =====================================================
       Record building
    ======================================================*/
    private static EmailMessage buildEmailMessage(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope,
        Id caseId
    ) {
        return new EmailMessage(
            ParentId    = caseId,
            Incoming    = true,
            Status      = '0',                       // New
            MessageDate = System.now(),
            Subject     = String.isBlank(email.subject) ? 'No Subject' : email.subject.left(255),
            FromAddress = email.fromAddress,
            FromName    = email.fromName,
            ToAddress   = envelope != null ? envelope.toAddress : null,
            TextBody    = truncate(email.plainTextBody),
            HtmlBody    = truncate(email.htmlBody)
        );
    }

    private static void stage(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope,
        String bodyText,
        String asin,
        MatchOutcome outcome,
        String detail
    ) {
        String subject = String.isBlank(email.subject) ? 'No Subject' : email.subject;

        Performance_Notifications__c pn = new Performance_Notifications__c(
            Name            = subject.left(80),
            Subject__c      = subject,
            From_Address__c = email.fromAddress,
            To_Address__c   = envelope != null ? envelope.toAddress : null,
            Date__c         = System.now().format('dd MMM yyyy HH:mm:ss'),
            Body__c         = truncate(bodyText == null ? bestBody(email) : bodyText),
            ASIN__c         = asin,
            Match_Status__c = label(outcome),
            Match_Detail__c = detail == null ? null : detail.left(255)
        );

        if (pn.Body__c == null) {
            pn.Body__c = 'No Body';
        }

        insert pn;
    }

    private static String label(MatchOutcome outcome) {
        if (outcome == MatchOutcome.MATCHED)  return 'Matched';
        if (outcome == MatchOutcome.NO_STORE) return 'No Store Match';
        return 'Error';
    }

    private static String truncate(String s) {
        return s == null ? null : s.left(BODY_LIMIT);
    }
}