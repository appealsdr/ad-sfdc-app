/******************************************************************************
@description: Invocable action used by Opportunity Lightning buttons.
              Sets the stage and fires a single webhook via
              OpportunityDataSendersApi — while preventing the trigger
              from firing a duplicate.
*******************************************************************************/
public class OpportunityButtonAction {

    public class Request {
        @InvocableVariable(required=true label='Opportunity ID')
        public Id opportunityId;

        @InvocableVariable(required=true label='Target Stage')
        public String targetStage;

        @InvocableVariable(required=true label='Webhook Action (Create/Update)')
        public String webhookAction;
    }

    @InvocableMethod(label='Opportunity Button Action' description='Set stage and send webhook (single fire)')
    public static void execute(List<Request> requests) {
        if (requests == null || requests.isEmpty()) return;

        Set<Id> oppIds = new Set<Id>();
        Map<Id, Request> reqMap = new Map<Id, Request>();

        for (Request r : requests) {
            oppIds.add(r.opportunityId);
            reqMap.put(r.opportunityId, r);
        }

        List<Opportunity> opps = [SELECT Id, StageName FROM Opportunity WHERE Id IN :oppIds];
        List<Opportunity> toUpdate = new List<Opportunity>();

        for (Opportunity opp : opps) {
            Request r = reqMap.get(opp.Id);
            if (opp.StageName != r.targetStage) {
                opp.StageName = r.targetStage;
                toUpdate.add(opp);
            }
        }

        // Suppress the trigger's webhook callout so we don't get duplicates
        OpportunityTriggerHandler.skipWebhookFiring = true;
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        OpportunityTriggerHandler.skipWebhookFiring = false;

        // Single authoritative webhook call
        OpportunityDataSendersApi.sendOpportunityDatabyTrigger(oppIds, requests[0].webhookAction);
    }
}