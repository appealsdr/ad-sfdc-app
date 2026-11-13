/******************************************************************************
@author:      Pradeep Kumar
@date:        02 Sep 2025
@description: Trigger Handler for Opportunity
*******************************************************************************/
public class OpportunityTriggerHandler extends TriggerFrameworkService {
  private List<Opportunity> lstNewOpportunities;
  private Map<Id, Opportunity> mapOldOpportunities;
  public static String TRIGGER_HANDLER_NAME = 'OpportunityTriggerHandler';
  public static Boolean skipWebhookFiring = false;
  private static final String CLOSED_WON_STAGE = 'Closed Won';

  public OpportunityTriggerHandler() {
    this.lstNewOpportunities = (Trigger.new != null)
      ? (List<Opportunity>) Trigger.new
      : new List<Opportunity>();
    this.mapOldOpportunities = (Trigger.oldMap != null)
      ? (Map<Id, Opportunity>) Trigger.oldMap
      : new Map<Id, Opportunity>();
  }

  /* After Insert */
  public override void beforeInsert() {
    validateContractReadiness();
    try {
      //processAfterInsert(lstNewOpportunities);
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    } finally {
      Logger.flushLogs();
    }
  }

  /* After Insert */
  public override void afterInsert() {
    try {
      processAfterInsert(lstNewOpportunities);
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    } finally {
      Logger.flushLogs();
    }
  } /* After Insert */
  public override void beforeUpdate() {
    validateContractReadiness();
    try {
      // processAfterInsert(lstNewOpportunities);
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    } finally {
      Logger.flushLogs();
    }
  }
  /* After Insert */
  public override void afterUpdate() {
    try {
      processAfterUpdate(lstNewOpportunities, mapOldOpportunities);
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    } finally {
      Logger.flushLogs();
    }
  }
  /* After Insert */
  public override void beforeDelete() {
    try {
      // processAfterInsert(lstNewOpportunities);
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    } finally {
      Logger.flushLogs();
    }
  }

  /* After Update */
  public override void afterDelete() {
    try {
      // processAfterUpdate(lstNewOpportunities, mapOldOpportunities);
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    } finally {
      Logger.flushLogs();
    }
  }

  /* After Update */
  public override void afterUnDelete() {
    try {
      //processAfterUpdate(lstNewOpportunities, mapOldOpportunities);
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    } finally {
      Logger.flushLogs();
    }
  }

  /** Enforce readiness before a stage change can create contracts or send a webhook. */
  private void validateContractReadiness() {
    List<Opportunity> enteringContractSent = new List<Opportunity>();
    Set<Id> opportunityIds = new Set<Id>();
    for (Opportunity opp : lstNewOpportunities) {
      Opportunity oldOpp = mapOldOpportunities.get(opp.Id);
      if (
        opp.StageName == 'Contract Sent' &&
        (oldOpp == null ||
        oldOpp.StageName != 'Contract Sent')
      ) {
        enteringContractSent.add(opp);
        if (opp.Id != null)
          opportunityIds.add(opp.Id);
      }
    }
    if (enteringContractSent.isEmpty())
      return;

    Set<Id> opportunitiesWithProducts = new Set<Id>();
    if (!opportunityIds.isEmpty()) {
      for (AggregateResult result : [
        SELECT OpportunityId opportunityId
        FROM OpportunityLineItem
        WHERE OpportunityId IN :opportunityIds
        GROUP BY OpportunityId
      ]) {
        opportunitiesWithProducts.add((Id) result.get('opportunityId'));
      }
    }
    for (Opportunity opp : enteringContractSent) {
      String errorMessage = contractReadinessError(
        opp.Pricebook2Id,
        opportunitiesWithProducts.contains(opp.Id),
        opp.Opportunity_Opener__c,
        opp.Opportunity_Closer__c
      );
      if (errorMessage != null)
        opp.StageName.addError(errorMessage);
    }
  }

  public static String contractReadinessError(
    Id pricebookId,
    Boolean hasProducts,
    Id opportunityOpenerId,
    Id opportunityCloserId
  ) {
    if (pricebookId == null) {
      return 'Select a price book and add at least one Opportunity product before sending the contract. If you created a quote, sync it to the Opportunity first.';
    }
    if (hasProducts != true) {
      return 'Add at least one Opportunity product before sending the contract. If you created a quote, sync it to the Opportunity first.';
    }
    if (opportunityOpenerId == null || opportunityCloserId == null) {
      return 'Set both Opportunity Opener and Opportunity Closer before sending the contract.';
    }
    return null;
  }

  private void processAfterInsert(List<Opportunity> opportunities) {
    try {
      if (!opportunities.isEmpty()) {
        shareWithCaseTeamMembers(opportunities);
      }
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    }
  }

  private void processAfterUpdate(
    List<Opportunity> opportunities,
    Map<Id, Opportunity> oldMap
  ) {
    try {
      List<Opportunity> accountChangedOpps = new List<Opportunity>();
      Set<Id> contractSentOppIds = new Set<Id>();
      Set<Id> closedWonOppIds = new Set<Id>();
      for (Opportunity opp : opportunities) {
        Opportunity oldOpp = oldMap.get(opp.Id);
        if (oldOpp != null && opp.AccountId != oldOpp.AccountId) {
          accountChangedOpps.add(opp);
        }
        if (
          opp.StageName == 'Contract Sent' &&
          oldOpp.StageName != 'Contract Sent'
        ) {
          contractSentOppIds.add(opp.Id);
        }
        if (
          opp.StageName == CLOSED_WON_STAGE &&
          oldOpp.StageName != CLOSED_WON_STAGE
        ) {
          closedWonOppIds.add(opp.Id);
        }
      }

      if (!accountChangedOpps.isEmpty()) {
        removeOldShares(accountChangedOpps, oldMap);
        shareWithCaseTeamMembers(accountChangedOpps);
      }
      // Data migrations set skipWebhookFiring to suppress every stage side effect,
      // including ServiceContract creation as well as outbound webhooks.
      if (!skipWebhookFiring) {
        if (!closedWonOppIds.isEmpty()) {
          // Generate the customer link before any Service Contract is inserted.
          SignupLinkService.generateAndStoreForOpportunityIds(closedWonOppIds);
        }
        Set<Id> contractCreationOppIds = OpportunityServiceContractService.getContractCreationTransitionIds(
          opportunities,
          oldMap
        );
        if (!contractCreationOppIds.isEmpty()) {
          OpportunityServiceContractService.createServiceContractsFromOpportunities(
            contractCreationOppIds
          );
        }
        if (!contractSentOppIds.isEmpty()) {
          callOpportunityApi(contractSentOppIds);
        }
      }
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    }
  }

  public static void callOpportunityApi(Set<Id> oppoIdSet) {
    OpportunityDataSendersApi.sendOpportunityDatabyTrigger(oppoIdSet, 'Update');
  }

  private void shareWithCaseTeamMembers(List<Opportunity> opportunities) {
    try {
      if (opportunities.isEmpty())
        return;

      Set<Id> accountIds = new Set<Id>();
      for (Opportunity opp : opportunities) {
        if (opp.AccountId != null)
          accountIds.add(opp.AccountId);
      }
      if (accountIds.isEmpty())
        return;

      Map<Id, Set<Id>> accountToUserIds = new Map<Id, Set<Id>>();
      for (Case_Team_Member__c ctm : [
        SELECT User__c, Case__r.AccountId
        FROM Case_Team_Member__c
        WHERE Case__r.AccountId IN :accountIds
      ]) {
        if (ctm.User__c != null && ctm.Case__r.AccountId != null) {
          if (!accountToUserIds.containsKey(ctm.Case__r.AccountId)) {
            accountToUserIds.put(ctm.Case__r.AccountId, new Set<Id>());
          }
          accountToUserIds.get(ctm.Case__r.AccountId).add(ctm.User__c);
        }
      }

      List<OpportunityShare> oppShares = new List<OpportunityShare>();
      for (Opportunity opp : opportunities) {
        if (
          opp.AccountId != null && accountToUserIds.containsKey(opp.AccountId)
        ) {
          for (Id userId : accountToUserIds.get(opp.AccountId)) {
            oppShares.add(
              new OpportunityShare(
                OpportunityId = opp.Id,
                UserOrGroupId = userId,
                OpportunityAccessLevel = 'Edit',
                RowCause = Schema.OpportunityShare.RowCause.Manual
              )
            );
          }
        }
      }

      if (!oppShares.isEmpty())
        insert oppShares;
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    }
  }

  private void removeOldShares(
    List<Opportunity> opportunities,
    Map<Id, Opportunity> oldMap
  ) {
    try {
      if (opportunities.isEmpty())
        return;

      List<OpportunityShare> sharesToDelete = new List<OpportunityShare>();

      for (Opportunity opp : opportunities) {
        Opportunity oldOpp = oldMap.get(opp.Id);
        if (oldOpp != null && oldOpp.AccountId != null) {
          Set<Id> userIds = new Set<Id>();
          for (Case_Team_Member__c ctm : [
            SELECT User__c
            FROM Case_Team_Member__c
            WHERE Case__r.AccountId = :oldOpp.AccountId
          ]) {
            if (ctm.User__c != null)
              userIds.add(ctm.User__c);
          }

          if (!userIds.isEmpty()) {
            sharesToDelete.addAll(
              [
                SELECT Id
                FROM OpportunityShare
                WHERE OpportunityId = :opp.Id AND UserOrGroupId IN :userIds
              ]
            );
          }
        }
      }

      if (!sharesToDelete.isEmpty())
        delete sharesToDelete;
    } catch (Exception ex) {
      Logger.logException(ex, TRIGGER_HANDLER_NAME);
    }
  }
}
