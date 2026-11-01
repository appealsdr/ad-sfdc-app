@IsTest
private class S3AwsPresignServiceTest {

    @IsTest
    static void testCreatePutObjectPresignedUrl() {
        Test.startTest();
        S3DocumentUrlService.PresignResponse response = S3AwsPresignService.createPutObjectPresignedUrl(
            'amzn-andrei-appeals-dr-test-bucket',
            'appealsDrApp/Templates/a1/Files/sample.pdf',
            'us-east-2',
            'application/pdf',
            'TESTACCESSKEY',
            'TESTSECRETKEY'
        );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assert(response.url.contains('amzn-andrei-appeals-dr-test-bucket.s3.us-east-2.amazonaws.com'));
        System.assert(response.url.contains('X-Amz-Signature='));
        System.assert(response.url.contains('X-Amz-Algorithm=AWS4-HMAC-SHA256'));
        System.assertNotEquals(null, response.expiresAt);
    }

    @IsTest
    static void testCreateGetObjectPresignedUrl() {
        Test.startTest();
        S3DocumentUrlService.PresignResponse previewResponse = S3AwsPresignService.createGetObjectPresignedUrl(
            'amzn-andrei-appeals-dr-test-bucket',
            'appealsDrApp/Templates/a1/Files/sample.pdf',
            'us-east-2',
            'TESTACCESSKEY',
            'TESTSECRETKEY',
            'sample.pdf',
            false
        );
        S3DocumentUrlService.PresignResponse downloadResponse = S3AwsPresignService.createGetObjectPresignedUrl(
            'amzn-andrei-appeals-dr-test-bucket',
            'appealsDrApp/Templates/a1/Files/sample.pdf',
            'us-east-2',
            'TESTACCESSKEY',
            'TESTSECRETKEY',
            'sample.pdf',
            true
        );
        Test.stopTest();

        System.assertNotEquals(null, previewResponse);
        System.assertNotEquals(null, downloadResponse);
        System.assert(downloadResponse.url.contains('response-content-disposition='));
    }

    @IsTest
    static void testHasAwsCredentialsAndRegion() {
        Appeals_Dr_Setting__c settings = new Appeals_Dr_Setting__c(
            AWS_Access_Key_Id__c = 'TESTACCESSKEY',
            AWS_Secret_Access_Key__c = 'TESTSECRETKEY'
        );

        System.assertEquals(true, S3AwsPresignService.hasAwsCredentials(settings));
        System.assertEquals('us-west-2', S3AwsPresignService.resolveRegion(
            new Appeals_Dr_Setting__c(AWS_Region__c = 'us-west-2'),
            null
        ));
    }

    @IsTest
    static void testResolveSettingsPrefersOrgDefaults() {
        Appeals_Dr_Setting__c settings = Appeals_Dr_Setting__c.getOrgDefaults();
        if (settings == null || settings.Id == null) {
            insert new Appeals_Dr_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                AWS_Access_Key_Id__c = 'ORGACCESSKEY',
                AWS_Secret_Access_Key__c = 'ORGSECRETKEY',
                AWS_Region__c = 'us-east-2'
            );
        } else {
            settings.AWS_Access_Key_Id__c = 'ORGACCESSKEY';
            settings.AWS_Secret_Access_Key__c = 'ORGSECRETKEY';
            settings.AWS_Region__c = 'us-east-2';
            update settings;
        }

        Appeals_Dr_Setting__c resolved = S3AwsPresignService.resolveSettings();
        System.assertEquals(true, S3AwsPresignService.hasAwsCredentials(resolved));
    }
}