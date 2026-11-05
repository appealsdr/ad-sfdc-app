# Product onboarding configuration

`productOnboardingConfig` is a Lightning Web Component for Product2 record pages. It is included below the standard record details in `Product_Record_Page` and is also available in Lightning App Builder as **Product Onboarding Configuration**.

The card initially displays the configured Case fields in their saved order. **Edit** replaces the card body with an inline editor. The card's actions provide **Add Field**, **Cancel**, and **Save**. Each field supports an override label, a required checkbox, removal, and drag-and-drop ordering. Up/down buttons also support ordering with a keyboard.

## Existing field dependency

The component uses the existing `Product2.Onboarding_Config__c` field referenced by this repository's profiles and Product layout. Its field definition is not included locally; this change does not redefine it. The field must be available in the target org and accept a JSON string. The component checks the field's actual character limit before saving.

Users need read access to Product2 and `Onboarding_Config__c`, access to Case metadata, and edit access to the Product record and configuration field to save. Lightning Data Service handles record reads and updates; no Apex controller or new permission assignment is required.

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

Saves use the Product's last modification timestamp to detect concurrent changes. A conflict refreshes the saved configuration while preserving the draft; cancel and edit again to work from the latest version.

## Deployment

Deploy the component and the updated Product record page together to an authenticated target org:

```sh
sf project deploy start --target-org <org-alias> \
  --source-dir force-app/main/sales-and-contracts/lwc/productOnboardingConfig \
  --source-dir force-app/main/default/flexipages/Product_Record_Page.flexipage-meta.xml
```

If another record page is assigned to Products, add **Product Onboarding Configuration** to that page in Lightning App Builder.

## Tests

The Jest suite is in `force-app/main/sales-and-contracts/lwc/productOnboardingConfig/__tests__/productOnboardingConfig.test.js`:

```sh
npm run test:unit -- --runInBand --runTestsByPath \
  force-app/main/sales-and-contracts/lwc/productOnboardingConfig/__tests__/productOnboardingConfig.test.js
```
