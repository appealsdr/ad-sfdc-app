@RestResource(urlMapping='/Payment/create')
global with sharing class PaymentWebhookService {
    /*
     * Previous payment webhook implementation retained for reference.
     * This legacy Payments wrapper and upsert flow are intentionally inactive.


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

    */

    /**
     * Receives verified Stripe invoice.payment_succeeded events through the
     * existing authenticated Salesforce REST integration. The forwarding
     * integration must verify Stripe-Signature before calling this endpoint.
     */
    @HttpPost
    global static String upsertPayment() {
        String jsonBody = '';
        String responseBody = '';
        String errorMsg = '';
        try {
            jsonBody = RestContext.request.requestBody == null
                ? '' : RestContext.request.requestBody.toString();
            if (String.isBlank(jsonBody)) {
                throw new InvalidWebhookException('Request body is empty');
            }

            Map<String, Object> event = asObject(JSON.deserializeUntyped(jsonBody));
            String eventId = requiredText(event.get('id'), 'Stripe event id');
            String eventType = requiredText(event.get('type'), 'Stripe event type');
            if (eventType != 'invoice.payment_succeeded') {
                responseBody = respond(200, 'ignored', 'Unsupported Stripe event type');
                return responseBody;
            }

            Map<String, Object> invoice = asObject(asObject(event.get('data')).get('object'));
            String invoiceId = requiredText(invoice.get('id'), 'Stripe invoice id');
            String subscriptionId = stripeId(invoice.get('subscription'));
            if (String.isBlank(subscriptionId)) {
                Map<String, Object> parent = asObject(invoice.get('parent'));
                subscriptionId = stripeId(asObject(parent.get('subscription_details')).get('subscription'));
            }
            if (String.isBlank(subscriptionId)) {
                responseBody = respond(200, 'ignored', 'Invoice is not related to a subscription');
                return responseBody;
            }
            if (textValue(invoice.get('status')) != 'paid' || invoice.get('paid_out_of_band') == true) {
                responseBody = respond(200, 'ignored', 'Invoice has not been paid through Stripe');
                return responseBody;
            }

            String currencyCode = requiredText(invoice.get('currency'), 'Invoice currency').toUpperCase();
            Decimal minorAmount = numberValue(invoice.get('amount_paid'), 'Invoice amount_paid');
            if (minorAmount < 0 || minorAmount != minorAmount.setScale(0)) {
                throw new InvalidWebhookException('Invoice amount_paid must be a non-negative integer');
            }
            if (minorAmount == 0) {
                responseBody = respond(200, 'ignored', 'Invoice has no payment amount');
                return responseBody;
            }
            Decimal amount = paymentAmount(minorAmount, currencyCode);
            String paidAt = paidAtValue(invoice, event);
            String paymentIntentId = paymentIntentId(invoice);

            // Lock the parent before checking for a payment. Concurrent retries
            // for this subscription must wait, then see the committed payment.
            List<ServiceContract> contracts = [
                SELECT Id FROM ServiceContract
                WHERE Stripe_Subscription_Id__c = :subscriptionId
                LIMIT 1 FOR UPDATE
            ];
            if (contracts.isEmpty()) {
                responseBody = respond(404, 'error', 'No Service Contract found for Stripe subscription ' + subscriptionId);
                errorMsg = 'Service Contract not found';
                return responseBody;
            }
            Id contractId = contracts[0].Id;
            List<Payment__c> existingPayments = [
                SELECT Id, Service_Contract__c FROM Payment__c
                WHERE Stripe_EventId__c = :eventId
                   OR (Service_Contract__c = :contractId AND Order_Ref__c = :invoiceId)
                LIMIT 1
            ];
            if (!existingPayments.isEmpty()) {
                Payment__c existingPayment = existingPayments[0];
                if (existingPayment.Service_Contract__c != contractId) {
                    responseBody = respond(409, 'error', 'Stripe event is already linked to a different Service Contract');
                    errorMsg = 'Conflicting Stripe event id';
                    return responseBody;
                }
                RestContext.response.statusCode = 200;
                responseBody = JSON.serialize(new Map<String, Object>{
                    'status' => 'success', 'message' => 'Payment already recorded',
                    'paymentId' => existingPayment.Id, 'serviceContractId' => contractId
                });
                return responseBody;
            }

            Payment__c payment = new Payment__c(
                Service_Contract__c = contractId,
                Stripe_EventId__c = eventId,
                Stripe_Payment_Intent_Id__c = paymentIntentId,
                Amount__c = amount,
                Amount_Applied__c = String.valueOf(amount),
                CurrencyIsoCode__c = currencyCode,
                Status__c = 'Paid',
                Payment_Type__c = 'Subscription',
                Order_Ref__c = invoiceId,
                PaidAt__c = paidAt,
                Description__c = truncate(textValue(invoice.get('description')), 255)
            );
            insert payment;
            RestContext.response.statusCode = 200;
            responseBody = JSON.serialize(new Map<String, Object>{
                'status' => 'success', 'message' => 'Subscription payment created successfully',
                'paymentId' => payment.Id, 'serviceContractId' => contractId
            });
            return responseBody;
        } catch (InvalidWebhookException e) {
            errorMsg = e.getMessage();
            responseBody = respond(400, 'error', errorMsg);
            return responseBody;
        } catch (System.JSONException e) {
            errorMsg = e.getMessage();
            responseBody = respond(400, 'error', 'Invalid JSON request body');
            return responseBody;
        } catch (Exception e) {
            errorMsg = e.getMessage();
            responseBody = respond(500, 'error', 'Unable to record subscription payment');
            return responseBody;
        } finally {
            // Preserve request/response logging for every delivery and outcome.
            try {
                insert new Application_Log__c(
                    Body__c = truncate(jsonBody, Application_Log__c.Body__c.getDescribe().getLength()),
                    Response__c = truncate(responseBody, Application_Log__c.Response__c.getDescribe().getLength()),
                    Error__c = truncate(errorMsg, Application_Log__c.Error__c.getDescribe().getLength())
                );
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Payment webhook logging failed: ' + e.getMessage());
            }
        }
    }

    private static String respond(Integer statusCode, String status, String message) {
        RestContext.response.statusCode = statusCode;
        return JSON.serialize(new Map<String, Object>{'status' => status, 'message' => message});
    }

    private static Map<String, Object> asObject(Object value) {
        if (value == null) return new Map<String, Object>();
        if (!(value instanceof Map<String, Object>)) {
            throw new InvalidWebhookException('Expected a JSON object');
        }
        return (Map<String, Object>) value;
    }

    private static String textValue(Object value) {
        if (value == null) return null;
        if (!(value instanceof String)) {
            throw new InvalidWebhookException('Expected a text value');
        }
        return (String) value;
    }

    private static String requiredText(Object value, String label) {
        String text = textValue(value);
        if (String.isBlank(text) || text.length() > 255) {
            throw new InvalidWebhookException(label + ' is required and must be at most 255 characters');
        }
        return text;
    }

    private static String stripeId(Object value) {
        return value instanceof Map<String, Object> ? textValue(asObject(value).get('id')) : textValue(value);
    }

    private static Decimal numberValue(Object value, String label) {
        if (value == null || value instanceof String || value instanceof Boolean) {
            throw new InvalidWebhookException(label + ' must be a number');
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            throw new InvalidWebhookException(label + ' must be a number');
        }
    }

    private static Decimal paymentAmount(Decimal minorAmount, String currencyCode) {
        if (!Pattern.matches('[A-Z]{3}', currencyCode)) {
            throw new InvalidWebhookException('Invoice currency must be a three-letter ISO code');
        }
        // ISK and UGX intentionally use /100: Stripe keeps their two-decimal
        // API representation for backward compatibility.
        Set<String> zeroDecimal = new Set<String>{
            'BIF', 'CLP', 'DJF', 'GNF', 'JPY', 'KMF', 'KRW',
            'MGA', 'PYG', 'RWF', 'VND', 'VUV', 'XAF', 'XOF', 'XPF'
        };
        Set<String> threeDecimal = new Set<String>{'BHD', 'JOD', 'KWD', 'OMR', 'TND'};
        Decimal divisor = zeroDecimal.contains(currencyCode) ? 1 : (threeDecimal.contains(currencyCode) ? 1000 : 100);
        Decimal amount = minorAmount / divisor;
        if (amount != amount.setScale(2) || amount > 9999999999999999.99) {
            throw new InvalidWebhookException('Invoice amount cannot be represented exactly in Payment Amount (18,2)');
        }
        return amount.setScale(2);
    }

    private static String paidAtValue(Map<String, Object> invoice, Map<String, Object> event) {
        Object paidAt = asObject(invoice.get('status_transitions')).get('paid_at');
        if (paidAt == null) paidAt = event.get('created');
        if (paidAt == null) return null;
        Decimal seconds = numberValue(paidAt, 'Payment timestamp');
        if (seconds < 0 || seconds != seconds.setScale(0)) {
            throw new InvalidWebhookException('Payment timestamp must be a non-negative integer');
        }
        try {
            return Datetime.newInstance(seconds.longValue() * 1000).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        } catch (Exception e) {
            throw new InvalidWebhookException('Invalid payment timestamp');
        }
    }

    private static String paymentIntentId(Map<String, Object> invoice) {
        String intentId = stripeId(invoice.get('payment_intent'));
        if (!String.isBlank(intentId)) return intentId;
        Object entries = asObject(invoice.get('payments')).get('data');
        if (entries == null) return null;
        if (!(entries instanceof List<Object>)) {
            throw new InvalidWebhookException('Invoice payments.data must be a list');
        }
        for (Object entry : (List<Object>) entries) {
            Map<String, Object> invoicePayment = asObject(entry);
            if (textValue(invoicePayment.get('status')) != 'paid') continue;
            Map<String, Object> payment = asObject(invoicePayment.get('payment'));
            if (textValue(payment.get('type')) == 'payment_intent') {
                return stripeId(payment.get('payment_intent'));
            }
        }
        return null;
    }

    private static String truncate(String value, Integer maxLength) {
        return value == null ? null : value.left(maxLength);
    }

    private class InvalidWebhookException extends Exception {}
}
