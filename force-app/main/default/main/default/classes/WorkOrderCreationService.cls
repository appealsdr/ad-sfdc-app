/******************************************************************************
@description: Creates a Work Order (with related Work Order Line Items) from
              a Service Contract and its Contract Line Items.
*******************************************************************************/
public with sharing class WorkOrderCreationService {

    private static final String LOG_SOURCE = 'WorkOrderCreationService';

    /**
     * Creates one Work Order for the given Service Contract, and copies each
     * of its Contract Line Items across as a Work Order Line Item.
     *
     * @param serviceContractId Id of the Service Contract to build the Work Order from.
     * @param startDate         Start date to apply to the Work Order and each
     *                           Work Order Line Item.
     * @return the Id of the newly created Work Order, or null if nothing was created.
     */
    public static Id createWorkOrderFromServiceContract(Id serviceContractId, Date startDate) {
        try {
            if (serviceContractId == null || startDate == null) {
                return null;
            }

            List<ServiceContract> serviceContracts = [
                SELECT Id, AccountId, Pricebook2Id,
                       (SELECT Id, PricebookEntryId, Quantity, UnitPrice, Discount, Description
                        FROM ContractLineItems)
                FROM ServiceContract
                WHERE Id = :serviceContractId
            ];

            if (serviceContracts.isEmpty() || serviceContracts[0].ContractLineItems.isEmpty()) {
                return null;
            }

            ServiceContract sc = serviceContracts[0];
            DateTime startDateTime = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
            Date monthStart = Date.newInstance(startDate.year(), startDate.month(), 1);
            Date monthEnd = monthStart.addMonths(1).addDays(-1);
            DateTime lineItemStartDateTime = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
            DateTime lineItemEndDateTime = DateTime.newInstance(monthEnd, Time.newInstance(0, 0, 0, 0));

            WorkOrder wo = new WorkOrder(
                ServiceContractId = sc.Id,
                AccountId = sc.AccountId,
                Pricebook2Id = sc.Pricebook2Id,
                StartDate = startDateTime
            );
            insert wo;

            List<WorkOrderLineItem> woliList = new List<WorkOrderLineItem>();
            for (ContractLineItem cli : sc.ContractLineItems) {
                woliList.add(new WorkOrderLineItem(
                    WorkOrderId = wo.Id,
                    PricebookEntryId = cli.PricebookEntryId,
                    Quantity = cli.Quantity,
                    UnitPrice = cli.UnitPrice,
                    Discount = cli.Discount,
                    Description = cli.Description,
                    StartDate = lineItemStartDateTime,
                    EndDate = lineItemEndDateTime
                ));
            }
            insert woliList;

            return wo.Id;
        } catch (Exception ex) {
            Logger.logException(ex, LOG_SOURCE);
            throw ex;
        }
    }
}