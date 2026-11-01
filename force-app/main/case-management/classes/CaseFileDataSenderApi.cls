/**
 * @description  Sends Case File data to an external API by Case_File__c Id.
 *               Safe version — builds field map manually and logs every API call.
 * @date         2025-11-03
 * @author       
 */
public with sharing class CaseFileDataSenderApi {

/**
 * @description Input parameters passed from Flow.
 */
public class InputParams {
    @InvocableVariable(label='Case File Id' required=true)
    public Id caseFileId;

    @InvocableVariable(label='Action (Create or Update)' required=true)
    public String action;
}

/**
 * @description Entry point for Flow invocation.
 */
@InvocableMethod(label='Parameter Case File Id and Action from Flow')
public static void sendCaseFileData(List<InputParams> params) {
    if (params == null || params.isEmpty()) {
        System.debug('No parameters provided — exiting.');
        return;
    }
    String action;
    Id fileId;

    for (InputParams input : params) {
        fileId = input.caseFileId;
        action = input.action;

    if (fileId != null) {
            sendCaseFileData(new Set<Id> {fileId}, action);
        } else {
            System.debug('Skipping record with null Case FileId.');
        }
    }
}  
public static void sendCaseFileDataFromTrigger(Set<Id> cSFileId, String action){
        sendCaseFileData(cSFileId, action);
        }
/**
 * @description Sends Case Comment data by Id (core reusable logic).
 */
public Static void sendCaseFileData(Set<Id> fileId, String action){
    System.debug('fileId' + fileId);
            if(fileId == null){
            System.debug('Case File Id is null — skipping send.');
            return;
            }
        // ----------------------------
        // Fetch Case_File__c record safely
        // ----------------------------
        List<Case_File__c> fileList = [
            SELECT Id, Case__c, Name, Client__c, Client_File_Info__c, Client_Response_Date_Time__c,
                CreatedById, Document_Type__c, File_Label__c, File_Link__c, File_Name__c,
                File_Size__c, File_Type__c, Info__c, Instructions__c, LastModifiedById,
                Verification_Status__c, Status_Reason__c, Stores__c
            FROM Case_File__c
            WHERE Id = :fileId
            LIMIT 1
        ];
    System.debug('fileList' + fileList);

    if (fileList.isEmpty()) {
            System.debug('No Case_File__c found for Id: ' + fileId);
            return;
        }

        Case_File__c fileRecord = fileList[0];

        // ----------------------------
        // Build Data Map dynamically
        // ----------------------------
        Map<String, Object> dataMap = new Map<String, Object>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case_File__c.fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            try {
                Object val = fileRecord.get(fieldName);
                if (val != null) dataMap.put(fieldName, val);
            } catch (Exception e) {
                System.debug('Skipped field: ' + fieldName);
            }
        }

        // ----------------------------
        // Build clean JSON payload
        // ----------------------------
        String finalJson = '{' +
            '"object_type": "Case_File__c",' +
            '"action": "' + String.escapeSingleQuotes(action) + '",' +
            '"data": ' + JSON.serialize(dataMap) +
        '}';

        System.debug('Final JSON Payload: ' + finalJson);

        // Send asynchronously
        sendToExternalAPI(finalJson);
    }

/**
 * @description Performs async callout to external API and logs result.
 */
/**
 * @description Performs callout to external API and logs result.
 */
public static void sendToExternalAPI(String jsonBody) {

    if (String.isBlank(jsonBody)) {
        System.debug('Empty JSON body — skipping callout.');
        return;
    }

    Appeals_WebhookApi__c config = Appeals_WebhookApi__c.getInstance();
    if (config == null || String.isBlank(config.EndPoint_URL__c) || String.isBlank(config.Api_Key__c)) {
        System.debug('Missing API configuration in Appeals_WebhookApi__c.');
        return;
    }

    HttpRequest req = new HttpRequest();
    req.setEndpoint(config.EndPoint_URL__c);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('X-SF-AD-Webhook-Key', config.Api_Key__c);
    req.setBody(jsonBody);

    String responseBody = '';
    String errorMsg = '';

    try {
        Http http = new Http();
        HttpResponse res = http.send(req);

        responseBody = res.getBody();

        System.debug('Response Code: ' + res.getStatusCode());
        if (res.getStatusCode() >= 400) {
            errorMsg = 'API Error ' + res.getStatusCode() + ': ' + responseBody;
        }

    } catch (Exception calloutEx) {
        errorMsg = 'Callout Exception: ' + calloutEx.getMessage();
        System.debug('Callout Error: ' + calloutEx.getMessage());
    }

    // Log response or error
    try {
        insert new Application_Log__c(
            Body__c     = jsonBody,
            Response__c = responseBody,
            Error__c    = errorMsg
        );
        System.debug('Application_Log__c inserted.');
    } catch (Exception logEx) {
        System.debug('Error inserting Application_Log__c: ' + logEx.getMessage());
    }
}
}