# Stripe subscription payments

`PaymentWebhookService` receives raw Stripe `invoice.payment_succeeded` events at
`POST /services/apexrest/Payment/create`. It creates a `Paid` / `Subscription`
`Payment__c` linked through `Service_Contract__c` to the contract whose
`Stripe_Subscription_Id__c` matches the invoice subscription ID. The previous
`Payments` wrapper implementation remains commented out in the same class.

## Integration setup

1. Deploy `PaymentWebhookService`, `PaymentWebhookServiceTest`, and
   `ServiceContract.Stripe_Subscription_Id__c` together. The subscription field is
   new because it was absent from the staging org schema; existing contract
   Stripe fields contain payment/charge information rather than a subscription ID.
2. Populate `Stripe_Subscription_Id__c` with the actual Stripe `sub_...` ID when
   the subscription is created, and backfill existing subscription contracts.
   It is a unique, case-sensitive external ID: one subscription maps to one
   Service Contract. Grant field access to the integration that writes it.
3. Configure the Stripe receiver to subscribe to `invoice.payment_succeeded`,
   verify the `Stripe-Signature` header against the original request bytes, and
   forward the unchanged event JSON to Salesforce with its existing OAuth
   integration credentials. The Salesforce integration user needs class access
   and record visibility to the matching Service Contract and recorded payments.
   This Apex change retains the authenticated endpoint; it does not publish a
   public Salesforce Site or configure Stripe delivery.

Stripe emits [`invoice.payment_succeeded`](https://docs.stripe.com/api/events/types)
for successful invoice payment attempts. `invoice.paid` is intentionally ignored
because it can also represent invoices marked paid outside Stripe.

Example forwarded body:

```json
{
  "id": "evt_example",
  "type": "invoice.payment_succeeded",
  "created": 1793707200,
  "data": {
    "object": {
      "id": "in_example",
      "object": "invoice",
      "parent": {
        "type": "subscription_details",
        "subscription_details": {
          "subscription": "sub_example"
        }
      },
      "amount_paid": 24900,
      "currency": "usd",
      "status": "paid",
      "description": "Monthly subscription",
      "status_transitions": {
        "paid_at": 1793707200
      }
    }
  }
}
```

The example creates a USD 249.00 payment on the contract with subscription
`sub_example`. Older Stripe payloads with top-level `subscription` and
`payment_intent` are supported, including expanded objects. Modern
`parent.subscription_details.subscription` and paid `payments.data` payment
intents are supported too. A payment intent is optional; no Stripe API callout
is needed. `Order_Ref__c` stores the Stripe invoice ID, and `PaidAt__c` stores UTC
ISO text using the invoice payment timestamp (falling back to event creation).

## Delivery behavior

- A contract lock serializes concurrent deliveries for the same subscription.
  Retrying an event or sending another event for the same contract/invoice
  returns the existing payment without changing it. A new billing invoice
  creates a separate payment.
- This flow records fully paid subscription invoices. Unsupported events,
  invoices without a subscription, unpaid/partially paid invoices, explicit
  out-of-band payments, and zero-amount invoices return HTTP 200 with
  `status: ignored` and create no payment.
- Invalid bodies or required values return HTTP 400. An unmatched subscription
  returns HTTP 404, so the sender can retry after the contract has been populated.
  A conflicting event ID returns HTTP 409. Unexpected database failures return
  HTTP 500. Do not acknowledge a failed Salesforce forwarding request as a
  successful Stripe delivery; retry it.
- Amounts follow [Stripe's currency minor-unit rules](https://docs.stripe.com/currencies),
  including JPY, ISK, and UGX. Values that cannot be represented exactly in the
  existing Salesforce amount field (18 digits, 2 decimals) are rejected instead
  of rounded.
- Every delivery attempts to write its request, response, and error to the
  existing `Application_Log__c`. Contract payments leave `Case__c` unset and do
  not enter case-specific payment automation.

## Validation

Run a validation without saving changes to Salesforce:

```sh
sf project deploy start --dry-run \
  --source-dir force-app/main/payments-and-pricing/classes/PaymentWebhookService.cls \
  --source-dir force-app/main/payments-and-pricing/classes/PaymentWebhookServiceTest.cls \
  --source-dir force-app/main/sales-and-contracts/objects/ServiceContract/fields/Stripe_Subscription_Id__c.field-meta.xml \
  --test-level RunSpecifiedTests --tests PaymentWebhookServiceTest \
  --target-org ad-sfdc-app-staging
```
