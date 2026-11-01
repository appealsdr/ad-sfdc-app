@RestResource(urlMapping='/v1/campaign-click')
global with sharing class CampaignClickRestApi {
    global class ClickRequest {
        public String campaignId;
        public String visitorId;
        public String eventId;
    }

    global class ClickResponse {
        public Boolean success;
        public Boolean duplicateEvent;
        public Boolean uniqueVisitor;
        public String message;
    }

    @HttpPost
    global static ClickResponse trackClick() {
        ClickRequest requestData;
        try {
            requestData = (ClickRequest) JSON.deserialize(
                RestContext.request.requestBody.toString(), ClickRequest.class
            );
        } catch (Exception ex) {
            return errorResponse(400, 'Invalid JSON');
        }
        if (requestData == null || String.isBlank(requestData.campaignId) ||
            String.isBlank(requestData.visitorId) || String.isBlank(requestData.eventId) ||
            requestData.visitorId.length() > 100 || requestData.eventId.length() > 100) {
            return errorResponse(400, 'Invalid request');
        }

        Id campaignId;
        try {
            campaignId = Id.valueOf(requestData.campaignId);
            if (campaignId.getSObjectType() != Campaign.SObjectType) {
                return errorResponse(400, 'Invalid campaign ID');
            }
        } catch (Exception ex) {
            return errorResponse(400, 'Invalid campaign ID');
        }

        String eventKey = sha256(String.valueOf(campaignId) + ':' + requestData.eventId);
        String visitorKey = sha256(String.valueOf(campaignId) + ':' + requestData.visitorId);
        List<Campaign> campaigns;
        try {
            campaigns = [
                SELECT Id, Total_Clicks__c, Unique_Clicks__c
                FROM Campaign WHERE Id = :campaignId AND IsActive = true
                LIMIT 1 FOR UPDATE
            ];
        } catch (QueryException ex) {
            return errorResponse(503, 'Campaign is busy; retry with the same eventId');
        }
        if (campaigns.isEmpty()) {
            return errorResponse(404, 'Campaign not found');
        }

        List<Campaign_Click_Event__c> existingEvents = [
            SELECT Id FROM Campaign_Click_Event__c WHERE Event_Key__c = :eventKey LIMIT 1
        ];
        if (!existingEvents.isEmpty()) {
            return successResponse(true, false, 'Already counted');
        }
        List<Campaign_Click_Identity__c> existingIdentities = [
            SELECT Id FROM Campaign_Click_Identity__c WHERE Unique_Key__c = :visitorKey LIMIT 1
        ];
        Boolean isUnique = existingIdentities.isEmpty();

        Savepoint transactionStart = Database.setSavepoint();
        try {
            insert new Campaign_Click_Event__c(
                Campaign__c = campaignId, Event_Key__c = eventKey, Clicked_At__c = System.now()
            );
            if (isUnique) {
                insert new Campaign_Click_Identity__c(
                    Campaign__c = campaignId, Visitor_Key__c = visitorKey,
                    Unique_Key__c = visitorKey, First_Click__c = System.now()
                );
            }
            Campaign campaign = campaigns[0];
            campaign.Total_Clicks__c = (campaign.Total_Clicks__c == null ? 0 : campaign.Total_Clicks__c) + 1;
            if (isUnique) {
                campaign.Unique_Clicks__c = (campaign.Unique_Clicks__c == null ? 0 : campaign.Unique_Clicks__c) + 1;
            }
            update campaign;
        } catch (DmlException ex) {
            Database.rollback(transactionStart);
            if (ex.getDmlStatusCode(0) == String.valueOf(StatusCode.DUPLICATE_VALUE)) {
                return errorResponse(503, 'Concurrent click; retry with the same eventId');
            }
            if (ex.getDmlStatusCode(0) == String.valueOf(StatusCode.UNABLE_TO_LOCK_ROW)) {
                return errorResponse(503, 'Campaign is busy; retry with the same eventId');
            }
            throw ex;
        }
        return successResponse(false, isUnique, 'Click recorded');
    }

    private static String sha256(String value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(value)));
    }

    private static ClickResponse successResponse(Boolean duplicateEvent, Boolean uniqueVisitor, String message) {
        ClickResponse response = new ClickResponse();
        response.success = true;
        response.duplicateEvent = duplicateEvent;
        response.uniqueVisitor = uniqueVisitor;
        response.message = message;
        return response;
    }

    private static ClickResponse errorResponse(Integer statusCode, String message) {
        RestContext.response.statusCode = statusCode;
        ClickResponse response = new ClickResponse();
        response.success = false;
        response.duplicateEvent = false;
        response.uniqueVisitor = false;
        response.message = message;
        return response;
    }
}