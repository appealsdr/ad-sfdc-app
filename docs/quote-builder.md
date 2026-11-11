# Opportunity Quote Workspace

The `quoteBuilder` Lightning Web Component is the quote workspace on the Opportunity record page. It keeps quote products separate from Opportunity Products until a user explicitly synchronizes a selected quote.

## Opportunity view

The default view is a quote timeline. Each quote card shows:

- name, number, status, total, created date, expiration date, price book, and recipient;
- the Quote Line Items directly below the summary;
- **Generate/View PDF**, **Send quote**, **Edit**, and **Sync to Opportunity** actions.

The standard Quotes related-list component was removed from `Opportunity_Record_Page_Three_Column` because this workspace is the primary quote list.

## New and Edit Quote view

**New quote** and **Edit** open the product workspace inside the component. Users can search and filter the Opportunity price book, add products, change quantities and discounts, add client-facing line notes, set the expiration date, and edit quote notes.

Saving writes directly to `Quote` and `QuoteLineItem`. It does not create or change `OpportunityLineItem` records.

Server-side rules:

- prices always come from the active Opportunity price book;
- products must be active in that price book;
- discounts above 15% require the `Quote_Discount_Override` custom permission;
- each quote supports at most 50 lines, quantities from 1–9999, and discounts from 0–100%.

## Sync, PDF, and Send

- **Sync to Opportunity** sets `Opportunity.SyncedQuoteId`. Salesforce then copies the selected quote’s lines to Opportunity Products and keeps that quote synchronized.
- **Generate PDF** renders `QuoteBuilderPdf` and saves a `QuoteDocument`. **View PDF** opens the newest saved document.
- **Send quote** asks for confirmation, generates a fresh PDF, emails it to `Quote.Email`, `Quote.Contact.Email`, or the primary Opportunity Contact Role, and changes the quote status to `Presented`.
- Send is disabled when no recipient email can be resolved.

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

- 7 focused LWC Jest tests passed.
- 10 `QuoteBuilderControllerTest` Apex tests passed.
- Staging deployment `0AfVZ00000GQlEz0AL` succeeded.
