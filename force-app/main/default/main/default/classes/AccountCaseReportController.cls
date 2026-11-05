/**
 * AccountCaseReportController
 * Extension controller for the AccountCaseReport Visualforce page.
 *
 * URL Parameters
 * ─────────────────────────────────────────────────────────────────
 *  Month   – target month in YYYY-MM format  (default: last month)
 *  pdf     – set to 'false' to render as HTML (default: PDF)
 *
 * Brand colours: Navy #102542 | Orange #FF9900
 */
public with sharing class AccountCaseReportController {

    // =========================================================================
    // INNER WRAPPER — groups closed cases by Record Type for VF iteration
    // =========================================================================
    public class CaseGroup {
        public String recordTypeName { get; set; }
        public List<Case> cases      { get; set; }
        public Integer   caseCount   { get; set; }

        public CaseGroup(String name, List<Case> caseList) {
            this.recordTypeName = name;
            this.cases          = caseList;
            this.caseCount      = caseList.size();
        }
    }

    // =========================================================================
    // PUBLIC PROPERTIES
    // =========================================================================
    public Account           acc               { get; private set; }
    public String            renderMode        { get; private set; }  // 'pdf' or ''
    public String            monthLabel        { get; private set; }  // e.g. "April 2026"
    public Date              monthStart        { get; private set; }
    public Date              monthEnd          { get; private set; }
    public List<CaseGroup>   closedCaseGroups  { get; private set; }
    public List<Case>        inProgressCases   { get; private set; }
    public Integer           totalClosedCases  { get; private set; }
    public Integer           totalOpenCases    { get; private set; }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================
    public AccountCaseReportController(ApexPages.StandardController stdCtrl) {

        // ── PDF / HTML mode ───────────────────────────────────────────────────
        String pdfParam = ApexPages.currentPage().getParameters().get('pdf');
        renderMode = (pdfParam != null && pdfParam.toLowerCase() == 'false') ? '' : 'pdf';

        // ── Month resolution ──────────────────────────────────────────────────
        String monthParam = ApexPages.currentPage().getParameters().get('Month');
        Integer targetYear;
        Integer targetMonth;

        if (String.isBlank(monthParam)) {
            // Default: last calendar month
            Date lastMonth = Date.today().addMonths(-1);
            targetYear  = lastMonth.year();
            targetMonth = lastMonth.month();
        } else {
            try {
                List<String> parts = monthParam.split('-');
                targetYear  = Integer.valueOf(parts[0]);
                targetMonth = Integer.valueOf(parts[1]);
            } catch (Exception e) {
                // Fallback to last month if the param is malformed
                Date lastMonth = Date.today().addMonths(-1);
                targetYear  = lastMonth.year();
                targetMonth = lastMonth.month();
            }
        }

        monthStart = Date.newInstance(targetYear, targetMonth, 1);
        monthEnd   = monthStart.addMonths(1).addDays(-1);

        String[] MONTH_NAMES = new String[]{
            'January','February','March','April','May','June',
            'July','August','September','October','November','December'
        };
        monthLabel = MONTH_NAMES[targetMonth - 1] + ' ' + String.valueOf(targetYear);

        // ── DateTime boundaries for SOQL ─────────────────────────────────────
        DateTime startDt = DateTime.newInstance(monthStart, Time.newInstance(0,  0,  0,   0));
        DateTime endDt   = DateTime.newInstance(monthEnd,   Time.newInstance(23, 59, 59, 999));

        // ── Account query ─────────────────────────────────────────────────────
        Id accId = stdCtrl.getId();
        acc = [
            SELECT  Id, Name, AccountNumber, Owner.Name,
                    Phone, Website,
                    BillingStreet, BillingCity, BillingState,
                    BillingPostalCode, BillingCountry,
                    Industry, Type, Description
            FROM    Account
            WHERE   Id = :accId
            LIMIT   1
        ];

        // ── Closed cases (IsClosed = true) ────────────────────────────────────
        List<Case> closedCases = [
            SELECT  Id, CaseNumber, Subject, Status,
                    RecordType.Name, Priority,
                    CreatedDate, ClosedDate
            FROM    Case
            WHERE   AccountId   = :accId
            AND     IsClosed    = true
            AND     CreatedDate >= :startDt
            AND     CreatedDate <= :endDt
            ORDER BY RecordType.Name NULLS LAST, CreatedDate DESC
        ];

        // Group by Record Type
        Map<String, List<Case>> groupMap = new Map<String, List<Case>>();
        List<String> orderedKeys = new List<String>();

        for (Case c : closedCases) {
            String rtName = (c.RecordType != null && c.RecordType.Name != null)
                            ? c.RecordType.Name : 'No Record Type';
            if (!groupMap.containsKey(rtName)) {
                groupMap.put(rtName, new List<Case>());
                orderedKeys.add(rtName);
            }
            groupMap.get(rtName).add(c);
        }

        closedCaseGroups = new List<CaseGroup>();
        for (String key : orderedKeys) {
            closedCaseGroups.add(new CaseGroup(key, groupMap.get(key)));
        }
        totalClosedCases = closedCases.size();

        // ── In-progress cases (IsClosed = false) ─────────────────────────────
        inProgressCases = [
            SELECT  Id, CaseNumber, Subject, Status,
                    RecordType.Name, Priority,
                    CreatedDate
            FROM    Case
            WHERE   AccountId   = :accId
            AND     IsClosed    = false
            AND     CreatedDate >= :startDt
            AND     CreatedDate <= :endDt
            ORDER BY Priority NULLS LAST, CreatedDate DESC
        ];
        totalOpenCases = inProgressCases.size();
    }
}