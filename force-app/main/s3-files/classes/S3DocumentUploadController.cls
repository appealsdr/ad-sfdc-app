public with sharing class S3DocumentUploadController {

    @AuraEnabled(cacheable=true)
    public static S3DocumentUploadService.UploadContextWrapper getUploadContext(Id recordId) {
        // getUploadContext never throws - it reports failure via uploadAllowed/message
        // on the wrapper - so there's nothing here for a try/catch to add.
        return S3DocumentUploadService.getUploadContext(recordId);
    }

    @AuraEnabled
    public static S3DocumentUploadService.UploadTargetWrapper prepareUpload(
        Id recordId,
        String fileName,
        String contentType,
        Long fileSize
    ) {
        try {
            return S3DocumentUploadService.prepareUpload(recordId, fileName, contentType, fileSize);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to prepare upload: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void uploadFileContent(String uploadUrl, String contentType, String fileBodyBase64) {
        try {
            if (String.isBlank(fileBodyBase64)) {
                throw new AuraHandledException('File content is required.');
            }

            Blob fileBody = EncodingUtil.base64Decode(fileBodyBase64);
            S3DocumentUploadService.uploadToPresignedUrl(uploadUrl, contentType, fileBody);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to upload file to S3: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static S3DocumentUploadService.FinalizeResultWrapper finalizeUpload(
        Id recordId,
        String fileName,
        String contentType,
        Long fileSize,
        String s3Key,
        String description
    ) {
        try {
            return S3DocumentUploadService.finalizeUpload(
                recordId,
                fileName,
                contentType,
                fileSize,
                s3Key,
                description
            );
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to finalize upload: ' + ex.getMessage());
        }
    }
}