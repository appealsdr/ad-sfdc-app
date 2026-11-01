public with sharing class S3DocumentUrlService {

    public static final String ACCESS_PREVIEW = 'preview';
    public static final String ACCESS_DOWNLOAD = 'download';
    public static final String ACCESS_UPLOAD = 'upload';

    public class PresignResponse {
        public String url;
        public String expiresAt;
    }

    public class DocumentAccess {
        public String url { get; set; }
        public Datetime expiresAt { get; set; }
    }

    public static DocumentAccess resolveAccess(S3_Document__c document, String accessType) {
        if (document == null) {
            throw new AuraHandledException('Document not found.');
        }

        String normalizedAccess = normalizeAccessType(accessType);
        DocumentAccess cachedAccess = getCachedAccess(document, normalizedAccess);
        if (cachedAccess != null) {
            return cachedAccess;
        }

        DocumentAccess refreshedAccess = refreshAccess(document, normalizedAccess);
        if (refreshedAccess != null) {
            return refreshedAccess;
        }

        return getFallbackAccess(document, normalizedAccess);
    }

    public static S3_Document__c queryDocument(Id documentId) {
        return [
            SELECT Id, File_Name__c, Content_Type__c, Is_Previewable__c, Preview_Type__c,
                   Preview_Status__c, Preview_URL__c, Preview_Expires_At__c,
                   Download_URL__c, Download_Expires_At__c, File_URL__c,
                   S3_Bucket__c, S3_Key__c, S3_Region__c, Thumbnail_URL__c, Status__c
            FROM S3_Document__c
            WHERE Id = :documentId
            LIMIT 1
        ];
    }

    public static PresignResponse createAwsPresignedUrl(
        Appeals_Dr_Setting__c settings,
        String bucket,
        String key,
        String region,
        String fileName,
        String contentType,
        String accessType
    ) {
        if (!S3AwsPresignService.hasAwsCredentials(settings)) {
            return null;
        }

        String resolvedRegion = S3AwsPresignService.resolveRegion(settings, region);

        if (ACCESS_UPLOAD.equalsIgnoreCase(accessType)) {
            return S3AwsPresignService.createPutObjectPresignedUrl(
                bucket,
                key,
                resolvedRegion,
                contentType,
                settings.AWS_Access_Key_Id__c,
                settings.AWS_Secret_Access_Key__c
            );
        }

        return S3AwsPresignService.createGetObjectPresignedUrl(
            bucket,
            key,
            resolvedRegion,
            settings.AWS_Access_Key_Id__c,
            settings.AWS_Secret_Access_Key__c,
            fileName,
            ACCESS_DOWNLOAD.equalsIgnoreCase(accessType)
        );
    }

    private static String normalizeAccessType(String accessType) {
        return ACCESS_DOWNLOAD.equalsIgnoreCase(accessType) ? ACCESS_DOWNLOAD : ACCESS_PREVIEW;
    }

    private static DocumentAccess getCachedAccess(S3_Document__c document, String accessType) {
        String url;
        Datetime expiresAt;

        if (ACCESS_DOWNLOAD.equals(accessType)) {
            url = document.Download_URL__c;
            expiresAt = document.Download_Expires_At__c;
        } else {
            url = document.Preview_URL__c;
            expiresAt = document.Preview_Expires_At__c;
        }

        if (String.isBlank(url) || isExpired(expiresAt)) {
            return null;
        }

        DocumentAccess access = new DocumentAccess();
        access.url = url;
        access.expiresAt = expiresAt;
        return access;
    }

    private static DocumentAccess refreshAccess(S3_Document__c document, String accessType) {
        Appeals_Dr_Setting__c settings = S3AwsPresignService.resolveSettings();
        if (String.isBlank(document.S3_Bucket__c) || String.isBlank(document.S3_Key__c)) {
            return null;
        }

        PresignResponse presignResponse = createAwsPresignedUrl(
            settings,
            document.S3_Bucket__c,
            document.S3_Key__c,
            document.S3_Region__c,
            document.File_Name__c,
            document.Content_Type__c,
            accessType
        );

        if (presignResponse == null || String.isBlank(presignResponse.url)) {
            return null;
        }

        Datetime expiresAt = parseExpiresAt(presignResponse.expiresAt);
        updateDocumentUrls(document.Id, accessType, presignResponse.url, expiresAt);

        DocumentAccess access = new DocumentAccess();
        access.url = presignResponse.url;
        access.expiresAt = expiresAt;
        return access;
    }

    private static DocumentAccess getFallbackAccess(S3_Document__c document, String accessType) {
        String url = ACCESS_DOWNLOAD.equals(accessType)
            ? firstNonBlank(document.Download_URL__c, document.File_URL__c, document.Preview_URL__c)
            : firstNonBlank(document.Preview_URL__c, document.Thumbnail_URL__c, document.File_URL__c);

        if (String.isNotBlank(url)) {
            DocumentAccess access = new DocumentAccess();
            access.url = url;
            return access;
        }

        if (!S3AwsPresignService.hasAwsCredentials(S3AwsPresignService.resolveSettings())) {
            throw new AuraHandledException(
                'No file URL is available. Configure AWS Access Key and Secret in Appeals Dr Setting.'
            );
        }

        throw new AuraHandledException(
            'No file URL is available for this document. Verify S3 bucket, key, and AWS credentials.'
        );
    }

    private static void updateDocumentUrls(Id documentId, String accessType, String url, Datetime expiresAt) {
        S3_Document__c updateRecord = new S3_Document__c(Id = documentId);
        if (ACCESS_DOWNLOAD.equals(accessType)) {
            updateRecord.Download_URL__c = url;
            updateRecord.Download_Expires_At__c = expiresAt;
        } else {
            updateRecord.Preview_URL__c = url;
            updateRecord.Preview_Expires_At__c = expiresAt;
            updateRecord.Preview_Status__c = 'Ready';
        }
        update updateRecord;
    }

    private static Boolean isExpired(Datetime expiresAt) {
        return expiresAt == null || expiresAt <= System.now();
    }

    private static Datetime parseExpiresAt(String expiresAtValue) {
        if (String.isBlank(expiresAtValue)) {
            return System.now().addHours(1);
        }
        try {
            return (Datetime) JSON.deserialize('"' + expiresAtValue + '"', Datetime.class);
        } catch (Exception ex) {
            return System.now().addHours(1);
        }
    }

    private static String firstNonBlank(String firstValue, String secondValue, String thirdValue) {
        if (String.isNotBlank(firstValue)) {
            return firstValue;
        }
        if (String.isNotBlank(secondValue)) {
            return secondValue;
        }
        return thirdValue;
    }
}