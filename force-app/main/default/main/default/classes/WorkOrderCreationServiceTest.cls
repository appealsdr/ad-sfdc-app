@isTest
private class WorkOrderCreationServiceTest {

    @TestSetup
    static void setupTestData() {
        List<Account> accList = TestDataFactory.createAccounts(1);
        PricebookEntry pbe = TestDataFactory.createStandardPricebookEntry(100);

        ServiceContract sc = new ServiceContract(
            Name = 'Test Service Contract',
            AccountId = accList[0].Id,
            StartDate = Date.today(),
            Pricebook2Id = pbe.Pricebook2Id
        );
        insert sc;
        insert new List<ContractLineItem>{
            new ContractLineItem(
                ServiceContractId = sc.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = pbe.UnitPrice
            ),
            new ContractLineItem(
                ServiceContractId = sc.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 2,
                UnitPrice = pbe.UnitPrice
            )
        };
    }

    // Service Contract with Contract Line Items -> one Work Order with matching Work Order Line Items
    @isTest
    static void createsWorkOrderWithLineItems() {
        ServiceContract sc = [SELECT Id FROM ServiceContract LIMIT 1];
        Date startDate = Date.today().addDays(5);

        Test.startTest();
        Id workOrderId = WorkOrderCreationService.createWorkOrderFromServiceContract(sc.Id, startDate);
        Test.stopTest();

        WorkOrder wo = [SELECT Id, StartDate, ServiceContractId, AccountId FROM WorkOrder WHERE Id = :workOrderId];
        System.assertEquals(sc.Id, wo.ServiceContractId, 'Work Order should be linked to the Service Contract');
        System.assertEquals(startDate, wo.StartDate.date(), 'Work Order start date should match the supplied date');

        Date expectedMonthStart = Date.newInstance(startDate.year(), startDate.month(), 1);
        Date expectedMonthEnd = expectedMonthStart.addMonths(1).addDays(-1);

        List<WorkOrderLineItem> woliList = [
            SELECT Id, Quantity, UnitPrice, Product2Id, StartDate, EndDate FROM WorkOrderLineItem WHERE WorkOrderId = :workOrderId
        ];
        System.assertEquals(2, woliList.size(), 'Both Contract Line Items should be copied to the Work Order');
        for (WorkOrderLineItem woli : woliList) {
            System.assertNotEquals(null, woli.Product2Id, 'Work Order Line Item should carry over the Product from the Contract Line Item');
            System.assertEquals(expectedMonthStart, woli.StartDate.date(), 'Work Order Line Item start date should be the first day of the month');
            System.assertEquals(expectedMonthEnd, woli.EndDate.date(), 'Work Order Line Item end date should be the last day of the month');
        }
    }

    // Service Contract with no Contract Line Items -> no Work Order created
    @isTest
    static void serviceContractWithoutLineItemsCreatesNothing() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ServiceContract scNoLines = new ServiceContract(
            Name = 'No Lines Service Contract',
            AccountId = acc.Id,
            StartDate = Date.today()
        );
        insert scNoLines;

        Test.startTest();
        Id workOrderId = WorkOrderCreationService.createWorkOrderFromServiceContract(scNoLines.Id, Date.today());
        Test.stopTest();

        System.assertEquals(null, workOrderId, 'No Work Order should be created when the Service Contract has no Contract Line Items');
    }

    // No Service Contract Id supplied -> no Work Order created
    @isTest
    static void noServiceContractIdCreatesNothing() {
        Test.startTest();
        Id workOrderId = WorkOrderCreationService.createWorkOrderFromServiceContract(null, Date.today());
        Test.stopTest();

        System.assertEquals(null, workOrderId, 'No Work Order should be created when no Service Contract Id is supplied');
    }
}