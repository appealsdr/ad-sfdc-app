/**
 * Inbound handler for the Amazon notification mailbox.
 *
 * Standard Email-to-Case always creates a Case when an email cannot be threaded.
 * This service exists so that email is ONLY ever attached to a Case that already
 * exists - it never creates one. Anything that cannot be matched is staged on
 * Performance_Notifications__c for review instead.
 *
 * Matching:
 *   1. The store-specific address Amazon was configured with identifies the Store
 *      (Store__c.Amazon_Notification_Email__c).
 *   2. Within that Store's open Cases, an ASIN found in the email wins.
 *   3. Otherwise the Store's most recently created open Case wins.
 */
global class StoreNotificationEmailToCaseService implements Messaging.InboundEmailHandler {

    private static final Integer BODY_LIMIT = 32000;

    @TestVisible
    private enum MatchOutcome { MATCHED, NO_STORE, NO_CASE, ERROR }

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
       /* Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        // Always accept. Bouncing would send noise back to Amazon, and an
        // unmatched email is a staging record here, not a delivery failure.
        result.success = true;

        try {
            route(email, envelope);
        } catch (Exception e) {
            stage(email, envelope, null, null, null, null,
                  MatchOutcome.ERROR, e.getTypeName() + ': ' + e.getMessage());
        }

        return result;*/
        return null;
    }

    /* =====================================================
       Routing
    ======================================================*/
    private static void route(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {

        String bodyText = bestBody(email);
        String asin = extractASIN(bodyText + ' ' + (email.subject == null ? '' : email.subject));

        /* ---- 1. address -> Store ---- */
        Store__c store = findStore(email, envelope);

        if (store == null) {
            stage(email, envelope, bodyText, asin, null, null, MatchOutcome.NO_STORE,
                  'No Store has an Amazon Notification Email matching this email.');
            return;
        }

        /* ---- 2. Store -> open Case ---- */
        List<Case> openCases = [
            SELECT Id, CaseNumber, ASIN__c, Relevant_ASINS__c
            FROM Case
            WHERE Store__c = :store.Id AND IsClosed = false
            ORDER BY CreatedDate DESC, CaseNumber DESC
        ];

        if (openCases.isEmpty()) {
            stage(email, envelope, bodyText, asin, store, null, MatchOutcome.NO_CASE,
                  'Store ' + store.Name + ' has no open Cases.');
            return;
        }

        Case target = null;
        String detail;

        if (String.isNotBlank(asin)) {
            for (Case c : openCases) {
                if (matchesAsin(c, asin)) {
                    target = c;
                    detail = 'Matched on ASIN ' + asin + '.';
                    break;
                }
            }
        }

        if (target == null) {
            target = openCases[0];
            detail = String.isBlank(asin)
                ? 'No ASIN in email; matched newest open Case.'
                : 'ASIN ' + asin + ' not on any open Case; matched newest open Case.';
        }

        /* ---- 3. attach ---- */
        insert buildEmailMessage(email, envelope, target.Id);

        stage(email, envelope, bodyText, asin, store, target.Id, MatchOutcome.MATCHED,
              detail + ' Case ' + target.CaseNumber + '.');
    }

    /* =====================================================
       Address -> Store
    ======================================================*/
    private static Store__c findStore(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {

        List<String> candidates = candidateAddresses(email, envelope);
        if (candidates.isEmpty()) return null;

        Map<String, Store__c> byAddress = new Map<String, Store__c>();
        for (Store__c st : [
            SELECT Id, Name, Amazon_Notification_Email__c
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
       Case matching helpers
    ======================================================*/
    private static Boolean matchesAsin(Case c, String asin) {
        if (String.isNotBlank(c.ASIN__c) && c.ASIN__c.trim().equalsIgnoreCase(asin)) {
            return true;
        }
        return String.isNotBlank(c.Relevant_ASINS__c) &&
               c.Relevant_ASINS__c.toUpperCase().contains(asin);
    }

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
        Store__c store,
        Id caseId,
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
            Store__c        = store == null ? null : store.Id,
            Case__c         = caseId,
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
        if (outcome == MatchOutcome.NO_CASE)  return 'No Case Match';
        return 'Error';
    }

    private static String truncate(String s) {
        return s == null ? null : s.left(BODY_LIMIT);
    }
}