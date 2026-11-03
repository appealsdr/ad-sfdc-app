public with sharing class S3DocumentPathService {

    public static final String APP_ROOT = 'appealsDrApp';
    public static final String VUID_FIELD = 'appealsdoctor_vuid__c';

    public class UploadPath {
        public String bucket { get; set; }
        public String region { get; set; }
        public String s3KeyPrefix { get; set; }
        public String relatedObjectType { get; set; }
        public String relatedRecordId { get; set; }
        public Id requiredFileId { get; set; }
        public String pathDescription { get; set; }
    }

    public static UploadPath resolveUploadPath(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        String objectName = recordId.getSObjectType().getDescribe().getName();
        UploadPath path = new UploadPath();
        path.relatedRecordId = String.valueOf(recordId);
        path.relatedObjectType = objectName;
        path.bucket = resolveBucket();
        path.region = resolveRegion();

        if (objectName == 'Case') {
            buildCasePath(recordId, path);
        } else if (objectName == 'Store__c') {
            buildStorePath(recordId, path);
        } else if (objectName == 'Document_Template__c') {
            buildTemplatePath(recordId, path);
        } else if (objectName == 'Contract__c') {
            buildContractPath(recordId, path);
        } else if (objectName == 'Required_File__c') {
            buildRequiredFilePath(recordId, path);
        } else if (objectName == 'Account') {
            buildAccountPath(recordId, path);
        } else {
            throw new AuraHandledException('File upload is not supported for ' + objectName + ' records.');
        }

        return path;
    }

    public static String buildObjectKey(UploadPath path, String fileName) {
        String sanitizedFileName = sanitizeFileName(fileName);
        String uniquePrefix = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 32);
        return path.s3KeyPrefix + uniquePrefix + '_' + sanitizedFileName;
    }

    private static void buildCasePath(Id caseId, UploadPath path) {
        Case caseRecord = [
            SELECT Id, Store__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (caseRecord.Store__c == null) {
            throw new AuraHandledException('This case must be linked to a store before uploading files.');
        }

        StoreContext storeContext = loadStoreContext(caseRecord.Store__c);
        path.s3KeyPrefix = APP_ROOT + '/Accounts/' + storeContext.accountVuid
            + '/Stores/' + storeContext.storeVuid
            + '/Issues/' + caseId
            + '/Files/';
        path.pathDescription = 'Case issue files for store ' + storeContext.storeVuid;
    }

    private static void buildStorePath(Id storeId, UploadPath path) {
        StoreContext storeContext = loadStoreContext(storeId);
        path.s3KeyPrefix = APP_ROOT + '/Accounts/' + storeContext.accountVuid
            + '/Stores/' + storeContext.storeVuid
            + '/Documents/Files/';
        path.pathDescription = 'Store documents for store ' + storeContext.storeVuid;
    }

    private static void buildTemplatePath(Id templateId, UploadPath path) {
        path.s3KeyPrefix = APP_ROOT + '/Templates/' + templateId + '/Files/';
        path.pathDescription = 'Document template files';
    }

    private static void buildContractPath(Id contractId, UploadPath path) {
        Contract__c contract = [
            SELECT Id, Store__c
            FROM Contract__c
            WHERE Id = :contractId
            LIMIT 1
        ];

        String accountVuid = resolveAccountVuidFromStore(contract.Store__c);
        path.s3KeyPrefix = APP_ROOT + '/Accounts/' + accountVuid
            + '/Contracts/' + contractId
            + '/Files/';
        path.pathDescription = 'Contract files for account ' + accountVuid;
    }

    private static void buildRequiredFilePath(Id requiredFileId, UploadPath path) {
        Required_File__c requiredFile = [
            SELECT Id, Case__c, Store__c, Document_Template__c
            FROM Required_File__c
            WHERE Id = :requiredFileId
            LIMIT 1
        ];

        if (requiredFile.Case__c != null) {
            buildCasePath(requiredFile.Case__c, path);
            path.relatedRecordId = String.valueOf(requiredFile.Case__c);
            path.relatedObjectType = 'Case';
            path.requiredFileId = requiredFileId;
            return;
        }

        if (requiredFile.Store__c != null) {
            buildStorePath(requiredFile.Store__c, path);
            path.relatedRecordId = String.valueOf(requiredFile.Store__c);
            path.relatedObjectType = 'Store__c';
            path.requiredFileId = requiredFileId;
            return;
        }

        if (requiredFile.Document_Template__c != null) {
            buildTemplatePath(requiredFile.Document_Template__c, path);
            path.relatedRecordId = String.valueOf(requiredFile.Document_Template__c);
            path.relatedObjectType = 'Document_Template__c';
            path.requiredFileId = requiredFileId;
            return;
        }

        throw new AuraHandledException(
            'Required File must be linked to a Case, Store, or Document Template before uploading.'
        );
    }

    private static void buildAccountPath(Id accountId, UploadPath path) {
        String accountVuid = resolveVuidOrId('Account', accountId);
        path.s3KeyPrefix = APP_ROOT + '/Accounts/' + accountVuid + '/Files/';
        path.pathDescription = 'Account files for ' + accountVuid;
    }

    private static StoreContext loadStoreContext(Id storeId) {
        Store__c store = [
            SELECT Id, Account__c
            FROM Store__c
            WHERE Id = :storeId
            LIMIT 1
        ];

        StoreContext context = new StoreContext();
        context.storeVuid = resolveVuidOrId('Store__c', store.Id);
        context.accountVuid = store.Account__c != null
            ? resolveVuidOrId('Account', store.Account__c)
            : null;

        if (context.accountVuid == null) {
            throw new AuraHandledException('Store must be linked to an account before uploading files.');
        }

        return context;
    }

    private static String resolveAccountVuidFromStore(Id storeId) {
        if (storeId == null) {
            throw new AuraHandledException('Contract must be linked to a store before uploading files.');
        }

        Store__c store = [
            SELECT Id, Account__c
            FROM Store__c
            WHERE Id = :storeId
            LIMIT 1
        ];

        if (store.Account__c == null) {
            throw new AuraHandledException('Contract store must be linked to an account before uploading files.');
        }

        return resolveVuidOrId('Account', store.Account__c);
    }

    /**
     * appealsdoctor_vuid__c isn't present on every object in every org (e.g. it
     * doesn't exist on Account/Store__c in production). Falling back to the
     * record's own Id keeps S3 paths unique and stable instead of blocking
     * uploads outright when the field is absent or blank.
     */
    private static String resolveVuidOrId(String objectName, Id recordId) {
        if (hasVuidField(objectName)) {
            String query = 'SELECT ' + VUID_FIELD + ' FROM ' + objectName + ' WHERE Id = :recordId LIMIT 1';
            SObject record = Database.query(query);
            Object value = record.get(VUID_FIELD);
            if (value != null && String.isNotBlank(String.valueOf(value))) {
                return String.valueOf(value);
            }
        }
        return String.valueOf(recordId);
    }

    private static Boolean hasVuidField(String objectName) {
        Schema.SObjectType token = Schema.getGlobalDescribe().get(objectName);
        if (token == null) {
            return false;
        }
        return token.getDescribe().fields.getMap().containsKey(VUID_FIELD);
    }

    private static String resolveBucket() {
        Appeals_Dr_Setting__c settings = S3AwsPresignService.resolveSettings();
        if (settings != null && String.isNotBlank(settings.AWS_S3_Bucket__c)) {
            return settings.AWS_S3_Bucket__c.trim();
        }
        return 'amzn-andrei-appeals-dr-test-bucket';
    }

    private static String resolveRegion() {
        return S3AwsPresignService.resolveRegion(S3AwsPresignService.resolveSettings(), null);
    }

    private static String sanitizeFileName(String fileName) {
        if (String.isBlank(fileName)) {
            return 'file';
        }

        String sanitized = fileName.trim().replaceAll('[^a-zA-Z0-9._-]', '_');
        return String.isBlank(sanitized) ? 'file' : sanitized;
    }

    private class StoreContext {
        public String accountVuid;
        public String storeVuid;
    }
}
