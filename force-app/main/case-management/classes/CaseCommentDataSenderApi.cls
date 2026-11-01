/**
 * @description Sends Case Comment data to an external API by Case_Comment__c Id.
 *              Can be invoked from Flow or called directly from Apex.
 * @author      Pravesh
 * @date        2025-11-03
 */
public with sharing class CaseCommentDataSenderApi {

/**
 * @description Invocable input class for Flow integration.
 */
public class InputParams {
    @InvocableVariable(label = 'Case Comment Id' required = true)
    public Id commentId;

    @InvocableVariable(label = 'Action (CREATE / UPDATE)' required = true)
    public String action;
}

/**
 * @description Invocable method that allows Flow to trigger Case Comment sync.
 */
@InvocableMethod(label = 'Send Case Comment Data to External API')
public static void sendCaseCommentDataFromFlow(List<InputParams> params) {
    if (params == null || params.isEmpty()) {
        System.debug('No input parameters received.');
        return;
    }
    String action;
    Id CaseCmId;

    for (InputParams p : params) {
        CaseCmId = p.commentId;
        action = p.action;
        if (CaseCmId != null) {
            sendCaseCommentData(new Set<Id> {CaseCmId}, action);
        } else {
            System.debug('Skipping record with null commentId.');
        }
    }
}
public Static void SendCaseCommentDataFromTrigger(Set<Id> CaseCmId, String action){
    sendCaseCommentData(CaseCmId, action);
}
/**
 * @description Sends Case Comment data by Id (core reusable logic).
 */
public static void sendCaseCommentData(Set<Id> commentId, String action) {
    if (commentId == null) {
        System.debug('Case_Comment__c Id is null — skipping send.');
        return;
    }

    if (String.isBlank(action)) {
        
    }

    // Fetch Case_Comment__c record
    Case_Comment__c comment = [
        SELECT Id, Case__c, Name, Comment__c, CreatedById, Incoming__c,
            Internal_Comment__c, LastModifiedById, OwnerId, Sender_User__c,
            Source_Type__c, Status__c, User_Name__c
        FROM Case_Comment__c
        WHERE Id = :commentId
        LIMIT 1
    ];

    // Build data map dynamically
    Map<String, Object> dataMap = new Map<String, Object>();
    Map<String, SObjectField> fieldMap = Case_Comment__c.SObjectType.getDescribe().fields.getMap();

    for (String fieldName : fieldMap.keySet()) {
        try {
            Object value = comment.get(fieldName);
            if (value != null) {
                dataMap.put(fieldName.toLowerCase(), value);
            }
        } catch (Exception e) {
            System.debug('Skipped field: ' + fieldName + ' due to error: ' + e.getMessage());
        }
    }

    //Serialize "data" portion
    String dataJson = JSON.serialize(dataMap);

    //Build structured payload
    String finalJson = '{' +
        '"object_type": "Case_Comment__c",' +
        '"action": "' + action + '",' +
        '"data": ' + dataJson +
    '}';

    System.debug('Final Ordered JSON Payload: ' + finalJson);

    //Send to external system asynchronously
    sendToExternalAPI(finalJson);
}

/**
 * @description Handles the actual HTTP callout to the external API.
 */
@future(callout = true)
public static void sendToExternalAPI(String jsonBody) {
    if (String.isBlank(jsonBody)) return;

    Appeals_WebhookApi__c config = Appeals_WebhookApi__c.getInstance();
    if (config == null || String.isBlank(config.EndPoint_URL__c) || String.isBlank(config.Api_Key__c))
        return;

    HttpRequest req = new HttpRequest();
    req.setEndpoint(config.EndPoint_URL__c);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('X-SF-AD-Webhook-Key', config.Api_Key__c);
    req.setBody(jsonBody);

    String responseBody = '';
    String errorMsg = '';

    try {
        HttpResponse res = new Http().send(req);
        responseBody = res.getBody();
    } catch (Exception e) {
        errorMsg = e.getMessage();
    }

    // Log API Interaction
    try {
        insert new Application_Log__c(
            Body__c     = jsonBody,
            Response__c = responseBody,
            Error__c    = errorMsg
        );
    } catch (Exception ex) {
        System.debug('Failed to log API interaction: ' + ex.getMessage());
    }
}
}