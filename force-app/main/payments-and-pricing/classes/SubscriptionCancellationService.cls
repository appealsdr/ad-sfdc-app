/**
 * Receives signature-verified Stripe subscription events through the existing
 * authenticated Salesforce integration. The forwarding integration verifies
 * Stripe-Signature and reconciles event ordering before delivery.
 */
@RestResource(urlMapping='/Subscription/cancel')
global with sharing class SubscriptionCancellationService {
    @HttpPost
    global static void receiveCancellation() {
        String jsonBody = '';
        String errorMsg = '';
        try {
            jsonBody = RestContext.request.requestBody == null
                ? '' : RestContext.request.requestBody.toString();
            if (String.isBlank(jsonBody)) {
                throw new InvalidWebhookException('Request body is empty');
            }
            processEvent(asObject(JSON.deserializeUntyped(jsonBody)));
        } catch (InvalidWebhookException e) {
            errorMsg = e.getMessage();
            reply(400, 'error', errorMsg, null, null);
        } catch (System.JSONException e) {
            errorMsg = e.getMessage();
            reply(400, 'error', 'Invalid JSON request body', null, null);
        } catch (Exception e) {
            errorMsg = e.getMessage();
            reply(500, 'error', 'Unable to update subscription cancellation', null, null);
        } finally {
            try {
                String responseBody = RestContext.response.responseBody == null
                    ? '' : RestContext.response.responseBody.toString();
                if (RestContext.response.statusCode >= 400 && String.isBlank(errorMsg)) {
                    errorMsg = responseBody;
                }
                insert new Application_Log__c(
                    Body__c = truncate(jsonBody, Application_Log__c.Body__c.getDescribe().getLength()),
                    Response__c = truncate(responseBody, Application_Log__c.Response__c.getDescribe().getLength()),
                    Error__c = truncate(errorMsg, Application_Log__c.Error__c.getDescribe().getLength())
                );
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Subscription cancellation logging failed: ' + e.getMessage());
            }
        }
    }

    private static void processEvent(Map<String, Object> event) {
        String eventId = requiredText(event.get('id'), 'Stripe event id');
        String eventType = requiredText(event.get('type'), 'Stripe event type');
        if (eventType != 'customer.subscription.updated' && eventType != 'customer.subscription.deleted') {
            reply(200, 'ignored', 'Unsupported Stripe event type', null, null);
            return;
        }
        Datetime eventAt = timestamp(event.get('created'), 'Stripe event created');
        Map<String, Object> subscription = asObject(asObject(event.get('data')).get('object'));
        if (requiredText(subscription.get('object'), 'Stripe object type') != 'subscription') {
            throw new InvalidWebhookException('Expected a Stripe subscription object');
        }
        String subscriptionId = requiredText(subscription.get('id'), 'Stripe subscription id');
        String stripeStatus = requiredText(subscription.get('status'), 'Stripe subscription status');
        Boolean terminal = stripeStatus == 'canceled';
        if (eventType == 'customer.subscription.deleted' && !terminal) {
            throw new InvalidWebhookException('Deleted subscription must have canceled status');
        }

        // Serialize deliveries that update the same contract.
        List<ServiceContract> contracts = [
            SELECT Id, StartDate, EndDate, Stripe_Cancellation_Status__c,
                Stripe_Active_Until__c, Stripe_Cancel_Event_Id__c,
                Stripe_Cancel_Event_At__c, Stripe_Pre_Cancel_End_Date__c
            FROM ServiceContract WHERE Stripe_Subscription_Id__c = :subscriptionId
            LIMIT 1 FOR UPDATE
        ];
        if (contracts.isEmpty()) {
            reply(404, 'error', 'No Service Contract found for Stripe subscription ' + subscriptionId, null, subscriptionId);
            return;
        }
        ServiceContract contract = contracts[0];
        if (contract.Stripe_Cancel_Event_Id__c == eventId) {
            reply(200, 'success', 'Stripe event already processed', contract, subscriptionId);
            return;
        }
        if (contract.Stripe_Cancel_Event_At__c != null && eventAt < contract.Stripe_Cancel_Event_At__c
            && !(terminal && contract.Stripe_Cancellation_Status__c != 'Canceled')) {
            reply(200, 'ignored', 'Older Stripe event ignored', contract, subscriptionId);
            return;
        }
        // Stripe never reactivates a canceled subscription. A new subscription
        // has a different ID, so a delayed update cannot reopen this contract.
        if (contract.Stripe_Cancellation_Status__c == 'Canceled' && !terminal) {
            reply(200, 'ignored', 'Canceled subscription cannot be reopened', contract, subscriptionId);
            return;
        }

        Datetime activeUntil;
        String cancellationStatus = 'None';
        if (terminal) {
            cancellationStatus = 'Canceled';
            // canceled_at may be the earlier scheduling request timestamp.
            // ended_at is the actual service end, including immediate cancels.
            activeUntil = timestamp(subscription.get('ended_at'), 'Subscription ended_at');
        } else {
            Object periodEndFlag = subscription.get('cancel_at_period_end');
            if (!(periodEndFlag instanceof Boolean)) {
                throw new InvalidWebhookException('Subscription cancel_at_period_end must be a boolean');
            }
            if (subscription.get('cancel_at') != null || (Boolean) periodEndFlag) {
                cancellationStatus = 'Scheduled';
                activeUntil = scheduledCutoff(subscription);
            }
        }

        Boolean sameState = contract.Stripe_Cancellation_Status__c == cancellationStatus
            && contract.Stripe_Active_Until__c == activeUntil;
        // created has only second precision. Do not invent an ordering between
        // conflicting snapshots from the same second. A terminal cancellation
        // may safely supersede a nonterminal snapshot because it cannot resume.
        if (contract.Stripe_Cancel_Event_At__c == eventAt && !sameState
            && !(terminal && contract.Stripe_Cancellation_Status__c != 'Canceled')) {
            reply(409, 'error', 'Conflicting events share a timestamp; reconcile with Stripe before retrying', contract, subscriptionId);
            return;
        }

        if (activeUntil != null) {
            // Stripe cutoff is exclusive. A midnight cutoff on Dec 1 means the
            // last inclusive UTC service day is Nov 30.
            Date activeThrough = activeUntil.addSeconds(-1).dateGmt();
            if (contract.StartDate != null && activeThrough < contract.StartDate) {
                reply(409, 'error', 'Cancellation date precedes the Service Contract start date', contract, subscriptionId);
                return;
            }
            if (cancellationStatus == 'Scheduled' && contract.Stripe_Cancellation_Status__c != 'Scheduled') {
                contract.Stripe_Pre_Cancel_End_Date__c = contract.EndDate;
            }
            contract.EndDate = activeThrough;
            if (terminal) contract.Stripe_Pre_Cancel_End_Date__c = null;
        } else if (contract.Stripe_Cancellation_Status__c == 'Scheduled') {
            contract.EndDate = contract.Stripe_Pre_Cancel_End_Date__c;
            contract.Stripe_Pre_Cancel_End_Date__c = null;
        }
        contract.Stripe_Cancellation_Status__c = cancellationStatus;
        contract.Stripe_Active_Until__c = activeUntil;
        contract.Stripe_Cancel_Event_Id__c = eventId;
        if (contract.Stripe_Cancel_Event_At__c == null || eventAt > contract.Stripe_Cancel_Event_At__c) {
            contract.Stripe_Cancel_Event_At__c = eventAt;
        }
        update contract;
        reply(200, 'success', 'Subscription cancellation synchronized', contract, subscriptionId);
    }

    private static Datetime scheduledCutoff(Map<String, Object> subscription) {
        if (subscription.get('cancel_at') != null) {
            return timestamp(subscription.get('cancel_at'), 'Subscription cancel_at');
        }
        if (subscription.get('current_period_end') != null) {
            return timestamp(subscription.get('current_period_end'), 'Subscription current_period_end');
        }
        // Modern Stripe versions put period ends on subscription items. Only
        // infer one contract cutoff when the complete set has one shared end.
        Map<String, Object> items = asObject(subscription.get('items'));
        if (items.get('has_more') == true) {
            throw new InvalidWebhookException('Incomplete subscription items require an explicit cancel_at');
        }
        Object entries = items.get('data');
        if (!(entries instanceof List<Object>) || ((List<Object>) entries).isEmpty()) {
            throw new InvalidWebhookException('Scheduled cancellation requires cancel_at or a billing period end');
        }
        Datetime cutoff;
        for (Object entry : (List<Object>) entries) {
            Datetime itemEnd = timestamp(asObject(entry).get('current_period_end'), 'Subscription item current_period_end');
            if (cutoff != null && cutoff != itemEnd) {
                throw new InvalidWebhookException('Mixed billing periods require an explicit cancel_at');
            }
            cutoff = itemEnd;
        }
        return cutoff;
    }

    private static void reply(Integer statusCode, String status, String message,
        ServiceContract contract, String subscriptionId) {
        Map<String, Object> body = new Map<String, Object>{'status' => status, 'message' => message};
        if (subscriptionId != null) body.put('subscriptionId', subscriptionId);
        if (contract != null) {
            body.put('serviceContractId', contract.Id);
            body.put('cancellationStatus', contract.Stripe_Cancellation_Status__c);
            body.put('activeUntil', contract.Stripe_Active_Until__c == null ? null
                : contract.Stripe_Active_Until__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
            body.put('activeThroughDate', contract.EndDate);
        }
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    private static Map<String, Object> asObject(Object value) {
        if (value == null) return new Map<String, Object>();
        if (!(value instanceof Map<String, Object>)) {
            throw new InvalidWebhookException('Expected a JSON object');
        }
        return (Map<String, Object>) value;
    }

    private static String requiredText(Object value, String label) {
        if (!(value instanceof String) || String.isBlank((String) value) || ((String) value).length() > 255) {
            throw new InvalidWebhookException(label + ' is required and must be text of at most 255 characters');
        }
        return (String) value;
    }

    private static Datetime timestamp(Object value, String label) {
        if (value == null || value instanceof String || value instanceof Boolean) {
            throw new InvalidWebhookException(label + ' must be an integer Unix timestamp');
        }
        try {
            Decimal seconds = Decimal.valueOf(String.valueOf(value));
            if (seconds < 0 || seconds != seconds.setScale(0)) {
                throw new InvalidWebhookException(label + ' must be a non-negative integer Unix timestamp');
            }
            return Datetime.newInstance(seconds.longValue() * 1000);
        } catch (Exception e) {
            throw new InvalidWebhookException(label + ' must be a valid non-negative integer Unix timestamp');
        }
    }

    private static String truncate(String value, Integer maxLength) {
        return value == null ? null : value.left(maxLength);
    }

    private class InvalidWebhookException extends Exception {}
}
