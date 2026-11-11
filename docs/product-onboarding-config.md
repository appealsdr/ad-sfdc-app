# Product and Case onboarding configuration

`productOnboardingConfig` is a Lightning Web Component for Product2 and Case record pages. It is available in Lightning App Builder as **Onboarding Configuration**. It is included below the standard record details in `Product_Record_Page` and below **Case Details** in the left sidebar of `Case_Record_Page1` (**Case Record Page Main**).

On a Product, the component reads and saves `Product2.Onboarding_Config__c`. On a Case, it reads and saves `Case.Case_Onboarding__c` on that Case. Editing a Case configuration does not change the Product configuration. Both contexts configure Case fields using the same JSON format.

The card initially displays the configured Case fields in their saved order. **Edit** replaces the card body with an inline editor. The card's actions provide **Add Field**, **Cancel**, and **Save**. Each field supports an override label, a required checkbox, removal, and drag-and-drop ordering. Up/down buttons also support ordering with a keyboard.

## Existing field dependency

The component uses the existing `Product2.Onboarding_Config__c` and `Case.Case_Onboarding__c` fields. Their definitions are not included locally; this change does not redefine them. Both fields must be available in the target org and accept a JSON string. Before saving, the component checks the character limit reported by object metadata for the field used by the current record. Product and Case field limits can differ.

Users need read access to the current record and its configuration field, access to Case metadata, and edit access to the current object, record, and configuration field to save. Case users do not need Product access to edit their Case configuration. Lightning Data Service handles record reads and updates; no Apex controller or new permission assignment is required.

## Saved format

```json
[
  {
    "fieldapiname": "Subject",
    "fieldlabel": "Issue summary",
    "required": true
  },
  {
    "fieldapiname": "Description",
    "fieldlabel": "",
    "required": false
  }
]
```

Array order defines display order. An empty override label uses the current Case field label. Removing every row saves `[]`. Cancel discards the draft without writing the record.

Duplicate selections are blocked. Invalid saved JSON blocks editing to protect the original data; correct the field value before using the editor. Existing fields that are unavailable to the current user remain visible by API name and are preserved unless explicitly replaced or removed.

Saves use the current record's last modification timestamp to detect concurrent changes. A conflict refreshes the saved configuration while preserving the draft; cancel and edit again to work from the latest version. Navigating to another record or object clears the previous edit session.

## Deployment

Deploy the component and the Product and Case record pages together to an authenticated target org:

```sh
sf project deploy start --target-org <org-alias> \
  --source-dir force-app/main/sales-and-contracts/lwc/productOnboardingConfig \
  --source-dir force-app/main/default/flexipages/Product_Record_Page.flexipage-meta.xml \
  --source-dir force-app/main/case-management/flexipages/Case_Record_Page1.flexipage-meta.xml
```

If another record page is assigned to Products or Cases, add **Onboarding Configuration** to that page in Lightning App Builder. Salesforce provides the record ID and object API name on record pages; no component properties need to be configured manually.

## Tests

The Jest suite is in `force-app/main/sales-and-contracts/lwc/productOnboardingConfig/__tests__/productOnboardingConfig.test.js`:

The suite covers Product and Case loading and saving, permissions, field limits, configuration validation, concurrent updates, and record navigation, alongside editing and reordering behavior.

```sh
npm run test:unit -- --runInBand --runTestsByPath \
  force-app/main/sales-and-contracts/lwc/productOnboardingConfig/__tests__/productOnboardingConfig.test.js
```
