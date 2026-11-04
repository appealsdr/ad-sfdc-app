@IsTest
private class SubscriptionCancellationServiceTest {
    @TestSetup
    static void setupContract() {
        Account account = new Account(Name = 'Stripe cancellation account');
        insert account;
        insert new ServiceContract(
            Name = 'Stripe cancellation contract',
            AccountId = account.Id,
            StartDate = Date.newInstance(2025, 1, 1),
            EndDate = Date.newInstance(2027, 12, 31),
            Stripe_Subscription_Id__c = 'sub_cancel_001'
        );
    }

    @IsTest
    static void scheduledCancellationSetsExactCutoffAndInclusiveEndDate() {
        Integer logCount = [SELECT COUNT() FROM Application_Log__c];
        Map<String, Object> event = scheduledEvent('evt_scheduled');
        // canceled_at is the request date, not the end of service.
        subscription(event).put('canceled_at', epoch('2026-11-03 12:00:00'));

        Test.startTest();
        Map<String, Object> response = sendEvent(event);
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, JSON.serialize(response));
        System.assertEquals('success', response.get('status'));
        ServiceContract contract = savedContract();
        System.assertEquals('Scheduled', contract.Stripe_Cancellation_Status__c);
        System.assertEquals(Datetime.valueOfGmt('2026-12-01 00:00:00'), contract.Stripe_Active_Until__c);
        System.assertEquals(Date.newInstance(2026, 11, 30), contract.EndDate);
        System.assertEquals(Date.newInstance(2027, 12, 31), contract.Stripe_Pre_Cancel_End_Date__c);
        System.assertEquals('evt_scheduled', contract.Stripe_Cancel_Event_Id__c);
        System.assertEquals(Datetime.valueOfGmt('2026-11-03 12:00:00'), contract.Stripe_Cancel_Event_At__c);
        System.assertEquals(String.valueOf(contract.Id), response.get('serviceContractId'));
        System.assertEquals('sub_cancel_001', response.get('subscriptionId'));
        System.assertEquals('Scheduled', response.get('cancellationStatus'));
        System.assertEquals('2026-12-01T00:00:00Z', response.get('activeUntil'));
        System.assertEquals('2026-11-30', response.get('activeThroughDate'));
        System.assertEquals(logCount + 1, [SELECT COUNT() FROM Application_Log__c]);
    }

    @IsTest
    static void explicitCancelDateWinsAndReschedulePreservesOriginalEndDate() {
        Map<String, Object> event = scheduledEvent('evt_custom');
        subscription(event).put('cancel_at', epoch('2026-12-15 15:30:00'));
        subscription(event).put('cancel_at_period_end', false);
        sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(Date.newInstance(2026, 12, 15), savedContract().EndDate);
        System.assertEquals(Datetime.valueOfGmt('2026-12-15 15:30:00'), savedContract().Stripe_Active_Until__c);

        event.put('id', 'evt_reschedule');
        event.put('created', epoch('2026-11-04 12:00:00'));
        subscription(event).put('cancel_at', epoch('2026-12-20 00:00:00'));
        sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);
        ServiceContract contract = savedContract();
        System.assertEquals(Date.newInstance(2026, 12, 19), contract.EndDate);
        System.assertEquals(Date.newInstance(2027, 12, 31), contract.Stripe_Pre_Cancel_End_Date__c);
    }

    @IsTest
    static void modernItemPeriodsWorkAndAmbiguousPeriodsAreRejected() {
        Map<String, Object> event = scheduledEvent('evt_modern');
        subscription(event).remove('current_period_end');
        subscription(event).put('items', new Map<String, Object>{
            'has_more' => false,
            'data' => new List<Object>{
                new Map<String, Object>{'current_period_end' => epoch('2026-12-01 00:00:00')},
                new Map<String, Object>{'current_period_end' => epoch('2026-12-01 00:00:00')}
            }
        });
        sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(Date.newInstance(2026, 11, 30), savedContract().EndDate);

        event.put('id', 'evt_mixed');
        event.put('created', epoch('2026-11-04 12:00:00'));
        Map<String, Object> items = (Map<String, Object>) subscription(event).get('items');
        items.put('data', new List<Object>{
            new Map<String, Object>{'current_period_end' => epoch('2026-12-01 00:00:00')},
            new Map<String, Object>{'current_period_end' => epoch('2027-01-01 00:00:00')}
        });
        assertError(400, sendEvent(event));
        System.assertEquals('evt_modern', savedContract().Stripe_Cancel_Event_Id__c);

        items.put('has_more', true);
        assertError(400, sendEvent(event));
        items.put('has_more', false);
        items.put('data', new List<Object>());
        assertError(400, sendEvent(event));
    }

    @IsTest
    static void effectiveCancellationUsesEndedAtAndCannotReopen() {
        sendEvent(scheduledEvent('evt_schedule'));
        Map<String, Object> event = endedEvent('evt_ended');
        subscription(event).put('cancel_at_period_end', true);
        subscription(event).put('canceled_at', epoch('2026-11-03 12:00:00'));
        Map<String, Object> response = sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Canceled', response.get('cancellationStatus'));
        ServiceContract contract = savedContract();
        System.assertEquals('Canceled', contract.Stripe_Cancellation_Status__c);
        System.assertEquals(Datetime.valueOfGmt('2026-11-15 14:00:00'), contract.Stripe_Active_Until__c);
        System.assertEquals(Date.newInstance(2026, 11, 15), contract.EndDate);

        Map<String, Object> reopen = scheduledEvent('evt_cannot_reopen');
        reopen.put('created', epoch('2026-11-16 12:00:00'));
        subscription(reopen).put('cancel_at_period_end', false);
        System.assertEquals('ignored', sendEvent(reopen).get('status'));
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Canceled', savedContract().Stripe_Cancellation_Status__c);
        System.assertEquals('evt_ended', savedContract().Stripe_Cancel_Event_Id__c);
    }

    @IsTest
    static void canceledSubscriptionUpdateRecordsTerminalState() {
        Map<String, Object> event = endedEvent('evt_update_canceled');
        event.put('type', 'customer.subscription.updated');
        sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Canceled', savedContract().Stripe_Cancellation_Status__c);
    }

    @IsTest
    static void withdrawingCancellationRestoresExistingAndOpenEndedTerms() {
        sendEvent(scheduledEvent('evt_schedule'));
        Map<String, Object> withdraw = scheduledEvent('evt_withdraw');
        withdraw.put('created', epoch('2026-11-04 12:00:00'));
        subscription(withdraw).put('cancel_at_period_end', false);
        Map<String, Object> response = sendEvent(withdraw);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('None', response.get('cancellationStatus'));
        ServiceContract contract = savedContract();
        System.assertEquals(Date.newInstance(2027, 12, 31), contract.EndDate);
        System.assertEquals(null, contract.Stripe_Active_Until__c);
        System.assertEquals(null, contract.Stripe_Pre_Cancel_End_Date__c);

        contract.EndDate = null;
        update contract;
        Map<String, Object> scheduleAgain = scheduledEvent('evt_schedule_open');
        scheduleAgain.put('created', epoch('2026-11-05 12:00:00'));
        sendEvent(scheduleAgain);
        System.assertEquals(200, RestContext.response.statusCode);
        withdraw.put('id', 'evt_withdraw_open');
        withdraw.put('created', epoch('2026-11-06 12:00:00'));
        sendEvent(withdraw);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(null, savedContract().EndDate);
    }

    @IsTest
    static void duplicateStaleAndConflictingEventsDoNotOverwriteDates() {
        Map<String, Object> original = scheduledEvent('evt_first');
        sendEvent(original);
        subscription(original).put('current_period_end', epoch('2027-01-01 00:00:00'));
        sendEvent(original);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(Date.newInstance(2026, 11, 30), savedContract().EndDate);

        original.put('id', 'evt_old');
        original.put('created', epoch('2026-11-02 12:00:00'));
        System.assertEquals('ignored', sendEvent(original).get('status'));
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('evt_first', savedContract().Stripe_Cancel_Event_Id__c);

        original.put('id', 'evt_same_second_conflict');
        original.put('created', epoch('2026-11-03 12:00:00'));
        assertError(409, sendEvent(original));
        System.assertEquals(Date.newInstance(2026, 11, 30), savedContract().EndDate);

        // A terminal cancellation can safely supersede a schedule in the same second.
        Map<String, Object> terminal = endedEvent('evt_same_second_ended');
        terminal.put('created', epoch('2026-11-03 12:00:00'));
        sendEvent(terminal);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Canceled', savedContract().Stripe_Cancellation_Status__c);
    }

    @IsTest
    static void terminalEventOverridesOlderTimestampWithoutLoweringWatermark() {
        sendEvent(scheduledEvent('evt_newer_schedule'));
        Map<String, Object> terminal = endedEvent('evt_older_terminal');
        terminal.put('created', epoch('2026-11-02 12:00:00'));
        sendEvent(terminal);

        System.assertEquals(200, RestContext.response.statusCode);
        ServiceContract contract = savedContract();
        System.assertEquals('Canceled', contract.Stripe_Cancellation_Status__c);
        System.assertEquals(Datetime.valueOfGmt('2026-11-15 14:00:00'), contract.Stripe_Active_Until__c);
        System.assertEquals('evt_older_terminal', contract.Stripe_Cancel_Event_Id__c);
        System.assertEquals(Datetime.valueOfGmt('2026-11-03 12:00:00'), contract.Stripe_Cancel_Event_At__c);
    }

    @IsTest
    static void unrelatedUpdatesKeepContractTermsAndOtherEventsAreIgnored() {
        Map<String, Object> event = scheduledEvent('evt_unrelated');
        subscription(event).put('cancel_at_period_end', false);
        sendEvent(event);
        System.assertEquals(200, RestContext.response.statusCode);
        ServiceContract contract = savedContract();
        System.assertEquals(Date.newInstance(2027, 12, 31), contract.EndDate);
        System.assertEquals(null, contract.Stripe_Active_Until__c);
        System.assertEquals('None', contract.Stripe_Cancellation_Status__c);

        event.put('id', 'evt_unsupported');
        event.put('type', 'customer.subscription.created');
        System.assertEquals('ignored', sendEvent(event).get('status'));
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('evt_unrelated', savedContract().Stripe_Cancel_Event_Id__c);
    }

    @IsTest
    static void rejectsInvalidRequestsWithoutChangingTheContract() {
        for (String body : new List<String>{'', '{', 'null', '[]'}) {
            assertError(400, sendBody(body));
        }
        for (String missing : new List<String>{'id', 'type', 'created', 'subscription_id', 'status', 'object'}) {
            Map<String, Object> event = scheduledEvent('evt_missing');
            if (missing == 'id' || missing == 'type' || missing == 'created') event.remove(missing);
            else subscription(event).remove(missing == 'subscription_id' ? 'id' : missing);
            assertError(400, sendEvent(event));
        }
        Map<String, Object> event = scheduledEvent('evt_missing_end');
        subscription(event).remove('current_period_end');
        assertError(400, sendEvent(event));
        event = endedEvent('evt_missing_ended_at');
        subscription(event).remove('ended_at');
        assertError(400, sendEvent(event));
        event = scheduledEvent('evt_bad_created');
        event.put('created', 'not-a-timestamp');
        assertError(400, sendEvent(event));
        event = scheduledEvent('evt_bad_boolean');
        subscription(event).put('cancel_at_period_end', 'true');
        assertError(400, sendEvent(event));
        System.assertEquals(Date.newInstance(2027, 12, 31), savedContract().EndDate);
        System.assertEquals(null, savedContract().Stripe_Cancel_Event_Id__c);
    }

    @IsTest
    static void missingContractAndCutoffBeforeContractStartReturnErrorsAndLog() {
        Integer logCount = [SELECT COUNT() FROM Application_Log__c];
        Map<String, Object> unknown = scheduledEvent('evt_unknown');
        subscription(unknown).put('id', 'sub_unknown');
        assertError(404, sendEvent(unknown));
        Application_Log__c log = [
            SELECT Body__c, Response__c, Error__c FROM Application_Log__c
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(log.Body__c.contains('evt_unknown'));
        System.assert(log.Response__c.contains('error'));
        System.assert(!String.isBlank(log.Error__c));

        Map<String, Object> beforeStart = endedEvent('evt_before_start');
        subscription(beforeStart).put('ended_at', epoch('2024-12-01 00:00:00'));
        assertError(409, sendEvent(beforeStart));
        System.assertEquals(Date.newInstance(2027, 12, 31), savedContract().EndDate);
        System.assertEquals(null, savedContract().Stripe_Cancel_Event_Id__c);
        System.assertEquals(logCount + 2, [SELECT COUNT() FROM Application_Log__c]);
    }

    private static Map<String, Object> scheduledEvent(String eventId) {
        return new Map<String, Object>{
            'id' => eventId,
            'type' => 'customer.subscription.updated',
            'created' => epoch('2026-11-03 12:00:00'),
            'data' => new Map<String, Object>{
                'object' => new Map<String, Object>{
                    'id' => 'sub_cancel_001',
                    'object' => 'subscription',
                    'status' => 'active',
                    'cancel_at_period_end' => true,
                    'cancel_at' => null,
                    'current_period_end' => epoch('2026-12-01 00:00:00')
                }
            }
        };
    }

    private static Map<String, Object> endedEvent(String eventId) {
        Map<String, Object> event = scheduledEvent(eventId);
        event.put('type', 'customer.subscription.deleted');
        event.put('created', epoch('2026-11-15 14:00:00'));
        subscription(event).put('status', 'canceled');
        subscription(event).put('cancel_at_period_end', false);
        subscription(event).put('ended_at', epoch('2026-11-15 14:00:00'));
        subscription(event).put('canceled_at', epoch('2026-11-15 14:00:00'));
        return event;
    }

    private static Map<String, Object> subscription(Map<String, Object> event) {
        return (Map<String, Object>) ((Map<String, Object>) event.get('data')).get('object');
    }

    private static ServiceContract savedContract() {
        return [
            SELECT Id, EndDate, Stripe_Cancellation_Status__c, Stripe_Active_Until__c,
                Stripe_Cancel_Event_Id__c, Stripe_Cancel_Event_At__c, Stripe_Pre_Cancel_End_Date__c
            FROM ServiceContract WHERE Stripe_Subscription_Id__c = 'sub_cancel_001'
        ];
    }

    private static Long epoch(String utcDateTime) {
        return Datetime.valueOfGmt(utcDateTime).getTime() / 1000;
    }

    private static void assertError(Integer statusCode, Map<String, Object> response) {
        System.assertEquals(statusCode, RestContext.response.statusCode, JSON.serialize(response));
        System.assertEquals('error', response.get('status'));
    }

    private static Map<String, Object> sendEvent(Map<String, Object> event) {
        return sendBody(JSON.serialize(event));
    }

    private static Map<String, Object> sendBody(String body) {
        RestContext.request = new RestRequest();
        RestContext.request.httpMethod = 'POST';
        RestContext.request.requestUri = '/services/apexrest/Subscription/cancel';
        RestContext.request.requestBody = Blob.valueOf(body);
        RestContext.response = new RestResponse();
        SubscriptionCancellationService.receiveCancellation();
        System.assertNotEquals(null, RestContext.response.responseBody, 'Response must contain JSON');
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }
}
