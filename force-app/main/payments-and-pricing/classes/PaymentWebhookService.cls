@RestResource(urlMapping='/Payment/create')
global with sharing class PaymentWebhookService {

    // Wrapper class for JSON payload inside "Payments"
    global class PaymentWrapper {
        public String stripeEventId;
        public String stripePaymentIntentId;
        public String stripeCheckoutSessionId;
        public Decimal amount;
        public String CurrencyIsoCode;
        public String paymentType;
        public String status;
        public String paymentMethod;
        public String paidAt;
        public String orderRef;
        public String guestOrderId;
        public String caseSFId;
        public String amountApplied;
        public String description;
    }

    // Wrapper for the outer "Payments" key
    global class PaymentsWrapper {
        public PaymentWrapper Payments;
    }

    @HttpPost
    global static String upsertPayment() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String jsonBody = '';
        String responseBody = '';
        String errorMsg = '';

        try {
            jsonBody = req.requestBody != null ? req.requestBody.toString() : '';
            if (String.isBlank(jsonBody)) {
                res.statusCode = 400;
                responseBody = '{"status":"error","message":"Request body is empty"}';
                return responseBody;
            }

            PaymentsWrapper wrapper = (PaymentsWrapper) JSON.deserialize(jsonBody, PaymentsWrapper.class);
            PaymentWrapper input = wrapper.Payments;

            if (input == null || String.isBlank(input.stripePaymentIntentId)) {
                res.statusCode = 400;
                responseBody = '{"status":"error","message":"Stripe Payment Intent Id is required"}';
                return responseBody;
            }

            Payment__c payment;
            List<Payment__c> existingPayments = [
                SELECT Id 
                FROM Payment__c 
                WHERE Stripe_EventId__c = :input.stripeEventId 
                LIMIT 1
            ];

            if (!existingPayments.isEmpty()) {
                payment = existingPayments[0];
            } else {
                payment = new Payment__c();
            }

            // Map fields
            payment.Case__c                       = input.caseSFId;
            payment.Stripe_EventId__c             = input.stripeEventId;
            payment.Stripe_Payment_Intent_Id__c   = input.stripePaymentIntentId;
            payment.Stripe_Checkout_Session_Id__c = input.stripeCheckoutSessionId;
            payment.Amount__c                     = input.amount;
            payment.Payment_Type__c               = input.paymentType;
            payment.Status__c                     = input.status;
            payment.Payment_Method__c             = input.paymentMethod;
            payment.Order_Ref__c                  = input.orderRef;
            payment.Guest_Order_Id__c             = input.guestOrderId;
            payment.Case_SF_ID__c                 = input.caseSFId;
            payment.Amount_Applied__c             = input.amountApplied;
            payment.Description__c                = input.description;
            payment.PaidAt__c                     = input.paidAt;
            payment.CurrencyIsoCode__c            = input.CurrencyIsoCode;

            upsert payment;

            res.statusCode = 200;
            responseBody = JSON.serializePretty(new Map<String, Object>{
                'status' => 'success',
                'message' => existingPayments.isEmpty() 
                    ? 'Payment record created successfully' 
                    : 'Payment record updated successfully',
                'paymentId' => payment.Id
            });

            return responseBody;

        } catch (Exception e) {
            errorMsg = e.getMessage();
            System.debug('Error in PaymentWebhookService: ' + errorMsg);
            res.statusCode = 500;
            responseBody = JSON.serializePretty(new Map<String, Object>{
                'status' => 'error',
                'message' => errorMsg
            });
            return responseBody;
        } finally {
            // Logging
            try {
                Application_Log__c log = new Application_Log__c(
                    Body__c = jsonBody,
                    Response__c = responseBody,
                    Error__c = errorMsg
                );
                insert log;
                System.debug('Application_Log__c inserted successfully.');
            } catch (Exception ex) {
                System.debug(' Failed to insert Application_Log__c: ' + ex.getMessage());
            }
        }
    }
}