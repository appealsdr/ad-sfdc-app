public with sharing class ContractLineItemPaymentService {
  private static final String DEPOSIT_CONFIG = 'Deposit';
  private static final String FULL_PRICE_CONFIG = 'Full Price';
  private static final String FIRST_PAYMENT_TYPE = 'First Payment';
  private static final String BALANCE_TYPE = 'Balance';
  private static final String REQUEST_PAYMENT_STATUS = 'Request Payment';
  private static final String DEFERRED_STATUS = 'Not Active';

  public static void createInitialPayments(
    List<ContractLineItem> insertedLines
  ) {
    if (insertedLines == null || insertedLines.isEmpty() || isFormAppUser())
      return;

    Set<Id> contractIds = new Set<Id>();
    for (ContractLineItem line : insertedLines) {
      if (line.ServiceContractId != null)
        contractIds.add(line.ServiceContractId);
    }
    if (contractIds.isEmpty())
      return;

    excludeFormAppContracts(contractIds);
    if (contractIds.isEmpty())
      return;

    Map<Id, List<ContractLineItem>> linesByContract = new Map<Id, List<ContractLineItem>>();
    for (ContractLineItem line : [
      SELECT
        Id,
        ServiceContractId,
        ServiceContract.Opportunity__c,
        Quantity,
        UnitPrice,
        Discount,
        TotalPrice,
        Deposit__c,
        PricebookEntry.Name,
        PricebookEntry.Payment_type__c,
        PricebookEntry.Deposit__c
      FROM ContractLineItem
      WHERE ServiceContractId IN :contractIds
    ]) {
      if (!linesByContract.containsKey(line.ServiceContractId)) {
        linesByContract.put(
          line.ServiceContractId,
          new List<ContractLineItem>()
        );
      }
      linesByContract.get(line.ServiceContractId).add(line);
    }

    Map<String, Payment__c> existingByReference = new Map<String, Payment__c>();
    for (Payment__c payment : [
      SELECT
        Id,
        Amount__c,
        Order_Ref__c,
        Payment_Type__c,
        Status__c
      FROM Payment__c
      WHERE Service_Contract__c IN :contractIds AND Order_Ref__c != NULL
    ]) {
      existingByReference.put(payment.Order_Ref__c, payment);
    }

    List<Payment__c> paymentsToInsert = new List<Payment__c>();
    List<Payment__c> paymentsToUpdate = new List<Payment__c>();
    for (Id contractId : linesByContract.keySet()) {
      Decimal firstPaymentTotal = 0;
      Id opportunityId;
      Boolean hasInitialPaymentLine = false;

      for (ContractLineItem line : linesByContract.get(contractId)) {
        String paymentConfig = line.PricebookEntry.Payment_type__c;
        if (
          paymentConfig != DEPOSIT_CONFIG &&
          paymentConfig != FULL_PRICE_CONFIG
        ) {
          continue;
        }

        Decimal lineTotal = line.TotalPrice == null
          ? roundCurrency(line.UnitPrice * line.Quantity)
          : roundCurrency(line.TotalPrice);
        if (lineTotal == null || lineTotal < 0)
          continue;

        opportunityId = line.ServiceContract.Opportunity__c;
        hasInitialPaymentLine = true;
        if (paymentConfig == FULL_PRICE_CONFIG) {
          firstPaymentTotal += lineTotal;
          continue;
        }

        Decimal depositTotal = calculateDepositTotal(line, lineTotal);
        firstPaymentTotal += depositTotal;
        Decimal balance = roundCurrency(lineTotal - depositTotal);
        if (balance > 0) {
          addBalancePayment(
            paymentsToInsert,
            existingByReference,
            line,
            balance
          );
        }
      }

      if (hasInitialPaymentLine) {
        addOrUpdateFirstPayment(
          paymentsToInsert,
          paymentsToUpdate,
          existingByReference,
          contractId,
          opportunityId,
          roundCurrency(firstPaymentTotal)
        );
      }
    }

    if (!paymentsToInsert.isEmpty())
      insert paymentsToInsert;
    if (!paymentsToUpdate.isEmpty())
      update paymentsToUpdate;
  }

  private static Decimal calculateDepositTotal(
    ContractLineItem line,
    Decimal lineTotal
  ) {
    Decimal depositPerUnit = line.Deposit__c;
    if (depositPerUnit == null && line.PricebookEntry.Deposit__c != null) {
      Decimal discountFactor = line.Discount == null
        ? 1
        : (1 - (line.Discount / 100));
      depositPerUnit = line.PricebookEntry.Deposit__c * discountFactor;
    }
    Decimal configuredDeposit = depositPerUnit == null ||
      line.Quantity == null
      ? null
      : roundCurrency(depositPerUnit * line.Quantity);
    return configuredDeposit != null &&
      configuredDeposit > 0 &&
      configuredDeposit < lineTotal
      ? configuredDeposit
      : lineTotal;
  }

  private static void addBalancePayment(
    List<Payment__c> payments,
    Map<String, Payment__c> existingByReference,
    ContractLineItem line,
    Decimal amount
  ) {
    String orderReference = line.Id + ':balance';
    if (existingByReference.containsKey(orderReference))
      return;
    Payment__c balancePayment = new Payment__c(
      Service_Contract__c = line.ServiceContractId,
      Contract_Line_Item__c = line.Id,
      Opportunity__c = line.ServiceContract.Opportunity__c,
      Amount__c = amount,
      Status__c = DEFERRED_STATUS,
      Payment_Type__c = BALANCE_TYPE,
      Description__c = ('Remaining balance for ' +
        line.PricebookEntry.Name).left(255),
      Order_Ref__c = orderReference
    );
    payments.add(balancePayment);
    existingByReference.put(orderReference, balancePayment);
  }

  private static void addOrUpdateFirstPayment(
    List<Payment__c> paymentsToInsert,
    List<Payment__c> paymentsToUpdate,
    Map<String, Payment__c> existingByReference,
    Id contractId,
    Id opportunityId,
    Decimal amount
  ) {
    String orderReference = String.valueOf(contractId) + ':first';
    Payment__c existing = existingByReference.get(orderReference);
    if (existing == null) {
      Payment__c firstPayment = new Payment__c(
        Service_Contract__c = contractId,
        Opportunity__c = opportunityId,
        Amount__c = amount,
        Status__c = REQUEST_PAYMENT_STATUS,
        Payment_Type__c = FIRST_PAYMENT_TYPE,
        Description__c = 'First payment for selected services',
        Order_Ref__c = orderReference
      );
      paymentsToInsert.add(firstPayment);
      existingByReference.put(orderReference, firstPayment);
      return;
    }

    if (
      (existing.Status__c == REQUEST_PAYMENT_STATUS ||
      existing.Status__c == 'Pending') &&
      (existing.Amount__c != amount ||
      existing.Payment_Type__c != FIRST_PAYMENT_TYPE ||
      existing.Status__c != REQUEST_PAYMENT_STATUS)
    ) {
      existing.Amount__c = amount;
      existing.Payment_Type__c = FIRST_PAYMENT_TYPE;
      existing.Status__c = REQUEST_PAYMENT_STATUS;
      paymentsToUpdate.add(existing);
    }
  }

  private static Decimal roundCurrency(Decimal value) {
    return value == null ? null : value.setScale(2);
  }

  private static void excludeFormAppContracts(Set<Id> contractIds) {
    Map<Id, Id> creatorByContract = new Map<Id, Id>();
    Set<Id> creatorIds = new Set<Id>();
    for (ServiceContract contract : [
      SELECT Id, CreatedById
      FROM ServiceContract
      WHERE Id IN :contractIds
    ]) {
      creatorByContract.put(contract.Id, contract.CreatedById);
      creatorIds.add(contract.CreatedById);
    }
    Set<Id> formAppUserIds = new Set<Id>();
    for (PermissionSetAssignment assignment : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        AssigneeId IN :creatorIds
        AND PermissionSet.Name = 'DrApp_Integration_API_User'
    ]) {
      formAppUserIds.add(assignment.AssigneeId);
    }
    for (Id contractId : creatorByContract.keySet()) {
      if (formAppUserIds.contains(creatorByContract.get(contractId))) {
        contractIds.remove(contractId);
      }
    }
  }

  private static Boolean isFormAppUser() {
    return ![
        SELECT Id
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND PermissionSet.Name = 'DrApp_Integration_API_User'
        LIMIT 1
      ]
      .isEmpty();
  }
}
