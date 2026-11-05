public with sharing class S3DocumentController {

    public class DocumentWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String contentType { get; set; }
        @AuraEnabled public String fileExtension { get; set; }
        @AuraEnabled public Decimal fileSizeBytes { get; set; }
        @AuraEnabled public String formattedFileSize { get; set; }
        @AuraEnabled public Boolean isPreviewable { get; set; }
        @AuraEnabled public String previewType { get; set; }
        @AuraEnabled public String previewStatus { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String uploadedByName { get; set; }
        @AuraEnabled public Datetime uploadedDate { get; set; }
        @AuraEnabled public String formattedUploadedDate { get; set; }
        @AuraEnabled public String thumbnailUrl { get; set; }
    }

    public class DocumentAccessWrapper {
        @AuraEnabled public String url { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String contentType { get; set; }
        @AuraEnabled public Boolean isPreviewable { get; set; }
        @AuraEnabled public String previewType { get; set; }
        @AuraEnabled public String accessType { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<DocumentWrapper> getDocuments(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        try {
            List<S3_Document__c> documents = queryDocuments(recordId);

            List<DocumentWrapper> wrappers = new List<DocumentWrapper>();
            for (S3_Document__c document : documents) {
                wrappers.add(toWrapper(document));
            }
            return wrappers;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load documents: ' + ex.getMessage());
        }
    }

    @TestVisible
    private static List<S3_Document__c> queryDocuments(Id recordId) {
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        String recordIdText = String.valueOf(recordId);

        if (objectApiName == 'S3_Document__c') {
            return [
                SELECT Id, File_Name__c, Content_Type__c, File_Extension__c, File_Size_Bytes__c,
                       Is_Previewable__c, Preview_Type__c, Preview_Status__c, Description__c,
                       Uploaded_Date__c, Thumbnail_URL__c, Uploaded_By__r.Name
                FROM S3_Document__c
                WHERE Id = :recordId
                  AND Status__c = 'Active'
                ORDER BY Uploaded_Date__c DESC NULLS LAST, CreatedDate DESC
            ];
        }

        if (objectApiName == 'Required_File__c') {
            Required_File__c requiredFile = [
                SELECT Last_Version__c
                FROM Required_File__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            Id lastVersionId = requiredFile.Last_Version__c;
            return [
                SELECT Id, File_Name__c, Content_Type__c, File_Extension__c, File_Size_Bytes__c,
                       Is_Previewable__c, Preview_Type__c, Preview_Status__c, Description__c,
                       Uploaded_Date__c, Thumbnail_URL__c, Uploaded_By__r.Name
                FROM S3_Document__c
                WHERE Status__c = 'Active'
                  AND (
                      Required_File__c = :recordId
                      OR Related_Record_Id__c = :recordIdText
                      OR Id = :lastVersionId
                  )
                ORDER BY Uploaded_Date__c DESC NULLS LAST, CreatedDate DESC
            ];
        }

        return [
            SELECT Id, File_Name__c, Content_Type__c, File_Extension__c, File_Size_Bytes__c,
                   Is_Previewable__c, Preview_Type__c, Preview_Status__c, Description__c,
                   Uploaded_Date__c, Thumbnail_URL__c, Uploaded_By__r.Name
            FROM S3_Document__c
            WHERE Related_Record_Id__c = :recordIdText
              AND Status__c = 'Active'
            ORDER BY Uploaded_Date__c DESC NULLS LAST, CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static DocumentAccessWrapper getDocumentAccess(Id documentId, String accessType) {
        if (documentId == null) {
            throw new AuraHandledException('Document Id is required.');
        }

        try {
            S3_Document__c document = S3DocumentUrlService.queryDocument(documentId);
            if (document.Status__c != 'Active') {
                throw new AuraHandledException('This document is not available.');
            }

            S3DocumentUrlService.DocumentAccess access =
                S3DocumentUrlService.resolveAccess(document, accessType);

            DocumentAccessWrapper wrapper = new DocumentAccessWrapper();
            wrapper.url = access.url;
            wrapper.fileName = document.File_Name__c;
            wrapper.contentType = document.Content_Type__c;
            wrapper.isPreviewable = document.Is_Previewable__c;
            wrapper.previewType = document.Preview_Type__c;
            wrapper.accessType = S3DocumentUrlService.ACCESS_DOWNLOAD.equalsIgnoreCase(accessType)
                ? S3DocumentUrlService.ACCESS_DOWNLOAD
                : S3DocumentUrlService.ACCESS_PREVIEW;
            return wrapper;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to access document: ' + ex.getMessage());
        }
    }

    private static DocumentWrapper toWrapper(S3_Document__c document) {
        DocumentWrapper wrapper = new DocumentWrapper();
        wrapper.id = document.Id;
        wrapper.fileName = document.File_Name__c;
        wrapper.contentType = document.Content_Type__c;
        wrapper.fileExtension = document.File_Extension__c;
        wrapper.fileSizeBytes = document.File_Size_Bytes__c;
        wrapper.formattedFileSize = formatFileSize(document.File_Size_Bytes__c);
        wrapper.isPreviewable = document.Is_Previewable__c;
        wrapper.previewType = document.Preview_Type__c;
        wrapper.previewStatus = document.Preview_Status__c;
        wrapper.description = document.Description__c;
        wrapper.uploadedByName = document.Uploaded_By__r != null ? document.Uploaded_By__r.Name : '';
        wrapper.uploadedDate = document.Uploaded_Date__c;
        wrapper.formattedUploadedDate = document.Uploaded_Date__c != null
            ? document.Uploaded_Date__c.format('MMM d, yyyy h:mm a')
            : '';
        wrapper.thumbnailUrl = document.Thumbnail_URL__c;
        return wrapper;
    }

    private static String formatFileSize(Decimal sizeBytes) {
        if (sizeBytes == null || sizeBytes <= 0) {
            return '0 B';
        }

        List<String> units = new List<String>{ 'B', 'KB', 'MB', 'GB' };
        Decimal size = sizeBytes;
        Integer unitIndex = 0;

        while (size >= 1024 && unitIndex < units.size() - 1) {
            size = size / 1024;
            unitIndex++;
        }

        return String.valueOf(size.setScale(unitIndex == 0 ? 0 : 1)) + ' ' + units[unitIndex];
    }
}
