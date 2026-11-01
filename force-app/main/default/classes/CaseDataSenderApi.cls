/**
 * @description  Sends Case data to an external API by Case Id.
 *               Safe version — builds field map manually and logs every API call.
 * @date         2025-11-03
 * @author       
 */
public with sharing class CaseDataSenderApi {

    /**
     * @description Input parameters passed from Flow.
     */
    public class InputParams {
        @InvocableVariable(label='Case Id' required=true)
        public Id caseId;

        @InvocableVariable(label='Action (Create or Update)' required=true)
        public String action;
    }

    /**
     * @description Entry point for Flow invocation.
     */
    @InvocableMethod(label='Parameter Case Id and Action from Flow')
    public static void sendCaseData(List<InputParams> params) {
        if (params == null || params.isEmpty()) {
            System.debug('⚠️ No parameters provided — exiting.');
            return;
        }

        for (InputParams input : params) {
            Id caseId = input.caseId;
            String action = input.action;

            if (caseId == null) {
                System.debug('⚠️ Null Case Id — skipping iteration.');
                continue;
            }

            if (String.isBlank(action)) {
                action = 'CREATE';
            }

            // Fetch Case record safely with explicitly listed fields
            List<Case> caseList = [
                SELECT  Amazon_Store_Name__c,
                Are_you_currently_selling_products_or_se__c,
                Are_you_the_owner__c,
                Are_you_using_your_trademark_on_a_produc__c,
                Are_you_willing_to_acknowledge_the_viola__c,
                ASIN__c,
                AssetId,
                At_risk_of_suspension_due_to_ODR__c,
                Brand_Description__c,
                Brand_Details__c,
                Brand_Name__c,
                Brand_Registry_Email__c,
                Brand_Registry_Phone_Number__c,
                Briefly_explain_how_you_will_be_using_th__c,
                BusinessHoursId,
                CaseNumber,
                Origin,
                OwnerId,
                Reason,
                RecordTypeId,
                SourceId,
                Category__c,
                IsClosedOnCreate,
                ContactEmail,
                ContactFax,
                ContactMobile,
                ContactId,
                ContactPhone,
                Contact_Position__c,
                CreatedById,
                Current_IPI_Score__c,
                Date_account_was_suspended__c,
                Date_linked_account_was_suspended__c,
                ClosedDate,
                CreatedDate,
                Deposit_upfront__c,
                Description,
                Description_of_inventory__c,
                Desired_Inventory_Limit_in_Cubit_Ft__c,
                Details__c,
                Do_you_have_a_Trademark__c,
                Do_you_need_an_urgent_disbursement_reque__c,
                Do_you_need_an_urgent_removal_order__c,
                Do_you_plan_to_continue_selling_this_ASI__c,
                Does_this_needs_to_be_expedited__c,
                Email__c,
                EntitlementId,
                IsEscalated,
                First_Name__c,
                First_use_anywhere_in_the_world__c,
                First_use_in_commerce__c,
                Fulfillment_Type__c,
                Full_details_of_linked_account_s_suspens__c,
                Full_details_of_suspension__c,
                Have_you_applied_for_a_trademark_before__c,
                Have_you_ever_filed_this_trademark_in_ot__c,
                Have_you_used_this_name_before__c,
                Impact_Level__c,
                Individual_Service_Options__c,
                Comments,
                Is_the_account_suspension_linked_to_anot__c,
                Is_the_increase_request_for_the_current__c,
                Is_there_inventory_at_risk_of_disposal__c,
                Is_your_account_at_risk_of_deactivation__c,
                Language,
                LastModifiedById,
                Last_Name__c,
                Linked_account_suspension_Category__c,
                List_all_of_the_products_or_services_tha__c,
                MilestoneStatus,
                AccountId,
                Name_of_linked_suspended_account__c,
                Name_or_Slogan_to_Protect__c,
                Opportunity__c,
                Order_ID__c,
                Other_Issues__c,
                ParentId,
                Payment_Status__c,
                Phone_Number__c,
                Please_confirm_the_filing_country__c,
                Please_select_the_country_where_you_firs__c,
                Please_select_the_date_when_you_first_fi__c,
                Priority,
                ProductId,
                Quantity__c,
                Reason_for_linked_account_s_suspension__c,
                Reason_for_loosing_approval__c,
                Reason_for_Storage_Increase__c,
                Reason_for_Suspension__c,
                Reasons_for_At_Risk_Status__c,
                Relevant_ASINS__c,
                Select_File_Type__c,
                ServiceContractId,
                Service_Type__c,
                SlaExitDate,
                SlaStartDate,
                Status,
                IsStopped,
                StopStartDate,
                Store__c,
                Store_Name__c,
                Subject,
                Suspension_Category__c,
                To_Protect__c,
                Total_Price__c,
                Type,
                Type_of_Inventory__c,
                Violation_Category__c,
                SuppliedCompany,
                SuppliedEmail,
                SuppliedName,
                SuppliedPhone,
                What_is_the_name_of_the_mark_holder__c,
                What_is_your_business_name__c,
                What_issues_are_you_experiencing_with_Br__c,
                What_products_or_services_do_you_offer__c,
                What_s_the_current_LSR__c,
                What_s_the_current_ODR__c,
                What_s_the_current_PFCR__c,
                What_s_the_current_VTR__c,
                Would_you_like_us_to_enrol_this_brand_in__c
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];

            if (caseList.isEmpty()) {
                System.debug('⚠️ No Case found for Id: ' + caseId);
                continue;
            }

            Case cs = caseList[0];

            // ----------------------------
            // Build Data Map manually
            // ----------------------------
            Map<String, Object> dataMap = new Map<String, Object>();
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();

            for (String fieldName : fieldMap.keySet()) {
                try {
                    Object val = cs.get(fieldName);
                    if (val != null) dataMap.put(fieldName, val);
                } catch (Exception e) {
                    System.debug('⚠️ Skipped field: ' + fieldName);
                }
            }

            // ----------------------------
            // Build clean JSON payload
            // ----------------------------
            String finalJson = '{' +
                '"object_type": "Case",' +
                '"action": "' + String.escapeSingleQuotes(action) + '",' +
                '"data": ' + JSON.serialize(dataMap) +
            '}';

            System.debug('🟦 Final JSON Payload: ' + finalJson);

            // Send asynchronously
            sendToExternalAPI(finalJson);
        }
    }

    /**
     * @description Performs async callout to external API and logs result.
     */
    @future(callout=true)
    public static void sendToExternalAPI(String jsonBody) {
        if (String.isBlank(jsonBody)) {
            System.debug('⚠️ Empty JSON body — skipping callout.');
            return;
        }

        HttpRequest req = new HttpRequest();
        String responseBody = '';
        String errorMsg = '';

        Appeals_WebhookApi__c config = Appeals_WebhookApi__c.getInstance();
        req.setEndpoint(config.EndPoint_URL__c);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-SF-AD-Webhook-Key', config.Api_Key__c);
        req.setBody(jsonBody);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            responseBody = res.getBody();
            System.debug('🟩 Response Code: ' + res.getStatusCode());
            System.debug('🟩 Response Body: ' + res.getBody());

            if (res.getStatusCode() >= 400) {
                errorMsg = 'API Error ' + res.getStatusCode() + ': ' + responseBody;
                System.debug('❌ API Error: ' + errorMsg);
            }
        } catch (Exception e) {
            errorMsg = 'Callout Exception: ' + e.getMessage();
            System.debug('❌ Exception during callout: ' + e.getMessage());
        }

        // Log API call
        try {
            Application_Log__c log = new Application_Log__c(
                Body__c = jsonBody,
                Response__c = responseBody,
                Error__c = errorMsg
            );
            insert log;
            System.debug('📝 Application_Log__c inserted successfully.');
        } catch (Exception ex) {
            System.debug('⚠️ Failed to insert Application_Log__c: ' + ex.getMessage());
        } 
    }
}