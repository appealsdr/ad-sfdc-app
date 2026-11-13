# Opportunity Quote Workspace

The `quoteBuilder` Lightning Web Component is the quote workspace on the Opportunity record page. It keeps quote products separate from Opportunity Products until a user explicitly synchronizes a selected quote.

## Opportunity view

The default view is a quote timeline. Each quote card shows:

- name, number, status, total, created date, expiration date, price book, and recipient;
- the Quote Line Items directly below the summary;
- **Generate/View PDF**, **Send quote**, **Edit**, and **Sync to Opportunity** actions.

The standard Quotes related-list component was removed from `Opportunity_Record_Page_Three_Column` because this workspace is the primary quote list.

## New and Edit Quote view

**New quote** and **Edit** open the product workspace inside the component. Users can search and filter the Opportunity price book, add products, change quantities and discounts, add client-facing line notes, set the expiration date, and edit quote notes. The editor also supports selecting a different price book, entering a negotiated unit price, and setting terms for recurring products.

Saving writes directly to `Quote` and `QuoteLineItem`. Unsynced quotes keep their products separate from Opportunity Products. Saving a synced quote also keeps its Opportunity product terms aligned.

Server-side rules:

- list prices come from the active Opportunity price book; negotiated unit prices belong to the quote and do not change the catalogue;
- products must be active in that price book;
- an explicit Discount % above 15% requires the `Quote_Discount_Override` custom permission; lowering the unit price does not require approval or display an approval warning;
- each quote supports at most 50 lines, quantities from 1–9999, and discounts from 0–100%;
- products whose price book entry has `Payment_type__c = 'Recurring'` require a quote-level term of 1–1200 whole months and may override the term per product;
- recurring lines without their own term inherit the quote term. That inheritance is preserved when editing a saved quote, so changing the quote term updates inherited lines while explicit line terms remain unchanged.

Changing an existing price book asks for confirmation before removing the current Opportunity products, stopping quote synchronization, and clearing draft products. Saved quotes and their line items are preserved. Quote notes, expiration date, and the recurring term stay in the editor. Cancelling leaves the Opportunity and draft unchanged. The server also requires an explicit confirmation flag before removing products, and rolls back the whole operation if a change fails. Selecting the current price book is a safe no-op for Opportunity products and synchronization.

The original catalogue price remains visible below each negotiated unit price. Each line is rounded to cents before calculating totals. Quote products also expose a nullable Deposit per unit: new products copy `PricebookEntry.Deposit__c` when configured, saved values are retained, blank uses the price-book default, and zero explicitly means no deposit. Recurring terms describe the agreement duration; they do not multiply the quote's line amounts.

## Sync, PDF, and Send

- **Sync to Opportunity** sets `Opportunity.SyncedQuoteId`. Salesforce then copies negotiated prices and discounts to Opportunity Products. The controller copies recurring terms using Salesforce's native quote-line/product links, including duplicate products.
- **Generate PDF** renders `QuoteBuilderPdf` and saves a `QuoteDocument`. **View PDF** previews the current quote through the Visualforce page, including edits made after a document was generated.
- The PDF shows each negotiated unit price with the original list price beneath it, the line discount as both a percentage and an amount, and the subtotal, discount, and net total. Recurring terms appear on the quote and the applicable product lines.
- **Send quote** asks for confirmation, generates a fresh PDF, emails it to `Quote.Email`, `Quote.Contact.Email`, or the primary Opportunity Contact Role, and changes the quote status to `Presented`.
- Sending requires a valid recipient email address.

Entering **Contract Sent**, including standard stage edits and the Send Invoice flow, requires a price book and at least one Opportunity product. A quote must be synchronized first if its products have not been added to the Opportunity. Contract creation copies negotiated prices, standard `Discount`, recurring terms, and the agreed per-unit `Deposit__c` onto contract line items. Payment creation uses the stored contract deposit and falls back to the price-book deposit only for legacy lines without a stored value.

`Sales_User` and `Sales_Team` grant access to the standard line-item discount fields and the new recurring-term fields. Standard discounts are reused to preserve Salesforce's native quote synchronization.

## Metadata

| Component                    | Purpose                                                                      |
| ---------------------------- | ---------------------------------------------------------------------------- |
| `QuoteBuilderController`     | Quote list, create/edit lines, sync, PDF, and send operations                |
| `QuoteBuilderControllerTest` | Quote separation, editing, validation, synchronization, PDF, and email tests |
| `quoteBuilder`               | Quote timeline and New/Edit Quote user interface                             |
| `QuoteBuilderPdf`            | Branded Visualforce PDF for quote delivery                                   |
| `Quote_Discount_Override`    | Allows approved users to exceed the 15% discount limit                       |
| `Sales_User`, `Sales_Team`   | Apex controller and Visualforce page access                                  |

## Verification

- 22 focused `quoteBuilder` Jest tests passed.
- 36 Apex tests passed across `QuoteBuilderControllerTest`, `OpportunityTriggerHandlerTest`, `OpportunityButtonActionTest`, and `OpportunityServiceContractServiceTest`.
- Scoped staging deployment `0AfVZ00000GSHxZ0AX` succeeded: 21 components, no component errors, test failures, or coverage warnings.
- Prettier, metadata XML checks, and `git diff --check` passed.

- Follow-up PDF deployments `0AfVZ00000GSI8r0AH` and `0AfVZ00000GSISD0A5` succeeded. The final deployed PDF was rendered from a saved staging quote for visual verification; legacy quotes without recurring terms are supported.
- Browser verification confirmed editable prices, original-price spacing, correct negotiated-price/discount totals, and the price-book chooser. Test edits were cancelled; the editor remains open with saved values.

## Changed components in this delivery

| API name                                                                                                                                                                                                   | Metadata type            | Change                                                                                                                         |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| [quoteBuilder](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/lwc/quoteBuilder/quoteBuilder.js)                                                               | LightningComponentBundle | Price-book selection, negotiated unit prices, spacing, rounded totals, recurring terms and inheritance.                        |
| [QuoteBuilderController](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/QuoteBuilderController.cls)                                                   | ApexClass                | Validates and saves prices/terms, preserves catalogue prices and approval limits, and copies terms through native quote links. |
| [QuoteBuilderControllerTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/QuoteBuilderControllerTest.cls)                                           | ApexClass                | Pricing, approval, duplicate-product sync, recurring-term and price-book regression tests.                                     |
| [OpportunityTriggerHandler](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/OpportunityTriggerHandler.cls)                                             | ApexClass                | Blocks entering Contract Sent without a price book and Opportunity products.                                                   |
| [OpportunityTriggerHandlerTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/OpportunityTriggerHandlerTest.cls)                                     | ApexClass                | Readiness errors, valid transitions, insert and bulk validation tests.                                                         |
| [OpportunityButtonAction](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/OpportunityButtonAction.cls)                                                 | ApexClass                | Applies readiness checks to send/resend actions and restores webhook flags after failures.                                     |
| [OpportunityButtonActionTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/OpportunityButtonActionTest.cls)                                         | ApexClass                | Send/resend readiness and flag restoration tests.                                                                              |
| [OpportunityServiceContractService](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/OpportunityServiceContractService.cls)                             | ApexClass                | Copies recurring terms alongside negotiated prices and discounts to contract lines.                                            |
| [OpportunityServiceContractServiceTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/OpportunityServiceContractServiceTest.cls)                     | ApexClass                | Verifies negotiated prices, discounts, net totals and term transfer.                                                           |
| [QuoteBuilderPdf](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/pages/QuoteBuilderPdf.page)                                                                  | ApexPage                 | Shows negotiated/original prices, line discounts, recurring terms and totals; handles absent legacy terms.                     |
| [Quote.Term_Months__c](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/objects/Quote/fields/Term_Months__c.field-meta.xml)                                     | CustomField              | Stores the recurring agreement term in months.                                                                                 |
| [QuoteLineItem.Term_Months__c](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/objects/QuoteLineItem/fields/Term_Months__c.field-meta.xml)                     | CustomField              | Stores the recurring agreement term in months.                                                                                 |
| [OpportunityLineItem.Term_Months__c](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/objects/OpportunityLineItem/fields/Term_Months__c.field-meta.xml)         | CustomField              | Stores the recurring agreement term in months.                                                                                 |
| [ContractLineItem.Term_Months__c](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/objects/ContractLineItem/fields/Term_Months__c.field-meta.xml)               | CustomField              | Stores the recurring agreement term in months.                                                                                 |
| [QuoteLineItem.Use_Quote_Term__c](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/objects/QuoteLineItem/fields/Use_Quote_Term__c.field-meta.xml)               | CustomField              | Preserves whether a recurring product inherits the quote term.                                                                 |
| [Sales_User](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/permissionsets/Sales_User.permissionset-meta.xml)                                                 | PermissionSet            | Grants access to standard discounts, recurring terms and recurring-product identification.                                     |
| [Sales_Team](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/permissionsets/Sales_Team.permissionset-meta.xml)                                                 | PermissionSet            | Grants access to standard discounts, recurring terms and recurring-product identification.                                     |
| [OpportunityLineItem-Opportunity Product Layout](</Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/default/layouts/OpportunityLineItem-Opportunity Product Layout.layout-meta.xml>) | Layout                   | Exposes recurring terms; Opportunity product layout also exposes its standard Discount field.                                  |
| [ContractLineItem-Contract Line Item Layout](</Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/default/layouts/ContractLineItem-Contract Line Item Layout.layout-meta.xml>)         | Layout                   | Exposes recurring terms; Opportunity product layout also exposes its standard Discount field.                                  |
| [Quote-Quote Layout](</Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/default/layouts/Quote-Quote Layout.layout-meta.xml>)                                                         | Layout                   | Exposes recurring terms; Opportunity product layout also exposes its standard Discount field.                                  |
| [QuoteLineItem-Quote Line Item Layout](</Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/default/layouts/QuoteLineItem-Quote Line Item Layout.layout-meta.xml>)                     | Layout                   | Exposes recurring terms; Opportunity product layout also exposes its standard Discount field.                                  |

Project-only file: this documentation. It has no deployment payload. Existing unrelated CSM/upsell changes were excluded from both scoped deployments.

## Price book confirmation follow-up

Switching an existing price book now opens a confirmation instead of blocking with the existing-products error. Confirming stops native quote synchronization before removing Opportunity products and changing the price book. Saved quotes and their line items are preserved. Cancelling keeps the Opportunity and draft unchanged. Duplicate clicks are guarded, invalid targets are rejected before cleanup, and all server mutations roll back together on failure.

Changed Salesforce components in this follow-up:

| API name                                                                                                                                                         | Metadata type            | Change                                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| [quoteBuilder](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/lwc/quoteBuilder/quoteBuilder.js)                     | LightningComponentBundle | Shows confirmation for existing-book changes, preserves cancellation, guards repeat clicks and refreshes record data after success. |
| [QuoteBuilderController](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/QuoteBuilderController.cls)         | ApexClass                | Requires explicit confirmation before resetting products/sync and changes the price book atomically.                                |
| [QuoteBuilderControllerTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/QuoteBuilderControllerTest.cls) | ApexClass                | Covers saved quote preservation, synced/unsynced products, missing confirmation, current-book no-op and invalid targets.            |

Verification: 26 focused quoteBuilder Jest tests and 20 QuoteBuilderControllerTest Apex tests passed. Formatting and git diff checks passed. Browser verification displayed the confirmation on the reported Opportunity; Cancel was selected. Staging deployment `0AfVZ00000GSJ050AH` succeeded for all 3 scoped components with no test failures or coverage warnings.

Project-only file: this documentation update; deployment is not applicable to it. The LWC Jest tests are part of the quoteBuilder source bundle and do not deploy as Salesforce metadata. Earlier unrelated project edits were preserved and excluded from this follow-up deployment.

## Deposit, Store and layout follow-up

- Removed the custom Contracts related list from the Opportunity Lightning record page and Opportunity layout. Service Contracts remain visible.
- The active `Store_Link_Opportunity_Account` before-save flow fills a blank Store Account from the selected Opportunity on creation or update. Explicitly selected Accounts are preserved. The old Store before-save flow has no active staging version.
- `Deposit__c` is a nullable Currency(18,2) per-unit amount on QuoteLineItem, OpportunityLineItem and ContractLineItem. It is exposed in all three line-item layouts and through Sales_User/Sales_Team permissions. Quote products default the value from their selected price-book entry, carry it through native quote sync and contract creation, and preserve it when catalogue deposits change. Explicit zero remains zero.
- Manual unit-price reductions can be saved without manager approval. The separate Discount % policy remains in place.

Store/layout deployment `0AfVZ00000GSK4D0AX` succeeded for four components and five Apex tests. Deposit/pricing deployment `0AfVZ00000GSK5p0AH` succeeded for 15 components and 30 Apex tests. All 31 focused quoteBuilder Jest tests passed, along with formatting, metadata XML and git diff checks. Neither deployment had component errors, test failures or coverage warnings.

Changed components in this follow-up:

| API name                                                                                                                                                                                                   | Metadata type            | Change                                                                                                                      |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| [Opportunity_Record_Page_Three_Column](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/flexipages/Opportunity_Record_Page_Three_Column.flexipage-meta.xml)     | FlexiPage                | Removes the custom Contracts card; keeps Service Contracts.                                                                 |
| [Opportunity-Opportunity Layout](</Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/layouts/Opportunity-Opportunity Layout.layout-meta.xml>)                     | Layout                   | Removes the custom Contracts related list.                                                                                  |
| [Store_Link_Opportunity_Account](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/store-management/flows/Store_Link_Opportunity_Account.flow-meta.xml)                              | Flow                     | Fills a blank Store Account from its Opportunity before save.                                                               |
| [StoreOpportunityAccountLinkTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/store-management/classes/StoreOpportunityAccountLinkTest.cls)                                    | ApexClass                | Creation, update, explicit Account preservation, missing Account and bulk flow regression tests.                            |
| [QuoteBuilderController](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/QuoteBuilderController.cls)                                                   | ApexClass                | Defaults and saves per-unit deposits and copies them through native sync; unit-price reductions no longer require approval. |
| [QuoteBuilderControllerTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/QuoteBuilderControllerTest.cls)                                           | ApexClass                | Deposit defaults, edited snapshots, zero/null, negative validation and unrestricted unit-price reduction regressions.       |
| [OpportunityServiceContractService](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/OpportunityServiceContractService.cls)                             | ApexClass                | Copies agreed Opportunity product deposits to contract lines.                                                               |
| [OpportunityServiceContractServiceTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/classes/OpportunityServiceContractServiceTest.cls)                     | ApexClass                | Checks deposit snapshots survive later catalogue changes.                                                                   |
| [ContractLineItemPaymentService](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/payments-and-pricing/classes/ContractLineItemPaymentService.cls)                                  | ApexClass                | Uses stored deposits, including zero, with a legacy catalogue fallback for null.                                            |
| [ContractLineItemPaymentServiceTest](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/payments-and-pricing/classes/ContractLineItemPaymentServiceTest.cls)                          | ApexClass                | Stored, legacy and zero deposit payment regressions.                                                                        |
| [quoteBuilder](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/lwc/quoteBuilder/quoteBuilder.js)                                                               | LightningComponentBundle | Adds deposit inputs and saved-line display; unit-price reductions no longer show an approval warning or block Save.         |
| [QuoteLineItem.Deposit__c](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/objects/QuoteLineItem/fields/Deposit__c.field-meta.xml)                             | CustomField              | Stores the nullable agreed deposit per unit.                                                                                |
| [OpportunityLineItem.Deposit__c](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/objects/OpportunityLineItem/fields/Deposit__c.field-meta.xml)                 | CustomField              | Stores the nullable agreed deposit per unit.                                                                                |
| [ContractLineItem.Deposit__c](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/objects/ContractLineItem/fields/Deposit__c.field-meta.xml)                       | CustomField              | Stores the nullable agreed deposit per unit.                                                                                |
| [Sales_User](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/permissionsets/Sales_User.permissionset-meta.xml)                                                 | PermissionSet            | Grants deposit field read/edit access and price-book deposit read access.                                                   |
| [Sales_Team](/Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/sales-and-contracts/permissionsets/Sales_Team.permissionset-meta.xml)                                                 | PermissionSet            | Grants deposit field read/edit access and price-book deposit read access.                                                   |
| [QuoteLineItem-Quote Line Item Layout](</Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/default/layouts/QuoteLineItem-Quote Line Item Layout.layout-meta.xml>)                     | Layout                   | Displays the Deposit field.                                                                                                 |
| [OpportunityLineItem-Opportunity Product Layout](</Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/default/layouts/OpportunityLineItem-Opportunity Product Layout.layout-meta.xml>) | Layout                   | Displays the Deposit field.                                                                                                 |
| [ContractLineItem-Contract Line Item Layout](</Users/andreipruzan/Documents/GitHub/ad-sfdc-app-staging/force-app/main/default/layouts/ContractLineItem-Contract Line Item Layout.layout-meta.xml>)         | Layout                   | Displays the Deposit field.                                                                                                 |

Project-only update: this documentation; no Salesforce deployment payload. Existing unrelated CSM and upsell edits were excluded from both scoped deployments.
