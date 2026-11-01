public class CaseFileController {

    public class DocTypeInput {
        @AuraEnabled public String documentTypeLabel  {get; set;}
        @AuraEnabled public String shortDescription {get; set;}
        @AuraEnabled public String instructions {get; set;}
    }

    @AuraEnabled(cacheable=true)
    public static List<Case_Document_Type_List__c> getCaseDocTypeList(){
        try {
            List<Case_Document_Type_List__c> caseDocTypeList = [SELECT Id, Name, Case_Document_Type_Label__c, Case_Document_Type_Value__c, Short_Description__c,Instructions__c FROM Case_Document_Type_List__c];
            return caseDocTypeList;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String createCaseFile(List<DocTypeInput> docTypes, Id caseId) {
        System.debug('Received caseId: ' + caseId);
        System.debug('Received docTypes: ' + JSON.serialize(docTypes));
        try {
            if (String.isBlank(caseId) || docTypes == null || docTypes.isEmpty()) {
                return 'Error: Invalid Case ID or Document Types.';
            }

            Case caseRecord = [SELECT Id, AccountId FROM Case WHERE Id = :caseId LIMIT 1];

            List<Case_File__c> caseFiles = new List<Case_File__c>();
            system.debug('caseFiles'+caseFiles);

            for (DocTypeInput docType : docTypes) {
                if (docType != null && !String.isBlank(docType.documentTypeLabel)) {
                    Case_File__c newRecord = new Case_File__c();
                        newRecord.Document_Type__c = docType.documentTypeLabel;
                        newRecord.Short_Description__c = docType.shortDescription;
                        newRecord.Instructions__c = docType.instructions;
                        newRecord.Case__c = caseId;
                        newRecord.Client__c = caseRecord.AccountId;
                    caseFiles.add(newRecord);
                }
            }

            if (!caseFiles.isEmpty()) {
                insert caseFiles;
            }
            system.debug('caseFiles'+caseFiles);
            return 'Success';

        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }


}