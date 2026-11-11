# Quote Builder — POC

A simple, custom product + quote screen for the Opportunity record page. It replaces the standard
**Add Products → Edit Products → New Quote** clicks with one component.

## What it does

| Area                | Behaviour                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Price book screen   | Cards for every active price book with its description and number of active products; the current one is marked. Shown automatically when the Opportunity has no price book, and from the **Change** link next to the price book name while the Opportunity has no products (Salesforce blocks a switch once products are saved). Price books with no active products can’t be picked. Fill in `Pricebook2.Description` so the cards explain each book (e.g. “On-Demand services — same prices as the app”). |
| Catalogue (left)    | Active products in that price book. Search by name, code or description; filter by Product Family. “+ Add” puts a product in the quote (adds 1 if it is already there).                                                                                                                                                                                                                                                                                                                                      |
| Quote lines (right) | Quantity stepper, discount %, note per line (ASIN, scope…), live line total. Lines over the discount limit are highlighted.                                                                                                                                                                                                                                                                                                                                                                                  |
| Totals              | Subtotal at list price, discount, total.                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Save products       | Replaces the Opportunity’s products in one call. Price = price book list price; discount goes in the standard `Discount` field.                                                                                                                                                                                                                                                                                                                                                                              |
| Create quote        | Copies the saved products into a new Quote (“<Opp> – Proposal vN”), valid 7/14/30 days, with notes and the primary contact. If a Quote Template Id is set on the component, it also renders the PDF and attaches it (QuoteDocument).                                                                                                                                                                                                                                                                         |
| Latest quote        | Shows the newest quote with an “Open quote” link.                                                                                                                                                                                                                                                                                                                                                                                                                                                            |

Rules enforced on the server (`QuoteBuilderController`), not in the browser:

- prices always come from the price book;
- every product must be active in the Opportunity’s price book;
- discount above **15%** is rejected unless the user has the **Quote Discount Override** custom permission;
- at most 50 lines, quantity 1–9999, discount 0–100%.

## Files (in `force-app/main/sales-and-contracts/`)

| File                                                                  | Purpose                                                                                                               |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `classes/QuoteBuilderController.cls`                                  | getContext · setPricebook · saveLines · createQuote · generatePdf                                                     |
| `classes/QuoteBuilderControllerTest.cls`                              | 9 tests: catalogue, set price book, save/replace lines, discount limit + override, invalid input, quote + PDF, errors |
| `lwc/quoteBuilder/`                                                   | the component (js, html, css, meta)                                                                                   |
| `customPermissions/Quote_Discount_Override.customPermission-meta.xml` | allows discounts above 15%                                                                                            |

The component is installed on `Opportunity_Record_Page_Three_Column`, replacing the standard Products related list. `Sales_User`, `Sales_Team`, and System Administrator have access to its Apex controller.

Validation completed in staging:

- 5 focused LWC Jest tests passed;
- 9 `QuoteBuilderControllerTest` Apex tests passed;
- deployment job `0AfVZ00000GQhzO0AT` succeeded.

## Deploy to staging

```sh
sf project deploy start --target-org <staging-alias> \
  --source-dir force-app/main/sales-and-contracts/classes/QuoteBuilderController.cls \
  --source-dir force-app/main/sales-and-contracts/classes/QuoteBuilderControllerTest.cls \
  --source-dir force-app/main/sales-and-contracts/lwc/quoteBuilder \
  --source-dir force-app/main/sales-and-contracts/customPermissions/Quote_Discount_Override.customPermission-meta.xml \
  --test-level RunSpecifiedTests --tests QuoteBuilderControllerTest
```

## Set up in the org

1. **Quotes** must be enabled (Setup → Quote Settings). The repo already has `Quote.settings-meta.xml`.
2. **Quote template:** Setup → Quote Templates → create “AppealsDoctor Proposal” (logo, line table with Product, Quantity, Sales Price, Discount, Total Price, Line Description; quote Description as notes). Copy its Id (starts with `0EH`).
3. **Page:** Quote Builder is already in the main column. In App Builder, set **Quote Template Id** when the final template is available.
4. **Access:** Apex access is already included in `Sales_Team` and `Sales_User`. Give **Quote Discount Override** to managers only. Users also need create/edit on Opportunity Product, Quote, Quote Line Item and Quote PDF.
5. **Product Family:** fill `Product2.Family` (e.g. Violation Removal, Listing Issues, A-Z Claim, Feedback Removal, Brand, Account Health, Listing Content; White Glove for retainer tiers) — that drives the filter pills.

## Not in the POC (next steps)

- **Approval process** instead of a hard block above 15% (submit for approval, then unlock Create quote).
- **Send to client:** email the PDF from the component and move the Opportunity to _Proposal Sent_ (after the stage migration in `Client_Journey_Implementation_Plan.md`, SF-1/SF-6).
- **Payment terms per product** (50% deposit vs full upfront, from the On-Demand price list) shown as a “Due now” total — needs a field such as `Product2.Deposit_Percent__c`.
- **Recurring vs one-time** totals for White Glove (monthly) next to On-Demand (one-off).
- Drag-to-reorder lines.
