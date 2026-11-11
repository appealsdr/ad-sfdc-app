# Required File S3 document migration

Use `scripts/apex/migrateRequiredFileS3Documents.apex` to update production documents created before the Required File upload association changed. This is anonymous Apex; no migration class deployment is required. The script starts in dry-run mode.

The script finds a document's requirement through `S3_Document__c.Required_File__c`, a legacy `Related_Record_Id__c` pointing to a Required File, or the default/current upload stored in `Required_File__c.Last_Version__c`. It includes older versions with either explicit association, even when they are no longer the last version.

It sets only these S3 document fields:

| Field | Value |
| --- | --- |
| `Required_File__c` | The uniquely identified requirement |
| `Related_Record_Id__c` | The requirement's parent record ID |
| `Related_Object_Type__c` | The parent's object API name |

Parent selection follows the existing `S3DocumentPathService` configuration: `Case__c` first, then `Store__c`, then `Document_Template__c`. A requirement with both a Case and a Store uses the Case; a requirement with a Store and a template uses the Store.

S3 objects are not moved or copied. Bucket, key, region, URLs, document status, and upload metadata are preserved. All document statuses are scanned; archived and deleted documents retain their statuses. The script does not write Required Files or change `Last_Version__c` or `File_Uploaded__c`. Updating Required Files would invoke the existing upload notification flow.

## Before running

Ensure the target org has the existing S3 objects and fields, including `S3_Document__c.Required_File__c`. Run as an administrator who can read the relevant documents and requirements and update document associations. Use an explicit production alias on every command.

Export the associations before applying changes:

```sh
sf data query --target-org <production-alias> \
  --query "SELECT Id, Required_File__c, Related_Record_Id__c, Related_Object_Type__c FROM S3_Document__c ORDER BY Id" \
  --result-format csv > /tmp/s3-document-links-before.csv
```

Keep the CSV and execution logs until verification is complete. The `S3_MIGRATION_PROPOSED` log entries also contain each document's before and after values.

## Run each page

1. Leave `dryRun = true`, `pageSize = 200`, and `afterDocumentId = null` for the first page. Run:

   ```sh
   sf apex run --file scripts/apex/migrateRequiredFileS3Documents.apex \
     --target-org <production-alias>
   ```

2. Review `S3_MIGRATION_PROPOSED`, `S3_MIGRATION_SKIPPED`, and `S3_MIGRATION_SUMMARY`. A dry run performs queries and logs proposals without DML.
3. Set `dryRun = false` and run the same command with the **same** `afterDocumentId` to apply the reviewed page.
4. On `NEXT_CURSOR=<id>`, set `afterDocumentId = '<id>';`, return to `dryRun = true`, and repeat. Each page scans up to `pageSize` documents, including unrelated and already correct records, so skipped records do not block later pages.
5. If the run reports `RETRY_CURRENT_CURSOR`, fix the logged failures and rerun the same cursor. Successful updates can be safely replayed. If execution fails or no cursor is printed, also retain the current cursor.
6. Continue until a live run reports `S3_MIGRATION_COMPLETE`. Save and resolve the skipped records separately; completion of the scan does not mean every conflict was resolved.

Use a smaller page for large logs or extensive org automation. The script allows 1–1,000 documents per page and aborts before DML if over 5,000 matching requirements are found. Reduce the page size or resolve shared references before retrying that cursor. Reverting to `afterDocumentId = null` safely starts another pass.

## Records requiring review

The script skips documents with conflicting requirement associations, including a last version shared by multiple requirements; malformed related record IDs; missing requirements; requirements without a supported parent; and documents already assigned to a different parent. A legacy related ID equal to the requirement's ID is allowed and is replaced with the resolved parent ID.

Unrelated standalone uploads and template files without a Required File association remain unchanged. The script does not infer a requirement from a file name, S3 path, or a parent record alone. History with no remaining lookup, legacy related ID, or last-version reference needs manual identification.

After migration, inspect representative Case and Store Required Files lists: uploads should be grouped under their requirements and preview/download should still work. To verify an applied page, rerun its starting cursor in dry-run mode: previously applied changes should count as `alreadyCorrect`, with no proposals for those documents. For a final read-only audit, start at `null` and use each `PREVIEW_PAGE_END` as the next cursor until `S3_MIGRATION_PREVIEW_COMPLETE`. During migration, apply each previewed page before advancing; `PREVIEW_PAGE_END` does not mean the page has been applied.
