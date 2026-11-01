public with sharing class RequiredFileController {

    public class RequiredFileWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String shortDescription { get; set; }
        @AuraEnabled public Boolean fileUploaded { get; set; }
        @AuraEnabled public String uploadedLabel { get; set; }
        @AuraEnabled public Id lastVersionId { get; set; }
        @AuraEnabled public String uploadedFileName { get; set; }
        @AuraEnabled public Boolean canPreview { get; set; }
    }

    public class TemplateWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String shortDescription { get; set; }
        @AuraEnabled public String acceptedFormat { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<RequiredFileWrapper> getRequiredFiles(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        List<Required_File__c> requiredFiles;

        if (objectApiName == 'Case') {
            requiredFiles = [
                SELECT Id, Name, Short_Description__c, File_Uploaded__c, Last_Version__c,
                       Last_Version__r.File_Name__c, Last_Version__r.Is_Previewable__c
                FROM Required_File__c
                WHERE Case__c = :recordId
                ORDER BY Name ASC
            ];
        } else if (objectApiName == 'Store__c') {
            requiredFiles = [
                SELECT Id, Name, Short_Description__c, File_Uploaded__c, Last_Version__c,
                       Last_Version__r.File_Name__c, Last_Version__r.Is_Previewable__c
                FROM Required_File__c
                WHERE Store__c = :recordId
                ORDER BY Name ASC
            ];
        } else {
            throw new AuraHandledException('Required files are only supported on Case and Store records.');
        }

        List<RequiredFileWrapper> wrappers = new List<RequiredFileWrapper>();
        for (Required_File__c requiredFile : requiredFiles) {
            wrappers.add(toWrapper(requiredFile));
        }
        return wrappers;
    }

    @AuraEnabled(cacheable=true)
    public static List<TemplateWrapper> getDocumentTemplates(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        if (objectApiName != 'Case' && objectApiName != 'Store__c') {
            throw new AuraHandledException('Document templates are only supported on Case and Store records.');
        }

        List<Document_Template__c> templates = [
            SELECT Id, Name, Short_Description__c, Accepted_Format__c
            FROM Document_Template__c
            WHERE Object_Api_Name__c = :objectApiName
            ORDER BY Name ASC
        ];

        List<TemplateWrapper> wrappers = new List<TemplateWrapper>();
        for (Document_Template__c template : templates) {
            TemplateWrapper wrapper = new TemplateWrapper();
            wrapper.id = template.Id;
            wrapper.name = template.Name;
            wrapper.shortDescription = template.Short_Description__c;
            wrapper.acceptedFormat = template.Accepted_Format__c;
            wrappers.add(wrapper);
        }
        return wrappers;
    }

    @AuraEnabled
    public static Id createRequiredFileDefault(
        Id recordId,
        String name,
        String acceptedFormat,
        String shortDescription,
        String instructions
    ) {
        validateDefaultInput(name, acceptedFormat, shortDescription);

        Required_File__c requiredFile = buildBaseRequiredFile(recordId);
        requiredFile.Name = name.trim();
        requiredFile.Accepted_Format__c = acceptedFormat;
        requiredFile.Short_Description__c = shortDescription.trim();
        requiredFile.Instructions__c = instructions;

        insert requiredFile;
        return requiredFile.Id;
    }

    @AuraEnabled
    public static Id createRequiredFileFromTemplate(Id recordId, Id templateId) {
        if (templateId == null) {
            throw new AuraHandledException('Document Template is required.');
        }

        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        Document_Template__c template = [
            SELECT Id, Name, Accepted_Format__c, Instructions__c, Short_Description__c, Object_Api_Name__c
            FROM Document_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];

        if (template.Object_Api_Name__c != objectApiName) {
            throw new AuraHandledException('Selected template is not available for this record type.');
        }

        Required_File__c requiredFile = buildBaseRequiredFile(recordId);
        requiredFile.Name = template.Name;
        requiredFile.Document_Template__c = template.Id;
        requiredFile.Accepted_Format__c = template.Accepted_Format__c;
        requiredFile.Instructions__c = template.Instructions__c;
        requiredFile.Short_Description__c = template.Short_Description__c;

        insert requiredFile;
        return requiredFile.Id;
    }

    private static Required_File__c buildBaseRequiredFile(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        Required_File__c requiredFile = new Required_File__c();

        if (objectApiName == 'Case') {
            requiredFile.Case__c = recordId;
        } else if (objectApiName == 'Store__c') {
            requiredFile.Store__c = recordId;
        } else {
            throw new AuraHandledException('Required files can only be created from Case or Store records.');
        }

        return requiredFile;
    }

    private static void validateDefaultInput(String name, String acceptedFormat, String shortDescription) {
        if (String.isBlank(name)) {
            throw new AuraHandledException('Name is required.');
        }
        if (String.isBlank(acceptedFormat)) {
            throw new AuraHandledException('Accepted Format is required.');
        }
        if (String.isBlank(shortDescription)) {
            throw new AuraHandledException('Short Description is required.');
        }
    }

    private static RequiredFileWrapper toWrapper(Required_File__c requiredFile) {
        RequiredFileWrapper wrapper = new RequiredFileWrapper();
        wrapper.id = requiredFile.Id;
        wrapper.name = requiredFile.Name;
        wrapper.shortDescription = requiredFile.Short_Description__c;
        wrapper.fileUploaded = requiredFile.File_Uploaded__c == true;
        wrapper.uploadedLabel = wrapper.fileUploaded ? 'Yes' : 'No';
        wrapper.lastVersionId = requiredFile.Last_Version__c;
        wrapper.uploadedFileName = requiredFile.Last_Version__r != null
            ? requiredFile.Last_Version__r.File_Name__c
            : null;
        wrapper.canPreview = wrapper.fileUploaded
            && requiredFile.Last_Version__c != null
            && requiredFile.Last_Version__r != null
            && requiredFile.Last_Version__r.Is_Previewable__c == true;
        return wrapper;
    }
}