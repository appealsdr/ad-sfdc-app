/**
* @description Sends Opportunity data to an external API by Opportunity Id.
*              Safe version — handles missing IDs and avoids QueryException.
* @author 
* @date 2025-11-03
*/
public without sharing class OpportunityDataSendersApi {
    
    /**
* @description Input parameters passed from Flow.
*/
    public class InputParams {
        @InvocableVariable(label='Opportunity Id' required=true)
        public Id opportunityId;
        
        @InvocableVariable(label='Action (Create or Update)' required=false)
        public String action;
    }
    
    /**
* @description Entry point for Flow invocation.
*/
    @InvocableMethod(label='Parameter oppId and Action from flow')
    public static void sendOpportunityData(List<InputParams> params) {
        if (params == null || params.isEmpty()) {
            System.debug('No parameters provided — exiting.');
            return;
        }
        String action;
        Id oppId;
        for (InputParams input : params) {
            oppId = input.opportunityId;
            action = input.action;
        }
       // Default action logic
        if (String.isBlank(action)) {
        action = 'Create';
    }
        if(oppId != null) {
            opportunityDataBody(new Set<Id> {oppId}, action);
        } 
    }
    
    public static void sendOpportunityDatabyTrigger(Set<Id> oppId, String action) {
        opportunityDataBody(oppId, action);
    }
    
    public static void opportunityDataBody(Set<Id> oppIds, String action) {
        if (oppIds == null || oppIds.isEmpty()) {
            return;
        }
        
        // -------------------------
        // STEP 1: Query related data
        // -------------------------
        List<Opportunity> oppList = [
            SELECT Id, Name, Amount, StageName, CloseDate, AccountId 
            FROM Opportunity 
            WHERE Id IN :oppIds
        ];
        
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : oppList) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        
        if (accountIds.isEmpty()) return;
        
        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, Name, Primary_Email__c                
            FROM Account 
            WHERE Id IN :accountIds
        ]);
        
        List<Contact> contactList = [
            SELECT Id, Client__c, AccountId, FirstName, LastName, Email, Phone 
            FROM Contact 
            WHERE Client__c IN :accountIds
        ];
        List<Store__c> storeList = [
            SELECT Id, Name, Account__c, Seller_ID__c
            FROM Store__c 
            WHERE Account__c IN :accountIds
        ];
        
        Set<Id> storeIds = new Set<Id>();
        for (Store__c s : storeList) {
            storeIds.add(s.Id);
        }
        
        Map<Id, List<Case>> storeCaseMap = new Map<Id, List<Case>>();
        if (!storeIds.isEmpty()) {
            for (Case c : [
                SELECT Id,          
                Amazon_Store_Name__c,
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
                Category_duplicate_Field__c,
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
                Frozen_Funds_USD__c,
                Fulfillment_Type__c,
                Full_details_of_linked_account_s_suspens__c,
                Full_details_of_suspension__c,
                Have_you_applied_for_a_trademark_before__c,
                Have_you_ever_filed_this_trademark_in_ot__c,
                Have_you_used_this_name_before__c,
                Impact_Level__c,
                Individual_Service_Options__c,
                Comments,
                Inventory_Value__c,
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
                Service_Name__c,
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
                WHERE Store__c IN :storeIds
                AND Opportunity__c IN :oppIds
            ]) {
                if (!storeCaseMap.containsKey(c.Store__c)) {
                    storeCaseMap.put(c.Store__c, new List<Case>());
                }
                storeCaseMap.get(c.Store__c).add(c);
            }
        }
        // -------------------------
        // Query Services
        // -------------------------
        Map<Id, List<Service__c>> oppToServices = new Map<Id, List<Service__c>>();
        List<Service__c> serviceList = [SELECT Id, Name, Store__c, Start_Date__c, End_Date__c, Contract_For_Month__c, Price__c, Store_Services__c, CreatedById, Description__c,CreatedDate
                                        FROM Service__c WHERE Store__c IN :oppIds];
        
        for(Service__c s : serviceList){
            if(!oppToServices.containsKey(s.Store__c)){
                oppToServices.put(s.Store__c, new List<Service__c>());
            }
            
            oppToServices.get(s.Store__c).add(s);
        }
        Set<Id> serviceIds = new Set<Id>();
        for(Service__c s : serviceList){
            serviceIds.add(s.Id);
        }
        
        // -------------------------
        // Query Retainer Services
        // -------------------------
        Map<Id, List<Retainer_Service__c>> serviceRetainerMap = new Map<Id, List<Retainer_Service__c>>();
        if(!serviceIds.isEmpty()){
            for(Retainer_Service__c rs : [SELECT Id, Name, Service__c, Case_Record_Type__c, Store_Opportunity__c,
                                          Start_Date__c,End_Date__c,Amount_Per_Month__c,Total_Case__c,Number_Of_Cases_Allowed_Per_Period__c
                                          FROM Retainer_Service__c WHERE Service__c IN :serviceIds]){
                                              
                                              if(!serviceRetainerMap.containsKey(rs.Service__c)){
                                                  serviceRetainerMap.put(rs.Service__c, new List<Retainer_Service__c>());
                                              }
                                              
                                              serviceRetainerMap.get(rs.Service__c).add(rs);
                                          }
        }
        
        // -------------------------
        // STEP 2: Build the wrapper
        // -------------------------
        OpportunityDataWrapper wrpp = new OpportunityDataWrapper();
        wrpp.object_type = 'Opportunity';
        wrpp.action = action;
        wrpp.timestamp = String.valueOf(System.now());
        
        wrpp.data = new OpportunityDataWrapper.Data();
        wrpp.data.CurrencyIsoCode = 'USD';
        wrpp.data.link_expiration = String.valueOf(System.now().addDays(7));  //'2025-12-31T00:00:00Z';
        
        // For simplicity, map the first Account (if multiple)
        Id firstAccId = accountIds.size() > 0 ? accountIds.iterator().next() : null;
        if (firstAccId != null && accMap.containsKey(firstAccId)) {
            Account acc = accMap.get(firstAccId);
            
            wrpp.data.customer = new OpportunityDataWrapper.Customer();
            wrpp.data.customer.Id = acc.Id;
            wrpp.data.customer.Name = acc.Name;
            wrpp.data.customer.PrimaryEmail = acc.Primary_Email__c;
            
            // Map Opportunities for that account
            wrpp.data.customer.Opportunities = new List<OpportunityDataWrapper.Opportunity>();
            for (Opportunity o : oppList) {
                if (o.AccountId == acc.Id) {
                    OpportunityDataWrapper.Opportunity oppWrap = new OpportunityDataWrapper.Opportunity();
                    oppWrap.Id = o.Id;
                    oppWrap.Name = o.Name;
                    oppWrap.Amount = o.Amount;
                    oppWrap.StageName = o.StageName;
                    oppWrap.CloseDate = o.CloseDate;
                    wrpp.data.customer.Opportunities.add(oppWrap);
                    
                    //Services
                    oppWrap.Services = new List<OpportunityDataWrapper.Service>();
                    if(oppToServices.containsKey(o.Id)){
                        
                        for(Service__c s : oppToServices.get(o.Id)){
                         OpportunityDataWrapper.Service sWrap = new OpportunityDataWrapper.Service();
                            sWrap.serviceId = s.Id;
                            sWrap.serviceName = s.Name;
                            sWrap.startDate = s.Start_Date__c;
                            sWrap.endDate = s.End_Date__c;
                            sWrap.months = s.Contract_For_Month__c;
                            sWrap.amountPerMonth = s.Price__c;
                            sWrap.storeId = s.Store_Services__c;
                            sWrap.oppId = s.Store__c;
                            sWrap.createdById = s.CreatedById;
                            sWrap.description = s.Description__c;
                            sWrap.createdDateTime = s.CreatedDate;
                            
                            // -------- Retainer Services --------
                            sWrap.RetainerServices = 
                                new List<OpportunityDataWrapper.RetainerService>();
                            
                            if(serviceRetainerMap.containsKey(s.Id)){
                                
                                for(Retainer_Service__c rs : serviceRetainerMap.get(s.Id)){
                                    
                                    OpportunityDataWrapper.RetainerService rsWrap = 
                                        new OpportunityDataWrapper.RetainerService();
                                    
                                    rsWrap.retainerServiceNo = rs.Name;
                                    rsWrap.caseRecordType = rs.Case_Record_Type__c;
                                    rsWrap.storeOpportunity = rs.Store_Opportunity__c;
                                    rsWrap.serviceId = rs.Service__c;
                                    rsWrap.startDate = rs.Start_Date__c;
                                    rsWrap.endDate = rs.End_Date__c;
                                    rsWrap.amountPerMonth = rs.Amount_Per_Month__c;
                                    rsWrap.totalCase = (Integer)rs.Total_Case__c;
                                    rsWrap.numberOfCasesAllowedPerPeriod = rs.Number_Of_Cases_Allowed_Per_Period__c;
                                    sWrap.RetainerServices.add(rsWrap);
                                }
                            }
                            oppWrap.Services.add(sWrap);
                        }
                    }
                    
                }
                
            }
            
            // Map Contacts for that account
            wrpp.data.customer.Contacts = new List<OpportunityDataWrapper.Contact>();
            for (Contact c : contactList) {
                if (c.Client__c == acc.Id) {
                    OpportunityDataWrapper.Contact cWrap = new OpportunityDataWrapper.Contact();
                    cWrap.Id = c.Id;
                    cWrap.FirstName = c.FirstName;
                    cWrap.LastName = c.LastName;
                    cWrap.Email = c.Email;
                    cWrap.Phone = c.Phone;
                    wrpp.data.customer.Contacts.add(cWrap);
                }
            }
        }
        
        // Map Stores and their Cases
        wrpp.data.customer.stores = new List<OpportunityDataWrapper.Store>();
        for (Store__c s : storeList) {
            OpportunityDataWrapper.Store sWrap = new OpportunityDataWrapper.Store();
            sWrap.Id = s.Id;
            sWrap.Name = s.Name;
            sWrap.SellerId = s.Seller_ID__c;
            sWrap.Cases = new List<OpportunityDataWrapper.CaseRecord>();
            
            if (storeCaseMap.containsKey(s.Id)) {
                for (Case c : storeCaseMap.get(s.Id)) {
                    OpportunityDataWrapper.CaseRecord caseWrap = new OpportunityDataWrapper.CaseRecord();
                    caseWrap.id = c.Id;
                    caseWrap.amazonStoreName = c.Amazon_Store_Name__c;
                    caseWrap.areYouCurrentlySellingProductsOrSe = c.Are_you_currently_selling_products_or_se__c;
                    caseWrap.areYouTheOwner = c.Are_you_the_owner__c;
                    caseWrap.areYouUsingYourTrademarkOnAProduct = c.Are_you_using_your_trademark_on_a_produc__c;
                    caseWrap.areYouWillingToAcknowledgeTheViolation = c.Are_you_willing_to_acknowledge_the_viola__c;
                    caseWrap.asin = c.ASIN__c;
                    caseWrap.assetId = c.AssetId;
                    caseWrap.atRiskOfSuspensionDueToOdr = c.At_risk_of_suspension_due_to_ODR__c;
                    caseWrap.brandDescription = c.Brand_Description__c;
                    caseWrap.brandDetails = c.Brand_Details__c;
                    caseWrap.brandName = c.Brand_Name__c;
                    caseWrap.brandRegistryEmail = c.Brand_Registry_Email__c;
                    caseWrap.brandRegistryPhoneNumber = c.Brand_Registry_Phone_Number__c;
                    caseWrap.brieflyExplainHowYouWillBeUsingTh = c.Briefly_explain_how_you_will_be_using_th__c;
                    caseWrap.businessHoursId = c.BusinessHoursId;
                    caseWrap.caseNumber = c.CaseNumber;
                    caseWrap.origin = c.Origin;
                    caseWrap.ownerId = c.OwnerId;
                    caseWrap.reason = c.Reason;
                    caseWrap.recordTypeId = c.RecordTypeId;
                    caseWrap.sourceId = c.SourceId;
                    caseWrap.category = c.Category__c;
                    caseWrap.categoryDuplicateField = c.Category_duplicate_Field__c;
                    caseWrap.isClosedOnCreate = c.IsClosedOnCreate;
                    caseWrap.contactEmail = c.ContactEmail;
                    caseWrap.contactFax = c.ContactFax;
                    caseWrap.contactMobile = c.ContactMobile;
                    caseWrap.contactId = c.ContactId;
                    caseWrap.contactPhone = c.ContactPhone;
                    caseWrap.contactPosition = c.Contact_Position__c;
                    caseWrap.createdById = c.CreatedById;
                    caseWrap.currentIpiScore = c.Current_IPI_Score__c;
                    caseWrap.dateAccountWasSuspended = c.Date_account_was_suspended__c;
                    caseWrap.dateLinkedAccountWasSuspended = c.Date_linked_account_was_suspended__c;
                    caseWrap.closedDate = c.ClosedDate;
                    caseWrap.createdDate = c.CreatedDate;
                    caseWrap.depositUpfront = c.Deposit_upfront__c;
                    caseWrap.description = c.Description;
                    caseWrap.descriptionOfInventory = c.Description_of_inventory__c;
                    caseWrap.desiredInventoryLimitInCubicFt = c.Desired_Inventory_Limit_in_Cubit_Ft__c;
                    caseWrap.details = c.Details__c;
                    caseWrap.doYouHaveATrademark = c.Do_you_have_a_Trademark__c;
                    caseWrap.doYouNeedAnUrgentDisbursementRequest = c.Do_you_need_an_urgent_disbursement_reque__c;
                    caseWrap.doYouNeedAnUrgentRemovalOrder = c.Do_you_need_an_urgent_removal_order__c;
                    caseWrap.doYouPlanToContinueSellingThisAsin = c.Do_you_plan_to_continue_selling_this_ASI__c;
                    caseWrap.doesThisNeedToBeExpedited = c.Does_this_needs_to_be_expedited__c;
                    caseWrap.email = c.Email__c;
                    caseWrap.entitlementId = c.EntitlementId;
                    caseWrap.isEscalated = c.IsEscalated;
                    caseWrap.firstName = c.First_Name__c;
                    caseWrap.firstUseAnywhereInTheWorld = c.First_use_anywhere_in_the_world__c;
                    caseWrap.firstUseInCommerce = c.First_use_in_commerce__c;
                    caseWrap.frozenFundsUsd = c.Frozen_Funds_USD__c;
                    caseWrap.fulfillmentType = c.Fulfillment_Type__c;
                    caseWrap.fullDetailsOfLinkedAccountSuspension = c.Full_details_of_linked_account_s_suspens__c;
                    caseWrap.fullDetailsOfSuspension = c.Full_details_of_suspension__c;
                    caseWrap.haveYouAppliedForATrademarkBefore = c.Have_you_applied_for_a_trademark_before__c;
                    caseWrap.haveYouEverFiledThisTrademarkInOther = c.Have_you_ever_filed_this_trademark_in_ot__c;
                    caseWrap.haveYouUsedThisNameBefore = c.Have_you_used_this_name_before__c;
                    caseWrap.impactLevel = c.Impact_Level__c;
                    caseWrap.individualServiceOptions = c.Individual_Service_Options__c;
                    caseWrap.comments = c.Comments;
                    caseWrap.inventoryValue = c.Inventory_Value__c;
                    caseWrap.isTheAccountSuspensionLinkedToAnother = c.Is_the_account_suspension_linked_to_anot__c;
                    caseWrap.isTheIncreaseRequestForTheCurrent = c.Is_the_increase_request_for_the_current__c;
                    caseWrap.isThereInventoryAtRiskOfDisposal = c.Is_there_inventory_at_risk_of_disposal__c;
                    caseWrap.isYourAccountAtRiskOfDeactivation = c.Is_your_account_at_risk_of_deactivation__c;
                    caseWrap.language = c.Language;
                    caseWrap.lastModifiedById = c.LastModifiedById;
                    caseWrap.lastName = c.Last_Name__c;
                    caseWrap.linkedAccountSuspensionCategory = c.Linked_account_suspension_Category__c;
                    caseWrap.listAllOfTheProductsOrServices = c.List_all_of_the_products_or_services_tha__c;
                    caseWrap.milestoneStatus = c.MilestoneStatus;
                    caseWrap.accountId = c.AccountId;
                    caseWrap.nameOfLinkedSuspendedAccount = c.Name_of_linked_suspended_account__c;
                    caseWrap.nameOrSloganToProtect = c.Name_or_Slogan_to_Protect__c;
                    caseWrap.opportunityId = c.Opportunity__c;
                    caseWrap.orderId = c.Order_ID__c;
                    caseWrap.otherIssues = c.Other_Issues__c;
                    caseWrap.parentId = c.ParentId;
                    caseWrap.paymentStatus = c.Payment_Status__c;
                    caseWrap.phoneNumber = c.Phone_Number__c;
                    caseWrap.pleaseConfirmTheFilingCountry = c.Please_confirm_the_filing_country__c;
                    caseWrap.pleaseSelectTheCountryWhereYouFirst = c.Please_select_the_country_where_you_firs__c;
                    caseWrap.pleaseSelectTheDateWhenYouFirstFiled = c.Please_select_the_date_when_you_first_fi__c;
                    caseWrap.priority = c.Priority;
                    caseWrap.productId = c.ProductId;
                    caseWrap.quantity = c.Quantity__c;
                    caseWrap.reasonForLinkedAccountSuspension = c.Reason_for_linked_account_s_suspension__c;
                    caseWrap.reasonForLosingApproval = c.Reason_for_loosing_approval__c;
                    caseWrap.reasonForStorageIncrease = c.Reason_for_Storage_Increase__c;
                    caseWrap.reasonForSuspension = c.Reason_for_Suspension__c;
                    caseWrap.reasonsForAtRiskStatus = c.Reasons_for_At_Risk_Status__c;
                    caseWrap.relevantAsins = c.Relevant_ASINS__c;
                    caseWrap.selectFileType = c.Select_File_Type__c;
                    caseWrap.serviceContractId = c.ServiceContractId;
                    caseWrap.serviceName = c.Service_Name__c;
                    caseWrap.serviceType = c.Service_Type__c;
                    caseWrap.slaExitDate = c.SlaExitDate;
                    caseWrap.slaStartDate = c.SlaStartDate;
                    caseWrap.status = c.Status;
                    caseWrap.isStopped = c.IsStopped;
                    caseWrap.stopStartDate = c.StopStartDate;
                    caseWrap.store = c.Store__c;
                    caseWrap.storeName = c.Store_Name__c;
                    caseWrap.subject = c.Subject;
                    caseWrap.suspensionCategory = c.Suspension_Category__c;
                    caseWrap.toProtect = c.To_Protect__c;
                    caseWrap.totalPrice = c.Total_Price__c;
                    caseWrap.type = c.Type;
                    caseWrap.typeOfInventory = c.Type_of_Inventory__c;
                    caseWrap.violationCategory = c.Violation_Category__c;
                    caseWrap.suppliedCompany = c.SuppliedCompany;
                    caseWrap.suppliedEmail = c.SuppliedEmail;
                    caseWrap.suppliedName = c.SuppliedName;
                    caseWrap.suppliedPhone = c.SuppliedPhone;
                    caseWrap.whatIsTheNameOfTheMarkHolder = c.What_is_the_name_of_the_mark_holder__c;
                    caseWrap.whatIsYourBusinessName = c.What_is_your_business_name__c;
                    caseWrap.whatIssuesAreYouExperiencingWithBrand = c.What_issues_are_you_experiencing_with_Br__c;
                    caseWrap.whatProductsOrServicesDoYouOffer = c.What_products_or_services_do_you_offer__c;
                    caseWrap.whatsTheCurrentLsr = c.What_s_the_current_LSR__c;
                    caseWrap.whatsTheCurrentOdr = c.What_s_the_current_ODR__c;
                    caseWrap.whatsTheCurrentPfcr = c.What_s_the_current_PFCR__c;
                    caseWrap.whatsTheCurrentVtr = c.What_s_the_current_VTR__c;
                    caseWrap.wouldYouLike = c.Would_you_like_us_to_enrol_this_brand_in__c;
                    
                    
                    
                    sWrap.Cases.add(caseWrap);
                }
            }
            wrpp.data.customer.stores.add(sWrap);
        }
        
        // -------------------------
        // STEP 3: Convert to JSON
        // -------------------------
        String jsonBody = JSON.serializePretty(wrpp);
        System.debug('Final JSON Body: ' + jsonBody);
        
        Id OppId = (oppIds != null && !oppIds.isEmpty()) ? oppIds.iterator().next() : null;
        
        sendToExternalAPI(jsonBody, OppId);
    }
    
    
    /**
* @description Performs async callout to external API.
*/
    @future(callout=true)
    public static void sendToExternalAPI(String jsonBody, Id oppId) {
        if (String.isBlank(jsonBody)) {
            System.debug('Empty JSON body — skipping callout.');
            return;
        }
        
        Appeals_WebhookApi__c config = Appeals_WebhookApi__c.getInstance();
        if (config == null || String.isBlank(config.EndPoint_URL__c) || String.isBlank(config.Api_Key__c)) {
            System.debug('Missing API configuration in Custom Setting.');
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
        String checkoutUrl = '';
        
        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            Integer statusCode = res.getStatusCode();
            responseBody = res.getBody();
            System.debug('Response: ' + responseBody);
            
            if (statusCode >= 400) {
                errorMsg = 'HTTP ' + statusCode + ': ' + responseBody;
            } else {
                // Parse checkout URL if available
                Map<String, Object> resp = 
                    (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                
                checkoutUrl = (String) resp.get('checkout_url');
                
                // Update Opportunity only if valid and present
                if (oppId != null && !String.isBlank(checkoutUrl)) {
                    update new Opportunity(Id = oppId, Checkout_URL__c = checkoutUrl);
                    System.debug('Checkout URL updated on Opportunity: ' + checkoutUrl);
                }
            }
            
        } catch (Exception ex) {
            errorMsg = 'Callout Exception: ' + ex.getMessage();
            System.debug(errorMsg);
        }
        
        // Log block — never inside a nested try/catch
        try {
            insert new Application_Log__c(
                Body__c = jsonBody,
                Response__c = responseBody,
                Error__c = errorMsg
            );
        } catch (Exception logEx) {
            System.debug('Log Insert Failed: ' + logEx.getMessage());
        }
    }
}