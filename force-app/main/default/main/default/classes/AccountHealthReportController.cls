/**
 * AccountHealthReportController
 * Apex controller for the accountHealthReportSender LWC component.
 *
 * Methods
 * ─────────────────────────────────────────────────────────────────
 *  getReportData(accountId)             – queries Account + Owner + primary Contact
 *  sendReportEmail(toEmail, reportJson) – builds branded HTML email and sends it
 *
 * Brand colours: Navy #102542 | Orange #FF9900
 */
public with sharing class AccountHealthReportController {

    // =========================================================================
    // INNER WRAPPER — serialised to / from JSON between LWC and Apex
    // =========================================================================
    public class ReportData {
        // ── Report header ──────────────────────────────────────────────────
        @AuraEnabled public String accountId        { get; set; }
        @AuraEnabled public String accountName      { get; set; }
        @AuraEnabled public String accountManager   { get; set; }
        @AuraEnabled public String reportDate       { get; set; }
        @AuraEnabled public String reportStart      { get; set; }
        @AuraEnabled public String reportEnd        { get; set; }
        @AuraEnabled public String reportType       { get; set; }
        @AuraEnabled public String contactEmail     { get; set; }

        // ── Account Health ─────────────────────────────────────────────────
        @AuraEnabled public String currentHealth    { get; set; }
        @AuraEnabled public String healthThisPeriod { get; set; }
        @AuraEnabled public String healthLastPeriod { get; set; }
        @AuraEnabled public String healthChange     { get; set; }

        // ── Solved Issues ──────────────────────────────────────────────────
        @AuraEnabled public String solvedFeedbackRemoval    { get; set; }
        @AuraEnabled public String solvedViolation          { get; set; }
        @AuraEnabled public String solvedListingIssue       { get; set; }
        @AuraEnabled public String solvedAzClaim            { get; set; }
        @AuraEnabled public String solvedBrandApproval      { get; set; }
        @AuraEnabled public String solvedBrandRemoval       { get; set; }
        @AuraEnabled public String solvedBrandGating        { get; set; }
        @AuraEnabled public String solvedCustomerMessage    { get; set; }
        @AuraEnabled public String solvedShippingComplaint  { get; set; }
        @AuraEnabled public String solvedStorageIncrease    { get; set; }
        @AuraEnabled public String solvedChargeback         { get; set; }
        @AuraEnabled public String totalIssuesFixed         { get; set; }

        // ── New & Ongoing Issues ───────────────────────────────────────────
        @AuraEnabled public String ongoingViolation         { get; set; }
        @AuraEnabled public String ongoingListingIssue      { get; set; }
        @AuraEnabled public String ongoingAzClaim           { get; set; }
        @AuraEnabled public String ongoingBrandApproval     { get; set; }
        @AuraEnabled public String ongoingFeedbackRemoval   { get; set; }
        @AuraEnabled public String ongoingBrandRemoval      { get; set; }
        @AuraEnabled public String ongoingBrandGating       { get; set; }
        @AuraEnabled public String ongoingCustomerMessage   { get; set; }
        @AuraEnabled public String ongoingShippingComplaint { get; set; }
        @AuraEnabled public String ongoingStorageIncrease   { get; set; }
        @AuraEnabled public String ongoingChargeback        { get; set; }
        @AuraEnabled public String totalNewOngoing          { get; set; }
    }


    // =========================================================================
    // getReportData
    // Called on component load. Queries the Account and pre-fills header fields.
    // Issue counts are left at '0' / 'N/A' for the user to fill in.
    // =========================================================================
    @AuraEnabled(cacheable=true)
    public static ReportData getReportData(String accountId) {
        try {
            Account acc = [
                SELECT  Id, Name, Owner.Name,
                        (SELECT Id, Email FROM Contacts
                         WHERE Email != null
                         ORDER BY CreatedDate DESC LIMIT 1)
                FROM    Account
                WHERE   Id = :accountId
                LIMIT   1
            ];

            ReportData d        = new ReportData();
            d.accountId         = acc.Id;
            d.accountName       = acc.Name;
            d.accountManager    = acc.Owner.Name;
            d.reportDate        = Date.today().format();
            d.reportType        = 'Monthly';
            d.reportStart       = '';
            d.reportEnd         = '';
            d.contactEmail      = (!acc.Contacts.isEmpty() && acc.Contacts[0].Email != null)
                                    ? acc.Contacts[0].Email : '';

            // ── Health defaults ───────────────────────────────────────────
            d.currentHealth     = '1000';
            d.healthThisPeriod  = '1000';
            d.healthLastPeriod  = '1000';
            d.healthChange      = '0';

            // ── Solved defaults ───────────────────────────────────────────
            d.solvedFeedbackRemoval    = '0';
            d.solvedViolation          = '0';
            d.solvedListingIssue       = '0';
            d.solvedAzClaim            = '0';
            d.solvedBrandApproval      = 'N/A';
            d.solvedBrandRemoval       = 'N/A';
            d.solvedBrandGating        = 'N/A';
            d.solvedCustomerMessage    = '0';
            d.solvedShippingComplaint  = 'N/A';
            d.solvedStorageIncrease    = 'N/A';
            d.solvedChargeback         = '0';
            d.totalIssuesFixed         = '0';

            // ── Ongoing defaults ──────────────────────────────────────────
            d.ongoingViolation         = '0';
            d.ongoingListingIssue      = '0';
            d.ongoingAzClaim           = '0';
            d.ongoingBrandApproval     = 'N/A';
            d.ongoingFeedbackRemoval   = '0';
            d.ongoingBrandRemoval      = 'N/A';
            d.ongoingBrandGating       = 'N/A';
            d.ongoingCustomerMessage   = '0';
            d.ongoingShippingComplaint = 'N/A';
            d.ongoingStorageIncrease   = 'N/A';
            d.ongoingChargeback        = '0';
            d.totalNewOngoing          = '0';

            return d;

        } catch (Exception e) {
            throw new AuraHandledException('Error loading account data: ' + e.getMessage());
        }
    }


    // =========================================================================
    // sendReportEmail
    // Deserialises the ReportData JSON sent from the LWC, builds the HTML body,
    // and dispatches via Messaging.SingleEmailMessage.
    // =========================================================================
    @AuraEnabled
    public static void sendReportEmail(String toEmail, String reportJson) {
        try {
            if (String.isBlank(toEmail)) {
                throw new AuraHandledException('Recipient email address is required.');
            }

            ReportData d = (ReportData) JSON.deserialize(reportJson, ReportData.class);

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ toEmail.trim() });
            mail.setSenderDisplayName('Appeals Doctor');
            mail.setSubject(
                'Account Health Management Report — ' +
                d.accountName +
                (String.isNotBlank(d.reportStart) ? ' (' + d.reportStart + ' – ' + d.reportEnd + ')' : '')
            );
            mail.setHtmlBody(buildEmailHtml(d));

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error sending email: ' + e.getMessage());
        }
    }


    // =========================================================================
    // buildEmailHtml  — private
    // Reproduces the exact same branded HTML email layout.
    // Uses a List<String> + join to avoid Apex 4 MB string heap limits.
    // =========================================================================
    private static String buildEmailHtml(ReportData d) {
        List<String> h = new List<String>();

        h.add('<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/>');
        h.add('<meta name="viewport" content="width=device-width,initial-scale=1.0"/>');
        h.add('<title>Account Health Management Report</title></head>');
        h.add('<body style="margin:0;padding:0;background-color:#f0f2f5;font-family:Arial,Helvetica,sans-serif;">');

        // ── Outer wrapper ─────────────────────────────────────────────────────
        h.add('<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f0f2f5;padding:32px 16px;">');
        h.add('<tr><td align="center">');

        // ── Card ──────────────────────────────────────────────────────────────
        h.add('<table width="700" cellpadding="0" cellspacing="0" border="0" style="max-width:700px;background-color:#ffffff;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,0.08);">');

        // ── Header ────────────────────────────────────────────────────────────
        h.add('<tr><td style="background-color:#102542;padding:28px 40px 20px;border-radius:12px 12px 0 0;">');
        h.add('<table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>');
        h.add('<td><img src="https://www.appealsdoctor.com/wp-content/uploads/2023/10/appeals-doctor-logo-white.png" alt="Appeals Doctor" width="180" style="display:block;max-width:180px;"/></td>');
        h.add('<td align="right" valign="bottom"><p style="margin:0;color:#FF9900;font-size:10px;font-weight:700;letter-spacing:2px;text-transform:uppercase;font-family:Arial,sans-serif;">');
        h.add('Account Management&nbsp;&bull;&nbsp;Suspensions&nbsp;&bull;&nbsp;Listing Violations&nbsp;&bull;&nbsp;Advertising&nbsp;&bull;&nbsp;Trademarks</p></td>');
        h.add('</tr></table>');
        h.add('<p style="margin:18px 0 0;color:#ffffff;font-size:20px;font-weight:700;letter-spacing:0.5px;font-family:Arial,sans-serif;">Account Health Management Report</p>');
        h.add('</td></tr>');

        // ── Orange accent bar ─────────────────────────────────────────────────
        h.add('<tr><td style="background-color:#FF9900;height:4px;font-size:1px;line-height:1px;">&nbsp;</td></tr>');

        // ── Meta table ────────────────────────────────────────────────────────
        h.add('<tr><td style="padding:24px 40px 8px;">');
        h.add('<table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #d0d7e2;border-radius:8px;overflow:hidden;">');
        h.add('<tr style="background-color:#102542;">');
        h.add(metaTh('Account Name') + metaTh('Account Manager') + metaTh('Report Date') + metaTh('Report Type'));
        h.add('</tr><tr style="background-color:#f8f9fb;">');
        h.add(metaTd(d.accountName) + metaTd(d.accountManager) + metaTd(d.reportDate) + metaTd(d.reportType));
        h.add('</tr><tr style="background-color:#ffffff;">');
        h.add('<td colspan="2" style="padding:10px 16px;color:#555555;font-size:12px;font-family:Arial,sans-serif;">');
        h.add('<span style="color:#888888;font-size:11px;text-transform:uppercase;letter-spacing:1px;">Period Start:</span>&nbsp;<strong>' + esc(d.reportStart) + '</strong></td>');
        h.add('<td colspan="2" style="padding:10px 16px;color:#555555;font-size:12px;font-family:Arial,sans-serif;">');
        h.add('<span style="color:#888888;font-size:11px;text-transform:uppercase;letter-spacing:1px;">Period End:</span>&nbsp;<strong>' + esc(d.reportEnd) + '</strong></td>');
        h.add('</tr></table></td></tr>');

        // ── Section label ─────────────────────────────────────────────────────
        h.add('<tr><td style="padding:24px 40px 0;">');
        h.add('<p style="margin:0;color:#102542;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:2px;font-family:Arial,sans-serif;border-top:3px solid #FF9900;padding-top:12px;">Account Activity Details</p>');
        h.add('</td></tr>');

        // ── Two-column body ───────────────────────────────────────────────────
        h.add('<tr><td style="padding:16px 40px 0;">');
        h.add('<table width="100%" cellpadding="0" cellspacing="0" border="0"><tr valign="top">');

        // ── LEFT: Activity table ──────────────────────────────────────────────
        h.add('<td width="55%" style="padding-right:12px;">');
        h.add('<table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #d0d7e2;border-radius:8px;overflow:hidden;">');

        // Column headers
        h.add('<tr style="background-color:#102542;">');
        h.add('<td style="padding:9px 14px;color:#ffffff;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1px;font-family:Arial,sans-serif;width:60%;">Type</td>');
        h.add('<td align="center" style="padding:9px 14px;color:#ffffff;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1px;font-family:Arial,sans-serif;width:20%;">Qty</td>');
        h.add('<td style="padding:9px 14px;color:#ffffff;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1px;font-family:Arial,sans-serif;width:20%;">Notes</td>');
        h.add('</tr>');

        // Solved sub-header
        h.add('<tr style="background-color:#e8f0fe;"><td colspan="3" style="padding:7px 14px;color:#102542;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1.5px;font-family:Arial,sans-serif;">&#10003;&nbsp;Solved Issues</td></tr>');

        // Solved rows
        h.add(activityRow('Feedback Removal', d.solvedFeedbackRemoval, true));
        h.add(activityRow('Violation',         d.solvedViolation,        false));
        h.add(activityRow('Listing Issue',      d.solvedListingIssue,     true));
        h.add(activityRow('A-Z Claim',          d.solvedAzClaim,          false));
        h.add(activityRow('Brand Approval',     d.solvedBrandApproval,    true));
        h.add(activityRow('Brand Removal',      d.solvedBrandRemoval,     false));
        h.add(activityRow('Brand Gating',       d.solvedBrandGating,      true));
        h.add(activityRow('Customer Message',   d.solvedCustomerMessage,  false));
        h.add(activityRow('Shipping Complaint', d.solvedShippingComplaint,true));
        h.add(activityRow('Storage Increase',   d.solvedStorageIncrease,  false));
        h.add(activityRow('Chargeback',         d.solvedChargeback,       true));

        // Total Fixed
        h.add('<tr style="background-color:#102542;">');
        h.add('<td style="padding:9px 14px;color:#ffffff;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;font-family:Arial,sans-serif;">Total Issues Fixed</td>');
        h.add('<td align="center" style="padding:9px 14px;color:#FF9900;font-size:14px;font-weight:700;font-family:Arial,sans-serif;">' + esc(d.totalIssuesFixed) + '</td>');
        h.add('<td style="padding:9px 14px;font-family:Arial,sans-serif;">&nbsp;</td></tr>');

        // Ongoing sub-header
        h.add('<tr style="background-color:#fff3e0;"><td colspan="3" style="padding:7px 14px;color:#b85c00;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1.5px;font-family:Arial,sans-serif;">&#9888;&nbsp;New &amp; Ongoing Issues</td></tr>');

        // Ongoing rows
        h.add(activityRow('Full Account Audit', '—',                        true));
        h.add(activityRow('Violation',          d.ongoingViolation,         false));
        h.add(activityRow('Listing Issue',       d.ongoingListingIssue,      true));
        h.add(activityRow('A-Z Claim',           d.ongoingAzClaim,           false));
        h.add(activityRow('Brand Approval',      d.ongoingBrandApproval,     true));
        h.add(activityRow('Feedback Removal',    d.ongoingFeedbackRemoval,   false));
        h.add(activityRow('Brand Removal',       d.ongoingBrandRemoval,      true));
        h.add(activityRow('Brand Gating',        d.ongoingBrandGating,       false));
        h.add(activityRow('Customer Message',    d.ongoingCustomerMessage,   true));
        h.add(activityRow('Shipping Complaint',  d.ongoingShippingComplaint, false));
        h.add(activityRow('Storage Increase',    d.ongoingStorageIncrease,   true));
        h.add(activityRow('Chargeback',          d.ongoingChargeback,        false));

        // Total Ongoing
        h.add('<tr style="background-color:#b85c00;">');
        h.add('<td style="padding:9px 14px;color:#ffffff;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;font-family:Arial,sans-serif;">Total New &amp; Ongoing Issues</td>');
        h.add('<td align="center" style="padding:9px 14px;color:#ffffff;font-size:14px;font-weight:700;font-family:Arial,sans-serif;">' + esc(d.totalNewOngoing) + '</td>');
        h.add('<td style="padding:9px 14px;font-family:Arial,sans-serif;">&nbsp;</td></tr>');

        h.add('</table></td>');
        // /LEFT

        // ── RIGHT: Health panel ───────────────────────────────────────────────
        h.add('<td width="45%" valign="top" style="padding-left:12px;">');

        // Health score card
        h.add('<table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #d0d7e2;border-radius:8px;overflow:hidden;margin-bottom:12px;">');
        h.add('<tr style="background-color:#102542;"><td colspan="2" style="padding:9px 14px;color:#FF9900;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1.5px;font-family:Arial,sans-serif;">Account Health</td></tr>');
        h.add('<tr style="background-color:#f8f9fb;"><td style="padding:20px 14px 8px;color:#888888;font-size:11px;text-transform:uppercase;letter-spacing:1px;font-family:Arial,sans-serif;">Current Score</td>');
        h.add('<td align="right" style="padding:20px 14px 8px;font-family:Arial,sans-serif;"><span style="color:#102542;font-size:32px;font-weight:700;line-height:1;">' + esc(d.currentHealth) + '</span></td></tr>');
        h.add(healthRow('This Reporting Period', d.healthThisPeriod, '#ffffff'));
        h.add(healthRow('Last Reporting Period', d.healthLastPeriod,  '#f8f9fb'));
        h.add(healthRow('Change Since Last Report', d.healthChange,  '#ffffff'));
        h.add('</table>');

        // Summary box
        h.add('<table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #d0d7e2;border-radius:8px;overflow:hidden;">');
        h.add('<tr style="background-color:#102542;"><td colspan="2" style="padding:9px 14px;color:#FF9900;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1.5px;font-family:Arial,sans-serif;">Period Summary</td></tr>');
        h.add('<tr style="background-color:#f0f7f0;"><td style="padding:12px 14px;color:#555555;font-size:11px;text-transform:uppercase;letter-spacing:0.8px;font-family:Arial,sans-serif;border-bottom:1px solid #d0d7e2;">&#10003;&nbsp;Total Issues Fixed</td>');
        h.add('<td align="right" style="padding:12px 14px;color:#2e7d32;font-size:18px;font-weight:700;font-family:Arial,sans-serif;border-bottom:1px solid #d0d7e2;">' + esc(d.totalIssuesFixed) + '</td></tr>');
        h.add('<tr style="background-color:#fff8f0;"><td style="padding:12px 14px;color:#555555;font-size:11px;text-transform:uppercase;letter-spacing:0.8px;font-family:Arial,sans-serif;">&#9888;&nbsp;New &amp; Ongoing</td>');
        h.add('<td align="right" style="padding:12px 14px;color:#b85c00;font-size:18px;font-weight:700;font-family:Arial,sans-serif;">' + esc(d.totalNewOngoing) + '</td></tr>');
        h.add('</table>');

        h.add('</td>');
        // /RIGHT

        h.add('</tr></table></td></tr>');

        // ── Footer ────────────────────────────────────────────────────────────
        h.add('<tr><td style="background-color:#102542;padding:20px 40px;border-top:4px solid #FF9900;border-radius:0 0 12px 12px;margin-top:24px;">');
        h.add('<p style="margin:0 0 8px;color:#FF9900;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1.5px;text-align:center;font-family:Arial,sans-serif;">');
        h.add('Account Management&nbsp;&bull;&nbsp;Suspensions&nbsp;&bull;&nbsp;Listing Violations&nbsp;&bull;&nbsp;Advertising&nbsp;&bull;&nbsp;Trademarks</p>');
        h.add('<p style="margin:0;color:#aaaaaa;font-size:11px;text-align:center;line-height:1.7;font-family:Arial,sans-serif;">');
        h.add('800 SE 4th Ave, Hallandale Beach FL 33009&nbsp;&nbsp;|&nbsp;&nbsp;786.259.0027&nbsp;&nbsp;|&nbsp;&nbsp;');
        h.add('<a href="mailto:Team@appealdoctor.com" style="color:#FF9900;text-decoration:none;">Team@appealdoctor.com</a>');
        h.add('&nbsp;&nbsp;|&nbsp;&nbsp;<a href="https://www.appealsdoctor.com" style="color:#FF9900;text-decoration:none;">www.appealsdoctor.com</a></p>');
        h.add('</td></tr>');

        h.add('</table></td></tr></table>');
        h.add('</body></html>');

        return String.join(h, '');
    }


    // =========================================================================
    // HTML BUILDER HELPERS
    // =========================================================================

    /** Escape HTML special characters */
    private static String esc(String s) {
        if (s == null) { return ''; }
        return s.replace('&', '&amp;')
                .replace('<', '&lt;')
                .replace('>', '&gt;')
                .replace('"', '&quot;');
    }

    /** Meta table header cell */
    private static String metaTh(String label) {
        return '<td style="padding:10px 16px;color:#FF9900;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1.5px;font-family:Arial,sans-serif;">' + esc(label) + '</td>';
    }

    /** Meta table data cell */
    private static String metaTd(String value) {
        return '<td style="padding:10px 16px;color:#102542;font-size:13px;font-weight:700;font-family:Arial,sans-serif;">' + esc(value) + '</td>';
    }

    /** Activity data row (alternating background) */
    private static String activityRow(String label, String qty, Boolean isEven) {
        String bg = isEven ? '#ffffff' : '#fafbfc';
        String qtyColor = (qty != null && qty != 'N/A' && qty != '—') ? '#102542' : '#888888';
        return '<tr style="background-color:' + bg + ';">'
             + '<td style="padding:7px 14px;color:#333333;font-size:12px;font-family:Arial,sans-serif;border-bottom:1px solid #f0f2f5;">' + esc(label) + '</td>'
             + '<td align="center" style="padding:7px 14px;color:' + qtyColor + ';font-size:12px;font-weight:700;font-family:Arial,sans-serif;border-bottom:1px solid #f0f2f5;">' + esc(qty) + '</td>'
             + '<td style="padding:7px 14px;color:#888888;font-size:11px;font-family:Arial,sans-serif;border-bottom:1px solid #f0f2f5;">&nbsp;</td>'
             + '</tr>';
    }

    /** Health panel row */
    private static String healthRow(String label, String value, String bg) {
        return '<tr style="background-color:' + bg + ';">'
             + '<td style="padding:8px 14px;color:#555555;font-size:11px;border-top:1px solid #f0f2f5;font-family:Arial,sans-serif;">' + esc(label) + '</td>'
             + '<td align="right" style="padding:8px 14px;color:#102542;font-size:13px;font-weight:700;border-top:1px solid #f0f2f5;font-family:Arial,sans-serif;">' + esc(value) + '</td>'
             + '</tr>';
    }
}