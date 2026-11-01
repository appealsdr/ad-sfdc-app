@IsTest
private class CampaignClickRestApiTest {
    private static CampaignClickRestApi.ClickResponse send(String campaignId, String visitorId, String eventId) {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/campaign-click';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'campaignId' => campaignId, 'visitorId' => visitorId, 'eventId' => eventId
        }));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        return CampaignClickRestApi.trackClick();
    }

    @IsTest
    static void tracksUniqueRepeatAndRetry() {
        Campaign campaign = new Campaign(Name = 'Tracking test', IsActive = true);
        insert campaign;

        System.assertEquals(true, send(String.valueOf(campaign.Id), 'visitor-a', 'event-1').uniqueVisitor);
        System.assertEquals(false, send(String.valueOf(campaign.Id), 'visitor-a', 'event-2').uniqueVisitor);
        System.assertEquals(true, send(String.valueOf(campaign.Id), 'visitor-b', 'event-3').uniqueVisitor);
        CampaignClickRestApi.ClickResponse retry = send(String.valueOf(campaign.Id), 'visitor-a', 'event-1');
        System.assertEquals(true, retry.duplicateEvent);
        System.assertEquals(false, retry.uniqueVisitor);

        campaign = [SELECT Total_Clicks__c, Unique_Clicks__c FROM Campaign WHERE Id = :campaign.Id];
        System.assertEquals(3, campaign.Total_Clicks__c);
        System.assertEquals(2, campaign.Unique_Clicks__c);
        System.assertEquals(3, [SELECT COUNT() FROM Campaign_Click_Event__c]);
        System.assertEquals(2, [SELECT COUNT() FROM Campaign_Click_Identity__c]);
    }

    @IsTest
    static void rejectsInvalidAndInactiveCampaigns() {
        Campaign campaign = new Campaign(Name = 'Inactive tracking test', IsActive = false);
        insert campaign;
        CampaignClickRestApi.ClickResponse inactive = send(String.valueOf(campaign.Id), 'visitor', 'event');
        System.assertEquals(false, inactive.success);
        System.assertEquals(404, RestContext.response.statusCode);
        System.assertEquals(false, send(String.valueOf(UserInfo.getUserId()), 'visitor', 'event').success);
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, send(String.valueOf(campaign.Id), '', 'event').success);
        System.assertEquals(400, RestContext.response.statusCode);
    }
}