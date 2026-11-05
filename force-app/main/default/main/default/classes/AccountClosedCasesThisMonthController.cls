public with sharing class AccountClosedCasesThisMonthController {
    public Id accountId { get; set; }

    private Account accountRecord;
    private List<Case> closedCases;

    public Account getAccountRecord() {
        if (accountId == null) {
            return new Account();
        }

        if (accountRecord == null) {
            List<Account> accounts = [
                SELECT Id,
                       Name,
                       AccountNumber,
                       Type,
                       Industry,
                       Phone,
                       Website,
                       BillingStreet,
                       BillingCity,
                       BillingState,
                       BillingPostalCode,
                       BillingCountry,
                       Owner.Name
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
            accountRecord = accounts.isEmpty() ? new Account() : accounts[0];
        }

        return accountRecord;
    }

    public List<Case> getClosedCases() {
        if (accountId == null) {
            return new List<Case>();
        }

        if (closedCases == null) {
            Date firstDayOfMonth = Date.today().toStartOfMonth();
            Date firstDayOfNextMonth = firstDayOfMonth.addMonths(1);

            closedCases = [
                SELECT Id,
                       CaseNumber,
                       Subject,
                       Status,
                       Priority,
                       Origin,
                       Type,
                       CreatedDate,
                       ClosedDate,
                       Owner.Name
                FROM Case
                WHERE AccountId = :accountId
                  AND IsClosed = true
                  AND ClosedDate >= :firstDayOfMonth
                  AND ClosedDate < :firstDayOfNextMonth
                ORDER BY ClosedDate DESC, CaseNumber ASC
            ];
        }

        return closedCases;
    }

    public Boolean getHasClosedCases() {
        return !getClosedCases().isEmpty();
    }

    public String getClosedCasesTitle() {
        return 'Cases Closed in ' + DateTime.now().format('MMMM yyyy');
    }
}