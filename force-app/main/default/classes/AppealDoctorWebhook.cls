/**
 * @description  Handles incoming webhook requests (like appealDoctor/webhook)
 *                and dynamically inserts/updates Salesforce records.
 * @author       
 * @createdDate  2025-10-24
 */
@RestResource(urlMapping='/appealDoctor/webhook')
global without sharing class AppealDoctorWebhook {

    @HttpPost
    global static ResponseWrapper createRecords() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        ResponseWrapper response = new ResponseWrapper();

        try {
            // Validate request body
            String requestBody = req.requestBody != null ? req.requestBody.toString() : null;
            if (String.isBlank(requestBody)) {
                res.statusCode = 400;
                return errorResponse('Empty request body.');
            }

            // Deserialize JSON into typed wrapper
            EventWrapper payload = (EventWrapper) JSON.deserialize(requestBody, EventWrapper.class);
            if (payload == null || String.isBlank(payload.event)) {
                res.statusCode = 400;
                return errorResponse('"event" is required.');
            }

            // Parse event → e.g. "Case_File__c:Insert"
            String[] parts = payload.event.split(':');
            String objectName = parts[0];
            String action = (parts.size() > 1) ? parts[1].trim() : null;

            if (String.isBlank(action)) {
                res.statusCode = 400;
                return errorResponse('Action is required in event (Insert/Update/Delete/Upsert).');
            }

            // Dispatch logic based on object
            switch on objectName {
                when 'Account' {
                    processGenericObject('Account', action, payload, response);
                }
                when 'Contact' {
                    processGenericObject('Contact', action, payload, response);
                }
                when 'Opportunity' {
                    processGenericObject('Opportunity', action, payload, response);
                }
                when 'Case_File__c' {
                    processCaseFile(action, payload, response, res);
                }
                when else {
                    res.statusCode = 400;
                    return errorResponse('Unsupported object: ' + objectName);
                }
            }

            res.statusCode = 200;
            response.status = 'success';
        } catch (AppealDoctorWebhookException e) {
            res.statusCode = 400;
            response = errorResponse(e.getMessage());
        } catch (Exception e) {
            System.debug('❌ Exception: ' + e.getMessage());
            res.statusCode = 500;
            response = errorResponse('Unexpected error: ' + e.getMessage());
        }

        return response;
    }

    // =========================================================
    // ========== OBJECT SPECIFIC PROCESSORS ===================
    // =========================================================

    private static void processCaseFile(String action, EventWrapper payload, ResponseWrapper response, RestResponse res) {
        if (payload.body == null || payload.body.isEmpty()) {
            throw new AppealDoctorWebhookException('Body cannot be empty for Case_File__c.');
        }

        List<Case_File__c> records = new List<Case_File__c>();

        for (BodyWrapper bw : payload.body) {
            if (bw.fields == null) continue;

            Case_File__c cf = new Case_File__c();

            if (action != 'Insert' && bw.fields.containsKey('Case_File_SF_ID')) {
                cf.Id = bw.fields.get('Case_File_SF_ID');
            }

            if (bw.fields.containsKey('File_Name')) 
                cf.File_Name__c = bw.fields.get('File_Name');
            if (bw.fields.containsKey('File_Type')) 
                cf.File_Type__c = bw.fields.get('File_Type');
            if (bw.fields.containsKey('Case_SF_ID')) 
                cf.Case__c = bw.fields.get('Case_SF_ID');
            if (bw.fields.containsKey('File_Size')) 
                cf.File_Size__c = Decimal.valueOf(bw.fields.get('File_Size'));
            if (bw.fields.containsKey('File_Link')) 
                cf.File_Link__c = bw.fields.get('File_Link');
            if (bw.fields.containsKey('Client_File_Info')) 
                cf.Info__c = bw.fields.get('Client_File_Info');
            if (bw.fields.containsKey('Status')) 
                cf.Verification_Status__c = bw.fields.get('Status');

            records.add(cf);
        }

        if (!records.isEmpty()) {
            try {
                if (action == 'Upsert') {
                    Upsert records;
               /* } else if (action == 'Update') {
                    update records;
                } else if (action == 'Insert') {
                    Insert records;
                } else if (action == 'Delete') {
                    delete records; */
                } else {
                    throw new AppealDoctorWebhookException('Unsupported action: ' + action);
                }
            } catch (DmlException de) {
                throw new AppealDoctorWebhookException('DML Error: ' + de.getMessage());
            }
        }

        response.status = 'success';
        response.objectName = 'Case_File__c';
        response.action = action;
        response.recordsProcessed = records.size();
        response.message = 'Records processed successfully ✅';
    }

    // For future scalability — generic objects like Account, Contact etc.
    private static void processGenericObject(String objectName, String action, EventWrapper payload, ResponseWrapper response) {
        response.status = 'success';
        response.objectName = objectName;
        response.action = action;
        response.recordsProcessed = (payload.body != null) ? payload.body.size() : 0;
    }

    // =========================================================
    // ========== WRAPPER CLASSES ==============================
    // =========================================================
    public class EventWrapper {
        public String event;
        public List<BodyWrapper> body; 
    }

    public class BodyWrapper {
        public Map<String, String> fields;
    }

    global class ResponseWrapper {
        public String status;
        public String objectName;
        public String action;
        public String message;
        public Integer recordsProcessed;
    }

    // =========================================================
    // ========== CUSTOM EXCEPTION =============================
    // =========================================================
    public class AppealDoctorWebhookException extends Exception {}

    // =========================================================
    // ========== HELPER METHODS ===============================
    // =========================================================
    private static ResponseWrapper errorResponse(String message) {
        ResponseWrapper resp = new ResponseWrapper();
        resp.status = 'error';
        resp.message = message;
        resp.recordsProcessed = 0;
        return resp;
    }
}