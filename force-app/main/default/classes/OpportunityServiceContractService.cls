/******************************************************************************
@author:      Claude
@date:        30 Jul 2026
@description: Creates a Service Contract (with line items copied from the
              Opportunity's Opportunity Line Items) when an Opportunity is
              moved to the Closed Won or Contract Sent stage. Invoked from
              OpportunityTriggerHandler.
*******************************************************************************/
public with sharing class OpportunityServiceContractService {

    private static final String LOG_SOURCE = 'OpportunityServiceContractService';
    @TestVisible
    private static final String CLOSED_WON_STAGE = 'Closed Won';
    @TestVisible
    private static final String CONTRACT_SEND_STAGE = 'Contract Sent';
    @TestVisible
    private static final String WON_STAGE = 'Won';
    @TestVisible
    private static final Set<String> CONTRACT_CREATION_STAGES = new Set<String>{ CLOSED_WON_STAGE, CONTRACT_SEND_STAGE, WON_STAGE };

    /**
     * Returns the Ids of the Opportunities that just transitioned into
     * Closed Won or Contract Sent (i.e. were not already in one of those
     * stages before this update).
     */
    public static Set<Id> getContractCreationTransitionIds(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        Set<Id> result = new Set<Id>();
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            Boolean wasAlreadyInStage = oldOpp != null && CONTRACT_CREATION_STAGES.contains(oldOpp.StageName);
            if (CONTRACT_CREATION_STAGES.contains(opp.StageName) && !wasAlreadyInStage) {
                result.add(opp.Id);
            }
        }
        return result;
    }

    /**
     * For each supplied Opportunity that has Opportunity Line Items, create a
     * Service Contract and copy the line items across as Service Contract Line Items.
     * Opportunities that already have a Service Contract created by this process,
     * or that have no line items, are skipped.
     */
    public static void createServiceContractsFromOpportunities(Set<Id> opportunityIds) {
        try {
            if (opportunityIds == null || opportunityIds.isEmpty()) {
                return;
            }

            // Load the opportunities together with their line items.
            Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
                SELECT Id, Name, AccountId, Pricebook2Id, CloseDate,
                       (SELECT Id, PricebookEntryId, Product2Id, Quantity, UnitPrice,
                               Discount, Description, ServiceDate
                        FROM OpportunityLineItems)
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]);

            // Skip opportunities that already produced a Service Contract via this process.
            Set<Id> alreadyProcessed = new Set<Id>();
            for (ServiceContract sc : [
                SELECT Opportunity__c
                FROM ServiceContract
                WHERE Opportunity__c IN :opportunityIds
            ]) {
                if (sc.Opportunity__c != null) {
                    alreadyProcessed.add(sc.Opportunity__c);
                }
            }

            // Build one Service Contract per eligible Opportunity.
            List<ServiceContract> contractsToInsert = new List<ServiceContract>();
            Map<Id, Opportunity> oppByOrder = new Map<Id, Opportunity>();
            for (Opportunity opp : oppMap.values()) {
                if (alreadyProcessed.contains(opp.Id)) {
                    continue;
                }
                if (opp.OpportunityLineItems == null || opp.OpportunityLineItems.isEmpty()) {
                    continue;
                }
                ServiceContract sc = new ServiceContract(
                    Name = opp.Name,
                    AccountId = opp.AccountId,
                    Pricebook2Id = opp.Pricebook2Id,
                    StartDate = opp.CloseDate,
                    Opportunity__c = opp.Id
                );
                contractsToInsert.add(sc);
                oppByOrder.put(opp.Id, opp);
            }

            if (contractsToInsert.isEmpty()) {
                return;
            }

            insert contractsToInsert;

            // Map each Opportunity to its freshly inserted Service Contract.
            Map<Id, Id> oppToContractId = new Map<Id, Id>();
            for (ServiceContract sc : contractsToInsert) {
                oppToContractId.put(sc.Opportunity__c, sc.Id);
            }

            // Copy each Opportunity Line Item to a Service Contract Line Item.
            List<ContractLineItem> lineItemsToInsert = new List<ContractLineItem>();
            for (Opportunity opp : oppByOrder.values()) {
                Id contractId = oppToContractId.get(opp.Id);
                if (contractId == null) {
                    continue;
                }
                for (OpportunityLineItem oli : opp.OpportunityLineItems) {
                    lineItemsToInsert.add(new ContractLineItem(
                        ServiceContractId = contractId,
                        PricebookEntryId = oli.PricebookEntryId,
                        Quantity = oli.Quantity,
                        UnitPrice = oli.UnitPrice,
                        Discount = oli.Discount,
                        Description = oli.Description,
                        StartDate = oli.ServiceDate
                    ));
                }
            }

            if (!lineItemsToInsert.isEmpty()) {
                insert lineItemsToInsert;
            }
        } catch (Exception ex) {
            Logger.logException(ex, LOG_SOURCE);
        }
    }
}