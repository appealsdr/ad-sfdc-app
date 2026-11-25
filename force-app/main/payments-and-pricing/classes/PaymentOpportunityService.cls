/**
 * Payment automation that runs from the Payment__c trigger. It runs without
 * sharing because payments are also saved by users who cannot see the related
 * Opportunity (for example the API integration user). With sharing, linking the
 * new Cases to that Opportunity fails and rolls the payment back.
 */
public without sharing class PaymentOpportunityService {
  private static final String PAID_STATUS = 'Paid';
  private static final String CLOSED_WON_STAGE = 'Closed Won';
  private static final String WHITE_GLOVE_PRICEBOOK_NAME = 'White Glove';
  private static final String NEW_CASE_STATUS = 'New';
  @TestVisible
  private static Boolean forceFailure = false;

  private class ForcedTestException extends Exception {
  }

  public static void populateOpportunity(List<Payment__c> payments) {
    if (forceFailure)
      throw new ForcedTestException('Forced test failure');
    Set<Id> contractIds = new Set<Id>();
    for (Payment__c payment : payments) {
      if (
        payment.Opportunity__c == null &&
        payment.Service_Contract__c != null
      ) {
        contractIds.add(payment.Service_Contract__c);
      }
    }
    if (contractIds.isEmpty())
      return;

    Map<Id, ServiceContract> contracts = new Map<Id, ServiceContract>(
      [
        SELECT Opportunity__c
        FROM ServiceContract
        WHERE Id IN :contractIds
      ]
    );
    for (Payment__c payment : payments) {
      ServiceContract contract = contracts.get(payment.Service_Contract__c);
      if (payment.Opportunity__c == null && contract != null) {
        payment.Opportunity__c = contract.Opportunity__c;
      }
    }
  }

  public static void closePaidOpportunities(
    List<Payment__c> payments,
    Map<Id, Payment__c> oldMap
  ) {
    Set<Id> opportunityIds = new Set<Id>();
    for (Payment__c payment : payments) {
      Payment__c oldPayment = oldMap == null ? null : oldMap.get(payment.Id);
      Boolean justPaid =
        payment.Status__c == PAID_STATUS &&
        (oldPayment == null ||
        oldPayment.Status__c != PAID_STATUS ||
        oldPayment.Opportunity__c != payment.Opportunity__c);
      if (justPaid && payment.Opportunity__c != null) {
        opportunityIds.add(payment.Opportunity__c);
      }
    }
    if (opportunityIds.isEmpty())
      return;

    List<Opportunity> opportunitiesToClose = new List<Opportunity>();
    for (Opportunity opportunity : [
      SELECT StageName
      FROM Opportunity
      WHERE Id IN :opportunityIds
    ]) {
      if (opportunity.StageName != CLOSED_WON_STAGE) {
        opportunity.StageName = CLOSED_WON_STAGE;
        opportunitiesToClose.add(opportunity);
      }
    }
    if (!opportunitiesToClose.isEmpty())
      update opportunitiesToClose;
  }

  public static void updateContractPaidAmounts(
    List<Payment__c> payments,
    Map<Id, Payment__c> oldMap
  ) {
    Set<Id> contractIds = paidAmountContractIds(payments, oldMap);
    if (contractIds.isEmpty())
      return;

    Map<Id, Decimal> paidAmountByContract = new Map<Id, Decimal>();
    for (AggregateResult result : [
      SELECT Service_Contract__c contractId, SUM(Amount__c) paidAmount
      FROM Payment__c
      WHERE Service_Contract__c IN :contractIds AND Status__c = :PAID_STATUS
      GROUP BY Service_Contract__c
    ]) {
      paidAmountByContract.put(
        (Id) result.get('contractId'),
        (Decimal) result.get('paidAmount')
      );
    }

    List<ServiceContract> contractsToUpdate = new List<ServiceContract>();
    for (Id contractId : contractIds) {
      contractsToUpdate.add(
        new ServiceContract(
          Id = contractId,
          Paid_Amount__c = paidAmountByContract.containsKey(contractId)
            ? paidAmountByContract.get(contractId)
            : 0
        )
      );
    }
    update contractsToUpdate;
  }

  public static void createCasesForFirstPayments(
    List<Payment__c> payments,
    Map<Id, Payment__c> oldMap
  ) {
    Set<Id> paidPaymentIds = new Set<Id>();
    Set<Id> candidateContractIds = new Set<Id>();
    for (Payment__c payment : payments) {
      Payment__c oldPayment = oldMap == null ? null : oldMap.get(payment.Id);
      Boolean firstPaidTransition =
        payment.Status__c == PAID_STATUS &&
        payment.Service_Contract__c != null &&
        (oldPayment == null ||
        oldPayment.Status__c != PAID_STATUS ||
        oldPayment.Service_Contract__c != payment.Service_Contract__c);
      if (firstPaidTransition) {
        paidPaymentIds.add(payment.Id);
        candidateContractIds.add(payment.Service_Contract__c);
      }
    }
    if (candidateContractIds.isEmpty())
      return;

    Map<Id, ServiceContract> eligibleContracts = new Map<Id, ServiceContract>();
    for (ServiceContract contract : [
      SELECT AccountId, Opportunity__c, Opportunity__r.Store__c, Pricebook2.Name
      FROM ServiceContract
      WHERE
        Id IN :candidateContractIds
        AND (Pricebook2Id = NULL
        OR Pricebook2.Name != :WHITE_GLOVE_PRICEBOOK_NAME)
    ]) {
      eligibleContracts.put(contract.Id, contract);
    }
    if (eligibleContracts.isEmpty())
      return;

    Set<Id> firstPaymentContractIds = new Set<Id>(eligibleContracts.keySet());
    for (Payment__c earlierPayment : [
      SELECT Service_Contract__c
      FROM Payment__c
      WHERE
        Service_Contract__c IN :firstPaymentContractIds
        AND Status__c = :PAID_STATUS
        AND Id NOT IN :paidPaymentIds
    ]) {
      firstPaymentContractIds.remove(earlierPayment.Service_Contract__c);
    }
    if (firstPaymentContractIds.isEmpty())
      return;

    List<ContractLineItem> contractLines = [
      SELECT
        Id,
        ServiceContractId,
        PricebookEntry.Product2.Name,
        PricebookEntry.Product2.Case_Type__c
      FROM ContractLineItem
      WHERE ServiceContractId IN :firstPaymentContractIds
    ];
    Set<Id> contractLineIds = new Set<Id>();
    for (ContractLineItem line : contractLines) {
      contractLineIds.add(line.Id);
    }

    Set<Id> lineIdsWithCases = new Set<Id>();
    if (!contractLineIds.isEmpty()) {
      for (Case existingCase : [
        SELECT Contract_Line_Item__c
        FROM Case
        WHERE Contract_Line_Item__c IN :contractLineIds
      ]) {
        lineIdsWithCases.add(existingCase.Contract_Line_Item__c);
      }
    }

    List<Case> casesToInsert = new List<Case>();
    for (ContractLineItem line : contractLines) {
      if (lineIdsWithCases.contains(line.Id))
        continue;
      ServiceContract contract = eligibleContracts.get(line.ServiceContractId);
      casesToInsert.add(
        new Case(
          Subject = line.PricebookEntry.Product2.Name,
          Status = NEW_CASE_STATUS,
          Case_Type__c = line.PricebookEntry.Product2.Case_Type__c,
          AccountId = contract.AccountId,
          Store__c = contract.Opportunity__r == null
            ? null
            : contract.Opportunity__r.Store__c,
          Opportunity__c = contract.Opportunity__c,
          ServiceContractId = contract.Id,
          Contract_Line_Item__c = line.Id
        )
      );
    }
    if (!casesToInsert.isEmpty())
      insert casesToInsert;
  }

  private static Set<Id> paidAmountContractIds(
    List<Payment__c> payments,
    Map<Id, Payment__c> oldMap
  ) {
    Set<Id> contractIds = new Set<Id>();
    for (Payment__c payment : payments) {
      Payment__c oldPayment = oldMap == null ? null : oldMap.get(payment.Id);
      if (
        payment.Status__c == PAID_STATUS &&
        payment.Service_Contract__c != null
      ) {
        contractIds.add(payment.Service_Contract__c);
      }
      if (
        oldPayment != null &&
        oldPayment.Status__c == PAID_STATUS &&
        oldPayment.Service_Contract__c != null
      ) {
        contractIds.add(oldPayment.Service_Contract__c);
      }
    }
    return contractIds;
  }
}
