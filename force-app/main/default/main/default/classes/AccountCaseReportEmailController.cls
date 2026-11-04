/**
 * AccountCaseReportEmailController
 * Apex controller for the accountCaseReport LWC.
 *
 * Responsibilities
 * ────────────────────────────────────────────────────────────────
 *  · getOrgBaseUrl      — returns the org domain URL so the LWC can build
 *                        the correct iframe src for the VF page preview.
 *  · getFromEmailOptions — returns available "From" senders:
 *                            – Current user's email (value = 'CURRENT_USER')
 *                            – Active Org-Wide Email Addresses (value = OWA Id)
 *  · getEmailOptions   — collects all "To" email addresses for the Account:
 *                            – Account-level email (PersonEmail / custom field)
 *                            – All Contact emails linked to the Account
 *  · sendReport        — renders AccountCaseReport.page as a PDF blob, sends it
 *                        as an email attachment to the chosen address (with the
 *                        chosen From sender), and creates a completed Email Task
 *                        on the Account (+ WhoId when the recipient matches a Contact).
 * ────────────────────────────────────────────────────────────────
 */
public with sharing class AccountCaseReportEmailController {

    // =========================================================================
    // INNER CLASSES — shapes returned to lightning-combobox
    // =========================================================================

    /** "To" recipient option — email address label + email value. */
    public class EmailOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public EmailOption(String lbl, String val) {
            this.label = lbl;
            this.value = val;
        }
    }

    /**
     * "From" sender option.
     * value = 'CURRENT_USER'   → send as the logged-in user (default SF behaviour)
     * value = <OWA Id (15/18)> → use that Org-Wide Email Address
     * email is stored separately so the LWC can display it in the preview chip.
     */
    public class FromEmailOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }   // 'CURRENT_USER' or OWA Id
        @AuraEnabled public String email { get; set; }   // address shown in preview

        public FromEmailOption(String lbl, String val, String emailAddr) {
            this.label = lbl;
            this.value = val;
            this.email = emailAddr;
        }
    }

    /** Sentinel value used when the current user is selected as the sender. */
    private static final String CURRENT_USER_SENTINEL = 'CURRENT_USER';


    // =========================================================================
    // GET ORG BASE URL
    // Used by the LWC to build the iframe src for the VF page preview.
    // =========================================================================
    @AuraEnabled(cacheable=true)
    public static String getOrgBaseUrl() {
        return URL.getOrgDomainUrl().toExternalForm();
    }


    // =========================================================================
    // GET FROM EMAIL OPTIONS
    // Returns the current user's email first, then all active Org-Wide Email
    // Addresses accessible to this user, sorted by display name.
    // =========================================================================
    @AuraEnabled(cacheable=true)
    public static List<FromEmailOption> getFromEmailOptions() {
        List<FromEmailOption> options = new List<FromEmailOption>();

        // ── 1. Current user (always the first / default option) ───────────────
        User currentUser = [
            SELECT Id, Name, Email
            FROM   User
            WHERE  Id = :UserInfo.getUserId()
            LIMIT  1
        ];
        options.add(new FromEmailOption(
            currentUser.Name + ' (Me)',
            CURRENT_USER_SENTINEL,
            currentUser.Email
        ));

        // ── 2. Active Org-Wide Email Addresses ────────────────────────────────
        // IsAllowAllProfiles = true  → available to every profile.
        // Per-profile OWA restrictions use the ProfileOrgWideEmailAddress
        // junction which isn't directly queryable here, so we surface all
        // "allow all profiles" addresses; admins can tighten via profiles.
        for (OrgWideEmailAddress owa : [
            SELECT Id, DisplayName, Address
            FROM   OrgWideEmailAddress
            WHERE  IsAllowAllProfiles = true
            ORDER BY DisplayName
        ]) {
            options.add(new FromEmailOption(
                owa.DisplayName + ' <' + owa.Address + '>',
                String.valueOf(owa.Id),
                owa.Address
            ));
        }

        return options;
    }


    // =========================================================================
    // GET EMAIL OPTIONS
    // Returns Account email (if present) + all related Contact emails.
    // =========================================================================
    @AuraEnabled(cacheable=true)
    public static List<EmailOption> getEmailOptions(Id accountId) {
        List<EmailOption> options = new List<EmailOption>();

        // ── Account email ─────────────────────────────────────────────────────
        // Standard Account has no Email field; Person Accounts expose PersonEmail.
        // We probe the schema and fall back gracefully.
        String accEmail = null;
        String accName  = '';

        Map<String, Schema.SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();

        // Priority: PersonEmail → Email__c → (skip)
        String emailField = null;
        for (String candidate : new List<String>{ 'personEmail', 'email__c', 'email' }) {
            if (accFields.containsKey(candidate)) {
                emailField = candidate;
                break;
            }
        }

        if (emailField != null) {
            String q = 'SELECT Id, Name, ' + emailField + ' FROM Account WHERE Id = :accountId LIMIT 1';
            SObject accObj = Database.query(q);
            accName  = (String) accObj.get('Name');
            accEmail = (String) accObj.get(emailField);
        } else {
            accName = [SELECT Name FROM Account WHERE Id = :accountId LIMIT 1].Name;
        }

        if (String.isNotBlank(accEmail)) {
            options.add(new EmailOption(accName + ' (Account)', accEmail));
        }

        // ── Contact emails ────────────────────────────────────────────────────
        for (Contact c : [
            SELECT Id, Name, Email
            FROM   Contact
            WHERE  AccountId = :accountId
            AND    Email     != null
            ORDER BY Name
        ]) {
            if (String.isNotBlank(c.Email)) {
                options.add(new EmailOption(c.Name + ' (Contact)', c.Email));
            }
        }

        return options;
    }


    // =========================================================================
    // SEND REPORT
    // Renders the VF page as PDF, emails it, and logs an Email activity Task.
    // NOTE: getContent() is internally a callout — all DML must come AFTER it.
    // =========================================================================
    @AuraEnabled
    public static void sendReport(Id accountId, String recipientEmail, String monthParam, String fromOwaId) {
        try {
            // ── 1. SOQL — must happen BEFORE the getContent() callout ─────────
            Account acc = [
                SELECT Id, Name
                FROM   Account
                WHERE  Id = :accountId
                LIMIT  1
            ];

            // Try to find a matching Contact for WhoId on the Task
            List<Contact> matchContacts = [
                SELECT Id
                FROM   Contact
                WHERE  AccountId = :accountId
                AND    Email     = :recipientEmail
                LIMIT  1
            ];

            // Resolve the From sender label for the Task description
            String fromLabel = 'Current User';
            if (String.isNotBlank(fromOwaId) && fromOwaId != CURRENT_USER_SENTINEL) {
                List<OrgWideEmailAddress> owas = [
                    SELECT DisplayName, Address
                    FROM   OrgWideEmailAddress
                    WHERE  Id = :fromOwaId
                    LIMIT  1
                ];
                if (!owas.isEmpty()) {
                    fromLabel = owas[0].DisplayName + ' <' + owas[0].Address + '>';
                }
            }

            // ── 2. Render VF page as PDF (callout — no DML before this) ──────
            PageReference pageRef = Page.AccountCaseReport;
            pageRef.getParameters().put('id',    String.valueOf(accountId));
            if (String.isNotBlank(monthParam)) {
                pageRef.getParameters().put('Month', monthParam);
            }

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                // getContent() is unavailable in tests — use placeholder
                pdfBlob = Blob.valueOf('PDF_PLACEHOLDER');
            } else {
                pdfBlob = pageRef.getContent();
            }

            // ── 3. Build and send the email ───────────────────────────────────
            String periodLabel = String.isNotBlank(monthParam) ? monthParam : 'last month';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ recipientEmail });
            mail.setSubject('Account Case Report – ' + acc.Name + ' (' + periodLabel + ')');
            mail.setHtmlBody(
                '<p>Please find attached the Account Case Report for ' +
                '<strong>' + acc.Name + '</strong> — period: <em>' + periodLabel + '</em>.</p>' +
                '<p>Best regards,<br/>AppealsDr Team</p>'
            );
            // Apply From sender — OWA overrides the default current-user sender
            if (String.isNotBlank(fromOwaId) && fromOwaId != CURRENT_USER_SENTINEL) {
                mail.setOrgWideEmailAddressId(fromOwaId);
            }
            mail.setSaveAsActivity(false);   // Task created manually below

            Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
            attach.setFileName('AccountCaseReport_' +
                acc.Name.replaceAll('[^a-zA-Z0-9]', '_') + '_' +
                periodLabel.replace('-', '_') + '.pdf');
            attach.setBody(pdfBlob);
            attach.setContentType('application/pdf');
            mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attach });

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });

            // ── 4. Create Email Activity Task (DML after callout is allowed) ──
            Task t        = new Task();
            t.Subject     = 'Email: Account Case Report – ' + acc.Name;
            t.WhatId      = accountId;
            t.Status      = 'Completed';
            t.Priority    = 'Normal';
            t.ActivityDate = Date.today();
            t.Type        = 'Email';
            t.Description = 'Account Case Report PDF sent to: ' + recipientEmail +
                            ' | From: ' + fromLabel +
                            ' | Period: ' + periodLabel;
            if (!matchContacts.isEmpty()) {
                t.WhoId = matchContacts[0].Id;
            }
            insert t;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error sending report: ' + e.getMessage());
        }
    }
}