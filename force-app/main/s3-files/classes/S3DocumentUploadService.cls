public with sharing class S3DocumentUploadService {

    public class UploadContextWrapper {
        @AuraEnabled public String bucket { get; set; }
        @AuraEnabled public String region { get; set; }
        @AuraEnabled public String pathDescription { get; set; }
        @AuraEnabled public String relatedObjectType { get; set; }
        @AuraEnabled public String relatedRecordId { get; set; }
        @AuraEnabled public List<String> acceptedFormats { get; set; }
        @AuraEnabled public Boolean uploadAllowed { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    public class UploadTargetWrapper {
        @AuraEnabled public String uploadUrl { get; set; }
        @AuraEnabled public String s3Key { get; set; }
        @AuraEnabled public String bucket { get; set; }
        @AuraEnabled public String region { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String contentType { get; set; }
        @AuraEnabled public String expiresAt { get; set; }
    }

    public class FinalizeResultWrapper {
        @AuraEnabled public Id documentId { get; set; }
        @AuraEnabled public String fileName { get; set; }
    }

    public static UploadContextWrapper getUploadContext(Id recordId) {
        UploadContextWrapper wrapper = new UploadContextWrapper();
        wrapper.uploadAllowed = true;
        wrapper.acceptedFormats = new List<String>();

        try {
            S3DocumentPathService.UploadPath path = S3DocumentPathService.resolveUploadPath(recordId);
            wrapper.bucket = path.bucket;
            wrapper.region = path.region;
            wrapper.pathDescription = path.pathDescription;
            wrapper.relatedObjectType = path.relatedObjectType;
            wrapper.relatedRecordId = path.relatedRecordId;
            wrapper.acceptedFormats = loadAcceptedFormats(recordId);
            wrapper.message = 'Files upload to s3://' + path.bucket + '/' + path.s3KeyPrefix;
        } catch (Exception ex) {
            wrapper.uploadAllowed = false;
            wrapper.message = ex.getMessage();
        }

        return wrapper;
    }

    public static UploadTargetWrapper prepareUpload(
        Id recordId,
        String fileName,
        String contentType,
        Long fileSize
    ) {
        validateUploadInput(fileName, fileSize);

        S3DocumentPathService.UploadPath path = S3DocumentPathService.resolveUploadPath(recordId);
        validateAcceptedFormat(recordId, fileName);

        String normalizedContentType = String.isNotBlank(contentType)
            ? contentType
            : 'application/octet-stream';
        String s3Key = S3DocumentPathService.buildObjectKey(path, fileName);

        Appeals_Dr_Setting__c settings = S3AwsPresignService.resolveSettings();
        S3DocumentUrlService.PresignResponse presignResponse = resolveUploadPresignedUrl(
            settings,
            path.bucket,
            s3Key,
            path.region,
            normalizedContentType
        );

        if (presignResponse == null || String.isBlank(presignResponse.url)) {
            throw new AuraHandledException(buildUploadUrlErrorMessage(settings));
        }

        UploadTargetWrapper wrapper = new UploadTargetWrapper();
        wrapper.uploadUrl = presignResponse.url;
        wrapper.s3Key = s3Key;
        wrapper.bucket = path.bucket;
        wrapper.region = path.region;
        wrapper.fileName = fileName;
        wrapper.contentType = normalizedContentType;
        wrapper.expiresAt = presignResponse.expiresAt;
        return wrapper;
    }

    public static FinalizeResultWrapper finalizeUpload(
        Id recordId,
        String fileName,
        String contentType,
        Long fileSize,
        String s3Key,
        String description
    ) {
        validateUploadInput(fileName, fileSize);

        if (String.isBlank(s3Key)) {
            throw new AuraHandledException('S3 key is required.');
        }

        S3DocumentPathService.UploadPath path = S3DocumentPathService.resolveUploadPath(recordId);
        String normalizedContentType = String.isNotBlank(contentType)
            ? contentType
            : 'application/octet-stream';
        String extension = extractExtension(fileName);

        S3_Document__c document = new S3_Document__c(
            Related_Record_Id__c = path.relatedRecordId,
            Related_Object_Type__c = path.relatedObjectType,
            Required_File__c = path.requiredFileId,
            S3_Bucket__c = path.bucket,
            S3_Key__c = s3Key,
            S3_Region__c = path.region,
            File_Name__c = fileName,
            File_Extension__c = extension,
            Content_Type__c = normalizedContentType,
            File_Size_Bytes__c = fileSize,
            Description__c = description,
            Status__c = 'Active',
            Preview_Status__c = 'Pending',
            Uploaded_By__c = UserInfo.getUserId(),
            Uploaded_Date__c = System.now()
        );
        insert document;

        updateRelatedUploadRecord(recordId, document.Id);

        FinalizeResultWrapper wrapper = new FinalizeResultWrapper();
        wrapper.documentId = document.Id;
        wrapper.fileName = fileName;
        return wrapper;
    }

    private static void validateUploadInput(String fileName, Long fileSize) {
        if (String.isBlank(fileName)) {
            throw new AuraHandledException('File name is required.');
        }
        if (fileSize == null || fileSize <= 0) {
            throw new AuraHandledException('File size is required.');
        }
        if (fileSize > 52428800) {
            throw new AuraHandledException('Files larger than 50 MB are not supported.');
        }
    }

    private static List<String> loadAcceptedFormats(Id recordId) {
        if (recordId.getSObjectType() != Required_File__c.SObjectType) {
            return new List<String>();
        }

        Required_File__c requiredFile = [
            SELECT Accepted_Format__c
            FROM Required_File__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (String.isBlank(requiredFile.Accepted_Format__c)) {
            return new List<String>();
        }

        return requiredFile.Accepted_Format__c.split(';');
    }

    private static void validateAcceptedFormat(Id recordId, String fileName) {
        List<String> acceptedFormats = loadAcceptedFormats(recordId);
        if (acceptedFormats.isEmpty()) {
            return;
        }

        String extension = extractExtension(fileName);
        if (String.isBlank(extension) || !acceptedFormats.contains(extension.toLowerCase())) {
            throw new AuraHandledException(
                'This file type is not allowed. Accepted formats: ' + String.join(acceptedFormats, ', ')
            );
        }
    }

    private static void updateRelatedUploadRecord(Id recordId, Id documentId) {
        if (recordId.getSObjectType() == Required_File__c.SObjectType) {
            update new Required_File__c(
                Id = recordId,
                Last_Version__c = documentId,
                File_Uploaded__c = true
            );
            return;
        }

        if (recordId.getSObjectType() == Document_Template__c.SObjectType) {
            update new Document_Template__c(
                Id = recordId,
                Last_Version__c = documentId
            );
        }
    }

    @TestVisible
    private static S3DocumentUrlService.PresignResponse resolveUploadPresignedUrl(
        Appeals_Dr_Setting__c settings,
        String bucket,
        String key,
        String region,
        String contentType
    ) {
        return S3DocumentUrlService.createAwsPresignedUrl(
            settings,
            bucket,
            key,
            region,
            null,
            contentType,
            S3DocumentUrlService.ACCESS_UPLOAD
        );
    }

    public static void uploadToPresignedUrl(String uploadUrl, String contentType, Blob fileBody) {
        if (String.isBlank(uploadUrl)) {
            throw new AuraHandledException('Upload URL is required.');
        }
        if (fileBody == null || fileBody.size() == 0) {
            throw new AuraHandledException('File content is required.');
        }

        String normalizedContentType = String.isNotBlank(contentType)
            ? contentType
            : 'application/octet-stream';

        HttpRequest request = new HttpRequest();
        request.setEndpoint(uploadUrl);
        request.setMethod('PUT');
        request.setHeader('Content-Type', normalizedContentType);
        request.setBodyAsBlob(fileBody);
        request.setTimeout(120000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'S3 upload failed with status ' + response.getStatusCode() + ': ' + response.getStatus()
            );
        }
    }

    @TestVisible
    private static String buildUploadUrlErrorMessage(Appeals_Dr_Setting__c settings) {
        if (settings == null || !S3AwsPresignService.hasAwsCredentials(settings)) {
            return 'Upload is not configured. Set AWS Access Key Id and AWS Secret Access Key in Appeals Dr Setting.';
        }

        return 'Unable to prepare the S3 upload URL. Verify AWS credentials, bucket name, and region in Appeals Dr Setting.';
    }

    private static String extractExtension(String fileName) {
        if (String.isBlank(fileName) || !fileName.contains('.')) {
            return null;
        }
        return fileName.substringAfterLast('.').toLowerCase();
    }
}
