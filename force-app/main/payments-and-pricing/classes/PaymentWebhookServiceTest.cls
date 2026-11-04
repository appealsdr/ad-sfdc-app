@IsTest
private class PaymentWebhookServiceTest {
    @TestSetup
    static void setupContract() {
        Account account = new Account(Name = 'Stripe subscription account');
        insert account;
        insert new ServiceContract(
            Name = 'Stripe subscription contract',
            AccountId = account.Id,
            StartDate = Date.today(),
            Stripe_Subscription_Id__c = 'sub_contract_001'
        );
    }

    @IsTest
    static void createsPaidPaymentForMatchingContract() {
        Map<String, Object> event = paymentEvent('evt_first', 'in_first');
        Integer logCount = [SELECT COUNT() FROM Application_Log__c];

        Test.startTest();
        Map<String, Object> response = sendEvent(event);
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, JSON.serialize(response));
        System.assertEquals('success', response.get('status'));
        ServiceContract contract = [SELECT Id FROM ServiceContract LIMIT 1];
        Payment__c payment = [
            SELECT Id, Service_Contract__c, Amount__c, Status__c, Payment_Type__c,
                CurrencyIsoCode__c, Stripe_EventId__c, Stripe_Payment_Intent_Id__c,
                Order_Ref__c, PaidAt__c, Amount_Applied__c, Description__c, Case__c
            FROM Payment__c
        ];
        System.assertEquals(contract.Id, payment.Service_Contract__c);
        System.assertEquals(123.45, payment.Amount__c);
        System.assertEquals('Paid', payment.Status__c);
        System.assertEquals('Subscription', payment.Payment_Type__c);
        System.assertEquals('USD', payment.CurrencyIsoCode__c);
        System.assertEquals('evt_first', payment.Stripe_EventId__c);
        System.assertEquals('pi_first', payment.Stripe_Payment_Intent_Id__c);
        System.assertEquals('in_first', payment.Order_Ref__c);
        System.assertEquals('2025-01-01T00:00:00Z', payment.PaidAt__c);
        System.assertEquals(123.45, Decimal.valueOf(payment.Amount_Applied__c));
        System.assertEquals('Monthly subscription', payment.Description__c);
        System.assertEquals(null, payment.Case__c);
        System.assertEquals(String.valueOf(payment.Id), response.get('paymentId'));
        System.assertEquals(logCount + 1, [SELECT COUNT() FROM Application_Log__c]);
    }

    @IsTest
    static void retriesAndRepeatedInvoiceDoNotDuplicateOrOverwrite() {
        Map<String, Object> event = paymentEvent('evt_original', 'in_original');
        System.assertEquals('success', sendEvent(event).get('status'));
        System.assertEquals(200, RestContext.response.statusCode);

        // A retry must not overwrite an already-recorded payment with altered data.
        invoice(event).put('amount_paid', 99999);
        sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);

        // Independently-created Stripe events can still refer to the same invoice.
        event.put('id', 'evt_repeated_invoice');
        sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Payment__c]);
        Payment__c recorded = [SELECT Amount__c, Stripe_EventId__c FROM Payment__c];
        System.assertEquals(123.45, recorded.Amount__c);
        System.assertEquals('evt_original', recorded.Stripe_EventId__c);

        // The next billing period is a distinct payment for the same contract.
        Map<String, Object> renewal = paymentEvent('evt_renewal', 'in_renewal');
        invoice(renewal).put('payment_intent', 'pi_renewal');
        sendEvent(renewal);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(2, [SELECT COUNT() FROM Payment__c]);
    }

    @IsTest
    static void supportsModernInvoiceAndOptionalPaymentIntent() {
        Map<String, Object> event = paymentEvent('evt_modern', 'in_modern');
        Map<String, Object> data = invoice(event);
        data.remove('subscription');
        data.remove('payment_intent');
        data.put('parent', new Map<String, Object>{
            'type' => 'subscription_details',
            'subscription_details' => new Map<String, Object>{
                'subscription' => new Map<String, Object>{ 'id' => 'sub_contract_001' }
            }
        });
        data.put('payments', new Map<String, Object>{
            'data' => new List<Object>{
                new Map<String, Object>{
                    'status' => 'paid',
                    'payment' => new Map<String, Object>{
                        'type' => 'payment_intent',
                        'payment_intent' => new Map<String, Object>{ 'id' => 'pi_modern' }
                    }
                }
            }
        });
        sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('pi_modern', [
            SELECT Stripe_Payment_Intent_Id__c FROM Payment__c WHERE Order_Ref__c = 'in_modern'
        ].Stripe_Payment_Intent_Id__c);

        Map<String, Object> noIntent = paymentEvent('evt_no_intent', 'in_no_intent');
        invoice(noIntent).remove('payment_intent');
        invoice(noIntent).put('subscription', new Map<String, Object>{ 'id' => 'sub_contract_001' });
        invoice(noIntent).remove('status_transitions');
        sendEvent(noIntent);
        System.assertEquals(200, RestContext.response.statusCode);
        Payment__c payment = [
            SELECT Stripe_Payment_Intent_Id__c, PaidAt__c FROM Payment__c
            WHERE Order_Ref__c = 'in_no_intent'
        ];
        System.assertEquals(null, payment.Stripe_Payment_Intent_Id__c);
        System.assertEquals('2025-01-01T00:01:00Z', payment.PaidAt__c);
    }

    @IsTest
    static void convertsCurrencyMinorUnitsWithoutLosingPrecision() {
        for (String currencyCode : new List<String>{ 'jpy', 'ugx', 'isk', 'kwd' }) {
            Map<String, Object> event = paymentEvent('evt_' + currencyCode, 'in_' + currencyCode);
            invoice(event).put('currency', currencyCode);
            invoice(event).put('amount_paid', currencyCode == 'kwd' ? 123450 : 12300);
            sendEvent(event);
            System.assertEquals(200, RestContext.response.statusCode, currencyCode);
        }
        Map<String, Decimal> amounts = new Map<String, Decimal>();
        for (Payment__c payment : [SELECT CurrencyIsoCode__c, Amount__c FROM Payment__c]) {
            amounts.put(payment.CurrencyIsoCode__c, payment.Amount__c);
        }
        System.assertEquals(12300, amounts.get('JPY'));
        System.assertEquals(123, amounts.get('UGX'));
        System.assertEquals(123, amounts.get('ISK'));
        System.assertEquals(123.45, amounts.get('KWD'));

        Map<String, Object> fractional = paymentEvent('evt_fraction', 'in_fraction');
        invoice(fractional).put('currency', 'kwd');
        invoice(fractional).put('amount_paid', 123451);
        System.assertEquals('error', sendEvent(fractional).get('status'));
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(4, [SELECT COUNT() FROM Payment__c]);
    }

    @IsTest
    static void ignoresEventsThatDoNotRepresentReceivedSubscriptionPayments() {
        Integer logCount = [SELECT COUNT() FROM Application_Log__c];
        for (String reason : new List<String>{ 'event_type', 'invoice_paid', 'one_off', 'unpaid', 'out_of_band', 'zero' }) {
            Map<String, Object> event = paymentEvent('evt_' + reason, 'in_' + reason);
            if (reason == 'event_type') event.put('type', 'invoice.payment_failed');
            if (reason == 'invoice_paid') event.put('type', 'invoice.paid');
            if (reason == 'one_off') invoice(event).remove('subscription');
            if (reason == 'unpaid') invoice(event).put('status', 'open');
            if (reason == 'out_of_band') invoice(event).put('paid_out_of_band', true);
            if (reason == 'zero') invoice(event).put('amount_paid', 0);
            Map<String, Object> response = sendEvent(event);
            System.assertEquals(200, RestContext.response.statusCode, reason);
            System.assertEquals('ignored', response.get('status'), reason);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Payment__c]);
        System.assertEquals(logCount + 6, [SELECT COUNT() FROM Application_Log__c]);
    }

    @IsTest
    static void rejectsMalformedAndIncompleteRequests() {
        for (String body : new List<String>{ '', '{', 'null', '[]' }) {
            System.assertEquals('error', sendBody(body).get('status'), body);
            System.assertEquals(400, RestContext.response.statusCode, body);
        }
        for (String field : new List<String>{ 'id', 'type', 'invoice_id', 'currency', 'amount_paid' }) {
            Map<String, Object> event = paymentEvent('evt_invalid', 'in_invalid');
            if (field == 'id' || field == 'type') event.remove(field);
            else invoice(event).remove(field == 'invoice_id' ? 'id' : field);
            System.assertEquals('error', sendEvent(event).get('status'), field);
            System.assertEquals(400, RestContext.response.statusCode, field);
        }
        Map<String, Object> invalidAmount = paymentEvent('evt_bad_amount', 'in_bad_amount');
        invoice(invalidAmount).put('amount_paid', 'not-a-number');
        System.assertEquals('error', sendEvent(invalidAmount).get('status'));
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Payment__c]);
    }

    @IsTest
    static void unmatchedSubscriptionReturnsErrorAndLogsRequest() {
        Map<String, Object> event = paymentEvent('evt_unknown', 'in_unknown');
        invoice(event).put('subscription', 'sub_unknown');
        Integer logCount = [SELECT COUNT() FROM Application_Log__c];
        Map<String, Object> response = sendEvent(event);

        System.assertEquals(404, RestContext.response.statusCode);
        System.assertEquals('error', response.get('status'));
        System.assertEquals(0, [SELECT COUNT() FROM Payment__c]);
        System.assertEquals(logCount + 1, [SELECT COUNT() FROM Application_Log__c]);
        Application_Log__c log = [
            SELECT Body__c, Response__c, Error__c FROM Application_Log__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(log.Body__c.contains('evt_unknown'));
        System.assert(log.Response__c.contains('error'));
        System.assert(!String.isBlank(log.Error__c));
    }

    @IsTest
    static void conflictingEventCannotLinkPaymentToAnotherContract() {
        sendEvent(paymentEvent('evt_conflict', 'in_original'));
        System.assertEquals(200, RestContext.response.statusCode);
        ServiceContract original = [SELECT Id, AccountId FROM ServiceContract LIMIT 1];
        insert new ServiceContract(
            Name = 'Other Stripe subscription',
            AccountId = original.AccountId,
            StartDate = Date.today(),
            Stripe_Subscription_Id__c = 'sub_other'
        );
        Map<String, Object> event = paymentEvent('evt_conflict', 'in_other');
        invoice(event).put('subscription', 'sub_other');

        System.assertEquals('error', sendEvent(event).get('status'));
        System.assertEquals(409, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Payment__c]);
        System.assertEquals(original.Id, [SELECT Service_Contract__c FROM Payment__c].Service_Contract__c);
    }

    private static Map<String, Object> paymentEvent(String eventId, String invoiceId) {
        return new Map<String, Object>{
            'id' => eventId,
            'type' => 'invoice.payment_succeeded',
            'created' => 1735689660,
            'data' => new Map<String, Object>{
                'object' => new Map<String, Object>{
                    'id' => invoiceId,
                    'object' => 'invoice',
                    'subscription' => 'sub_contract_001',
                    'payment_intent' => 'pi_first',
                    'amount_paid' => 12345,
                    'currency' => 'usd',
                    'status' => 'paid',
                    'description' => 'Monthly subscription',
                    'status_transitions' => new Map<String, Object>{ 'paid_at' => 1735689600 }
                }
            }
        };
    }

    private static Map<String, Object> invoice(Map<String, Object> event) {
        return (Map<String, Object>) ((Map<String, Object>) event.get('data')).get('object');
    }

    private static Map<String, Object> sendEvent(Map<String, Object> event) {
        return sendBody(JSON.serialize(event));
    }

    private static Map<String, Object> sendBody(String body) {
        RestContext.request = new RestRequest();
        RestContext.request.httpMethod = 'POST';
        RestContext.request.requestUri = '/services/apexrest/Payment/create';
        RestContext.request.requestBody = Blob.valueOf(body);
        RestContext.response = new RestResponse();
        return (Map<String, Object>) JSON.deserializeUntyped(PaymentWebhookService.upsertPayment());
    }
}
