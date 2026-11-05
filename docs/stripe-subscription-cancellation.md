# Stripe subscription cancellation

`SubscriptionCancellationService` accepts raw Stripe subscription snapshot
events at `POST /services/apexrest/Subscription/cancel`. It matches the Service
Contract by `Stripe_Subscription_Id__c`, records cancellation state and the exact
service cutoff, and updates the existing contract `EndDate`.

## Events and contract dates

Subscribe the Stripe receiver to these
[cancellation events](https://docs.stripe.com/billing/subscriptions/cancel):

- `customer.subscription.updated`: scheduling, rescheduling, or withdrawing a
  cancellation. A non-null `cancel_at` or `cancel_at_period_end: true` schedules
  cancellation while service continues until the supplied cutoff.
- `customer.subscription.deleted`: effective cancellation, including immediate
  cancellation. An update whose subscription status is `canceled` is also accepted.

For a scheduled cancellation, the cutoff comes from `cancel_at` first, then
legacy `current_period_end`. For modern item-level periods, the complete
`items.data` list must have one shared `current_period_end`; mixed or incomplete
periods require an explicit `cancel_at` instead of guessing a service end.

Effective cancellation uses `ended_at`. Stripe's
[`canceled_at`](https://docs.stripe.com/api/subscriptions/object) can identify
the earlier cancellation request rather than the time service actually ends,
so it is never used as the cutoff.

The exact cutoff is stored in `Stripe_Active_Until__c` as an exclusive UTC instant.
`EndDate` is the last inclusive UTC service date: a cutoff of
`2026-12-01T00:00:00Z` produces an End Date of November 30, 2026. A cutoff at
15:30 UTC produces the same calendar date, with the exact time retained in the
custom field. Consumers that enforce access to the second must use
`Stripe_Active_Until__c`. Salesforce's standard `Status` is read-only and remains
derived by Salesforce; `Stripe_Cancellation_Status__c` records `Scheduled`,
`Canceled`, or `None` explicitly.

When a pending cancellation is withdrawn, the service restores the End Date
saved before scheduling, including an originally blank End Date. While
cancellation is scheduled, the webhook owns End Date; withdrawal restores that
saved value even if someone edited End Date in the meantime. A subscription
already recorded as canceled cannot be reopened by a later active snapshot.

## Example request

This schedules service to end at midnight UTC on December 1, 2026:

```json
{
  "id": "evt_subscription_cancel_scheduled",
  "type": "customer.subscription.updated",
  "created": 1793707200,
  "data": {
    "object": {
      "id": "sub_example",
      "object": "subscription",
      "status": "active",
      "cancel_at_period_end": true,
      "cancel_at": 1796083200,
      "canceled_at": 1793707200
    }
  }
}
```

The HTTP 200 JSON response includes `serviceContractId`, `subscriptionId`,
`cancellationStatus: "Scheduled"`, `activeUntil: "2026-12-01T00:00:00Z"`, and
`activeThroughDate: "2026-11-30"`. An effective cancellation body uses type
`customer.subscription.deleted`, status `canceled`, and its actual `ended_at`.
Every supported event requires an ID, numeric integer Unix `created` timestamp,
and a subscription object with ID and status. Nonterminal updates must include
a boolean `cancel_at_period_end`.

## Deployment and forwarding

Deploy both new Apex classes and all six fields in the local Service Contract
metadata folder. The subscription ID field is shared with the payment webhook.
Populate it for each subscription contract before forwarding events. Grant the
OAuth integration user class access and visibility to the matching contract;
grant the intended users field access to inspect the new Stripe fields.

Use the same authenticated forwarding arrangement as the
[payment webhook](stripe-subscription-payments.md). The public receiver verifies
`Stripe-Signature` against the original request body and forwards events using
Salesforce OAuth credentials. This Apex service does not publish a public Site
or configure Stripe delivery.

Stripe [does not guarantee event ordering](https://docs.stripe.com/webhooks#event-ordering),
and its creation timestamps have only second precision. The receiver must
reconcile against the current Stripe subscription when delivery order is
uncertain, and serialize changes for a subscription. The Apex service locks the
contract, recognizes a repeat of its last event ID, ignores older nonterminal
snapshots, and returns HTTP 409 for conflicting same-second snapshots. A
terminal cancellation can supersede an earlier nonterminal state even when
delivered with an older timestamp. These guards do not establish a complete
Stripe event order. A same-second conflict needs reconciliation/manual repair
against Stripe; retrying that identical conflict alone will not resolve it.

Unsupported event types return HTTP 200 with `status: ignored`. Malformed or
incomplete input returns HTTP 400. A missing contract returns HTTP 404. A cutoff
before the contract Start Date returns HTTP 409 rather than writing an invalid
contract date. Database errors return HTTP 500. The service attempts to log
every request, response, and error in `Application_Log__c`. The receiver should
retain and retry failed Salesforce deliveries rather than treating them as
successfully synchronized.

Validate without saving changes to the org:

```sh
sf project deploy start --dry-run \
  --source-dir force-app/main/payments-and-pricing/classes/SubscriptionCancellationService.cls \
  --source-dir force-app/main/payments-and-pricing/classes/SubscriptionCancellationServiceTest.cls \
  --source-dir force-app/main/sales-and-contracts/objects/ServiceContract \
  --test-level RunSpecifiedTests --tests SubscriptionCancellationServiceTest \
  --target-org ad-sfdc-app-staging
```
