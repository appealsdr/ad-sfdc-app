// Migrate legacy Required File uploads to the current S3 document associations.
// Run: sf apex run --file scripts/apex/migrateRequiredFileS3Documents.apex --target-org <production-alias>
// Read docs/s3-document-migration.md before running. No class deployment is needed.
// Preview each page with dryRun = true, then apply THE SAME cursor with false.
// Advance afterDocumentId only to the logged NEXT_CURSOR after a successful apply.

Boolean dryRun = true;
Integer pageSize = 200;
Id afterDocumentId = null;

System.assert(pageSize > 0 && pageSize <= 1000, 'pageSize must be between 1 and 1000.');
System.assert(
    afterDocumentId == null || afterDocumentId.getSObjectType() == S3_Document__c.SObjectType,
    'afterDocumentId must be an S3_Document__c Id.'
);

// Scan every document so Last_Version-only references and older versions are included.
// Paging all records also prevents conflicts or unrelated uploads blocking progress.
String documentQuery =
    'SELECT Id, Required_File__c, Related_Record_Id__c, Related_Object_Type__c ' +
    'FROM S3_Document__c';
if (afterDocumentId != null) {
    documentQuery += ' WHERE Id > :afterDocumentId';
}
documentQuery += ' ORDER BY Id LIMIT :pageSize';
List<S3_Document__c> documents = Database.query(documentQuery);

Set<Id> documentIds = new Set<Id>();
Set<Id> requiredFileIds = new Set<Id>();
Map<Id, Id> relatedIdsByDocument = new Map<Id, Id>();
Map<Id, Set<Id>> candidatesByDocument = new Map<Id, Set<Id>>();
Set<Id> malformedRelatedIds = new Set<Id>();

for (S3_Document__c document : documents) {
    documentIds.add(document.Id);
    Set<Id> candidates = new Set<Id>();
    candidatesByDocument.put(document.Id, candidates);
    if (document.Required_File__c != null) {
        candidates.add(document.Required_File__c);
        requiredFileIds.add(document.Required_File__c);
    }
    if (String.isNotBlank(document.Related_Record_Id__c)) {
        try {
            Id relatedId = Id.valueOf(document.Related_Record_Id__c);
            relatedIdsByDocument.put(document.Id, relatedId);
            if (relatedId.getSObjectType() == Required_File__c.SObjectType) {
                candidates.add(relatedId);
                requiredFileIds.add(relatedId);
            }
        } catch (Exception ex) {
            malformedRelatedIds.add(document.Id);
        }
    }
}

Map<Id, Required_File__c> requiredFilesById = new Map<Id, Required_File__c>();
if (!documentIds.isEmpty()) {
    // Include reverse Last_Version references outside the page's explicit lookups.
    // A shared default document cannot be assigned to multiple required files.
    List<Required_File__c> requiredFiles = [
        SELECT Id, Case__c, Store__c, Document_Template__c, Last_Version__c
        FROM Required_File__c
        WHERE Id IN :requiredFileIds OR Last_Version__c IN :documentIds
        LIMIT 5001
    ];
    System.assert(
        requiredFiles.size() <= 5000,
        'Too many matching Required Files. Reduce pageSize or resolve shared Last_Version references; no updates were made.'
    );
    for (Required_File__c requiredFile : requiredFiles) {
        requiredFilesById.put(requiredFile.Id, requiredFile);
        if (documentIds.contains(requiredFile.Last_Version__c)) {
            candidatesByDocument.get(requiredFile.Last_Version__c).add(requiredFile.Id);
        }
    }
}

List<S3_Document__c> updates = new List<S3_Document__c>();
Integer unrelatedCount = 0;
Integer alreadyCorrectCount = 0;
Integer skippedCount = 0;
for (S3_Document__c document : documents) {
    Set<Id> candidates = candidatesByDocument.get(document.Id);
    if (candidates.isEmpty() && document.Related_Object_Type__c != 'Required_File__c') {
        unrelatedCount++;
        continue;
    }

    String skipReason;
    Required_File__c requiredFile;
    Id parentId;
    String parentType;
    if (candidates.size() != 1) {
        skipReason = candidates.isEmpty()
            ? 'No valid Required File association.'
            : 'Conflicting Required File associations or shared Last_Version: ' + String.valueOf(candidates);
    } else if (malformedRelatedIds.contains(document.Id)) {
        skipReason = 'Related_Record_Id__c is not a valid Salesforce Id.';
    } else {
        Id requiredFileId = new List<Id>(candidates)[0];
        requiredFile = requiredFilesById.get(requiredFileId);
        if (requiredFile == null) {
            skipReason = 'Required File is missing or unavailable: ' + requiredFileId;
        } else {
            // Match S3DocumentPathService.buildRequiredFilePath parent precedence.
            if (requiredFile.Case__c != null) {
                parentId = requiredFile.Case__c;
                parentType = 'Case';
            } else if (requiredFile.Store__c != null) {
                parentId = requiredFile.Store__c;
                parentType = 'Store__c';
            } else if (requiredFile.Document_Template__c != null) {
                parentId = requiredFile.Document_Template__c;
                parentType = 'Document_Template__c';
            }

            Id existingRelatedId = relatedIdsByDocument.get(document.Id);
            if (parentId == null) {
                skipReason = 'Required File has no Case, Store, or Document Template parent.';
            } else if (
                existingRelatedId != null &&
                existingRelatedId != requiredFile.Id &&
                existingRelatedId != parentId
            ) {
                skipReason = 'Document already belongs to another parent: ' + existingRelatedId;
            }
        }
    }

    if (skipReason != null) {
        skippedCount++;
        System.debug(LoggingLevel.WARN, 'S3_MIGRATION_SKIPPED ' + document.Id + ': ' + skipReason);
        continue;
    }

    String parentIdText = String.valueOf(parentId);
    if (
        document.Required_File__c == requiredFile.Id &&
        parentIdText.equals(document.Related_Record_Id__c) &&
        parentType.equals(document.Related_Object_Type__c)
    ) {
        alreadyCorrectCount++;
        continue;
    }

    S3_Document__c change = new S3_Document__c(
        Id = document.Id,
        Required_File__c = requiredFile.Id,
        Related_Record_Id__c = parentIdText,
        Related_Object_Type__c = parentType
    );
    updates.add(change);
    // Retain old values in the execution log for review and recovery.
    System.debug(LoggingLevel.INFO, 'S3_MIGRATION_PROPOSED ' + JSON.serialize(
        new Map<String, Object>{ 'before' => document, 'after' => change }
    ));
}

Integer updatedCount = 0;
Integer failedCount = 0;
if (!dryRun && !updates.isEmpty()) {
    Database.SaveResult[] results = Database.update(updates, false);
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            updatedCount++;
        } else {
            failedCount++;
            for (Database.Error error : results[i].getErrors()) {
                System.debug(LoggingLevel.ERROR,
                    'S3_MIGRATION_FAILED ' + updates[i].Id + ': ' +
                    error.getStatusCode() + ' - ' + error.getMessage());
            }
        }
    }
}

System.debug(LoggingLevel.INFO,
    'S3_MIGRATION_SUMMARY dryRun=' + dryRun +
    ', scanned=' + documents.size() +
    ', proposed=' + updates.size() +
    ', updated=' + updatedCount +
    ', failed=' + failedCount +
    ', alreadyCorrect=' + alreadyCorrectCount +
    ', unrelated=' + unrelatedCount +
    ', skipped=' + skippedCount);

if (dryRun) {
    System.debug(LoggingLevel.INFO,
        'DRY_RUN: no updates were made. Set dryRun=false and rerun with the SAME afterDocumentId before advancing.');
    if (documents.isEmpty()) {
        System.debug(LoggingLevel.INFO, 'S3_MIGRATION_PREVIEW_COMPLETE: no documents remain after this cursor.');
    } else {
        System.debug(LoggingLevel.INFO,
            'PREVIEW_PAGE_END=' + documents[documents.size() - 1].Id +
            ' (for audit-only paging; do not skip applying this page during migration)');
    }
} else if (failedCount > 0) {
    System.debug(LoggingLevel.ERROR,
        'RETRY_CURRENT_CURSOR: resolve failures and rerun with the SAME afterDocumentId. Successful changes are idempotent.');
} else if (documents.isEmpty()) {
    System.debug(LoggingLevel.INFO, 'S3_MIGRATION_COMPLETE: no documents remain after this cursor. Review all skipped records.');
} else {
    System.debug(LoggingLevel.INFO, 'NEXT_CURSOR=' + documents[documents.size() - 1].Id);
}
