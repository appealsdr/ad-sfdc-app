/**
 * LeadImportController
 * Apex controller for the leadImport LWC component.
 * Parses a CSV file and inserts Leads into Salesforce.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * SETUP NOTES
 * ─────────────────────────────────────────────────────────────────────────────
 * 1. CUSTOM FIELD — Create a custom Text(255) field on the Lead object:
 *    Label : Import Batch Name
 *    API   : Import_Batch_Name__c
 *    This field stores the "Upload Name" entered in the LWC for traceability.
 *    If you prefer not to create the field, set UPLOAD_NAME_FIELD = null and
 *    the batch name will be prepended to the Description field instead.
 *
 * 2. LEADSOURCE VALUES — The "Source" text entered in the LWC is written to
 *    Lead.LeadSource.  Make sure the value you type in the UI matches an
 *    existing picklist entry, or the insert will throw a field-validation error.
 *    Alternatively, change SOURCE_LEAD_FIELD below to a custom text field.
 * ─────────────────────────────────────────────────────────────────────────────
 */
public with sharing class LeadImportController {

    // =========================================================================
    // FIELD MAPPING CONFIGURATION
    // Key   = CSV column header (trimmed, case-sensitive)
    // Value = Salesforce Lead field API name
    //
    // Add, remove, or change entries freely.
    // To ignore a CSV column entirely, simply omit it from this map.
    // =========================================================================
    @TestVisible
    private static final Map<String, String> CSV_TO_LEAD_FIELD_MAP = new Map<String, String>{
        'First Name'     => 'FirstName',
        'Last Name'      => 'LastName',
        'Mail'           => 'Email',
        'Phone'          => 'Phone',
        'Direct Phone'   => 'MobilePhone',
        'Title'          => 'Title',
        'Seller Name'    => 'Company',
        'Website'        => 'Website',
        'Street Address' => 'Street',
        'City'           => 'City',
        'State'          => 'State',
        'Zip Code'       => 'PostalCode',
        'Country'        => 'Country',
        'Notes (MUST)'   => 'Description'
        // ── Intentionally omitted columns ──────────────────────────────────
        // 'Revenue'         — mixed-format text ($1M-$2M); map to a custom
        //                     text field if needed, e.g. 'Annual_Revenue_Text__c'
        // 'Seller Url'      — duplicate of Website; uncomment to override
        // 'Status'          — CSV status strings don't match SF Lead Status
        //                     picklist values; map to a custom text field if needed
        // 'FBA/FBM', 'Feedback', 'Mail Status', 'Sent back to Melvin' — omitted
    };

    // =========================================================================
    // BATCH METADATA FIELDS
    // These are set from the LWC form inputs (Upload Name + Source), not from
    // the CSV rows themselves.
    // =========================================================================

    // API name of the custom field that stores the batch/upload name.
    // Set to null to prepend it to Description instead.
    @TestVisible
    private static final String UPLOAD_NAME_FIELD = 'Import_Batch_Name__c';

    // Lead field that receives the Source value from the LWC form.
    // Uses LeadSource by default — change to a custom text field if desired.
    @TestVisible
    private static final String SOURCE_LEAD_FIELD = 'LeadSource';


    // =========================================================================
    // INNER CLASSES
    // =========================================================================

    public class ImportResult {
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }
        @AuraEnabled public List<String> errors    { get; set; }
        @AuraEnabled public List<FailedLead> failedLeads { get; set; }

        public ImportResult() {
            this.successCount = 0;
            this.failureCount = 0;
            this.errors       = new List<String>();
            this.failedLeads  = new List<FailedLead>();
        }
    }

    /**
     * FailedLead
     * Represents a single CSV row that was NOT uploaded — either skipped
     * pre-insert (e.g. missing required Company) or rejected by the DB layer
     * (e.g. validation rule, duplicate, invalid picklist value).
     *
     * `rowData` holds every CSV column for that row keyed by the sanitized
     * header name, so the LWC can render the original values regardless of
     * how the CSV → Lead field map is configured.
     */
    public class FailedLead {
        @AuraEnabled public Integer rowNumber { get; set; }
        @AuraEnabled public String  reason    { get; set; }
        @AuraEnabled public Map<String, String> rowData { get; set; }

        public FailedLead(Integer rowNumber, String reason, Map<String, String> rowData) {
            this.rowNumber = rowNumber;
            this.reason    = reason;
            this.rowData   = rowData;
        }
    }

    public class PreviewResult {
        @AuraEnabled public List<Map<String, String>> rows       { get; set; }
        @AuraEnabled public List<Map<String, String>> columns    { get; set; }
        @AuraEnabled public Integer                   totalCount { get; set; }

        public PreviewResult() {
            this.rows       = new List<Map<String, String>>();
            this.columns    = new List<Map<String, String>>();
            this.totalCount = 0;
        }
    }


    // =========================================================================
    // AURA-ENABLED METHODS
    // =========================================================================

    /**
     * getSourceOptions
     * Returns the active picklist values for whatever Lead field is configured
     * as SOURCE_LEAD_FIELD (defaults to LeadSource).
     * The LWC uses this to populate a dynamic combobox instead of a free-text input,
     * which eliminates the most common cause of failed inserts (invalid picklist value).
     *
     * If SOURCE_LEAD_FIELD is not a picklist (e.g. a custom text field), returns
     * an empty list — the LWC then falls back to a plain text input.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getSourceOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        try {
            Schema.SObjectField field = Lead.SObjectType.getDescribe()
                .fields.getMap().get(SOURCE_LEAD_FIELD);
            if (field == null) {
                return options;
            }
            Schema.DescribeFieldResult dfr = field.getDescribe();
            if (dfr.getType() != Schema.DisplayType.PICKLIST &&
                dfr.getType() != Schema.DisplayType.MULTIPICKLIST) {
                return options;
            }
            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                if (entry.isActive()) {
                    options.add(new Map<String, String>{
                        'label' => entry.getLabel(),
                        'value' => entry.getValue()
                    });
                }
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load Source options: ' + e.getMessage());
        }
    }

    /**
     * parseCSVPreview
     * Called by the LWC after the user selects a file.
     * Returns column definitions and a capped preview (first 50 rows) for the
     * lightning-datatable — does NOT insert any data.
     */
    @AuraEnabled
    public static PreviewResult parseCSVPreview(String csvContent) {
        try {
            List<List<String>> parsed = parseCSV(csvContent);
            if (parsed == null || parsed.isEmpty()) {
                throw new AuraHandledException('The file appears to be empty.');
            }

            List<String> headers = parsed[0];
            PreviewResult result = new PreviewResult();

            // Build column definitions for lightning-datatable
            for (String header : headers) {
                Map<String, String> col = new Map<String, String>{
                    'label'    => header,
                    'fieldName'=> sanitizeKey(header),
                    'type'     => 'text'
                };
                result.columns.add(col);
            }

            // Build row data (max 50 rows for preview)
            Integer dataRows = parsed.size() - 1;
            result.totalCount = dataRows;
            Integer previewLimit = Math.min(dataRows, 50);

            for (Integer i = 1; i <= previewLimit; i++) {
                List<String> rowValues = parsed[i];
                Map<String, String> rowMap = new Map<String, String>();
                rowMap.put('__id', String.valueOf(i));
                for (Integer j = 0; j < headers.size(); j++) {
                    String cellValue = j < rowValues.size() ? rowValues[j] : '';
                    rowMap.put(sanitizeKey(headers[j]), cellValue);
                }
                result.rows.add(rowMap);
            }

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error parsing CSV: ' + e.getMessage());
        }
    }

    /**
     * importLeads
     * Called when the user clicks "Upload".
     * Parses the full CSV, maps columns to Lead fields, and inserts records.
     * Returns counts of successes and failures (partial success supported).
     */
    @AuraEnabled
    public static ImportResult importLeads(String csvContent, String uploadName, String source) {
        try {
            List<List<String>> parsed = parseCSV(csvContent);
            if (parsed == null || parsed.size() < 2) {
                throw new AuraHandledException('No data rows found in the file.');
            }

            List<String> headers = parsed[0];

            // Build column-index lookup: CSV header → column index
            Map<String, Integer> headerIndex = new Map<String, Integer>();
            for (Integer i = 0; i < headers.size(); i++) {
                headerIndex.put(headers[i], i);
            }

            ImportResult result = new ImportResult();

            // Parallel arrays — same index across all three.
            // Lets us correlate Database.SaveResult ↔ original row data/number
            // after a partial-success insert.
            List<Lead>                 leadsToInsert  = new List<Lead>();
            List<Map<String, String>>  insertRowData  = new List<Map<String, String>>();
            List<Integer>              insertRowNums  = new List<Integer>();

            for (Integer rowIdx = 1; rowIdx < parsed.size(); rowIdx++) {
                List<String> row = parsed[rowIdx];

                // Snapshot the original CSV row keyed by sanitized header so the
                // LWC can render it — this is also what we attach to FailedLead.
                Map<String, String> rowData = new Map<String, String>();
                for (Integer j = 0; j < headers.size(); j++) {
                    String cellValue = j < row.size() ? row[j] : '';
                    rowData.put(sanitizeKey(headers[j]), cellValue);
                }

                // Spreadsheet-style row number (header is row 1, first data row is 2)
                Integer rowNumber = rowIdx + 1;

                Lead l = new Lead();

                // Map CSV columns to Lead fields
                for (String csvColumn : CSV_TO_LEAD_FIELD_MAP.keySet()) {
                    String sfField = CSV_TO_LEAD_FIELD_MAP.get(csvColumn);
                    Integer colIdx = headerIndex.get(csvColumn);
                    if (colIdx != null) {
                        String cellValue = colIdx < row.size() ? row[colIdx].trim() : '';
                        if (String.isNotBlank(cellValue)) {
                            l.put(sfField, cellValue);
                        }
                    }
                }

                // Set batch metadata from form inputs
                if (String.isNotBlank(source)) {
                    l.put(SOURCE_LEAD_FIELD, source);
                }
                if (String.isNotBlank(uploadName)) {
                    if (UPLOAD_NAME_FIELD != null) {
                        // Preferred: dedicated custom field
                        try {
                            l.put(UPLOAD_NAME_FIELD, uploadName);
                        } catch (Exception fieldEx) {
                            // Custom field doesn't exist yet — fall back to Description prefix
                            String existingDesc = (String) l.get('Description');
                            l.put('Description',
                                '[Import: ' + uploadName + '] ' +
                                (String.isNotBlank(existingDesc) ? existingDesc : ''));
                        }
                    } else {
                        // Fallback: prepend to Description
                        String existingDesc = (String) l.get('Description');
                        l.put('Description',
                            '[Import: ' + uploadName + '] ' +
                            (String.isNotBlank(existingDesc) ? existingDesc : ''));
                    }
                }

                // Company is required on Lead — capture as a failed lead instead of silently dropping
                if (String.isBlank((String) l.get('Company'))) {
                    String reason = 'Missing required value: Company / Seller Name';
                    result.failureCount++;
                    result.errors.add('Row ' + rowNumber + ': ' + reason);
                    result.failedLeads.add(new FailedLead(rowNumber, reason, rowData));
                    continue;
                }

                leadsToInsert.add(l);
                insertRowData.add(rowData);
                insertRowNums.add(rowNumber);
            }

            // Bail out only if nothing parsed AND nothing was already captured as failed
            if (leadsToInsert.isEmpty() && result.failedLeads.isEmpty()) {
                throw new AuraHandledException('No data rows found in the file.');
            }

            // Insert with partial success (allOrNone = false)
            if (!leadsToInsert.isEmpty()) {
                Database.SaveResult[] saveResults = Database.insert(leadsToInsert, false);

                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    Integer rowNumber = insertRowNums[i];

                    if (sr.isSuccess()) {
                        result.successCount++;
                    } else {
                        result.failureCount++;

                        // Concatenate every error returned for this row
                        List<String> messages = new List<String>();
                        for (Database.Error err : sr.getErrors()) {
                            messages.add(err.getMessage());
                            result.errors.add('Row ' + rowNumber + ': ' + err.getMessage());
                        }
                        result.failedLeads.add(new FailedLead(
                            rowNumber,
                            String.join(messages, '; '),
                            insertRowData[i]
                        ));
                    }
                }
            }

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unexpected error during import: ' + e.getMessage());
        }
    }


    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    /**
     * parseCSV
     * Parses a CSV string into a List<List<String>>.
     * - Skips leading empty rows (handles files with blank rows at the top)
     * - Handles double-quoted fields containing commas or double-quotes
     * - Returns null if content is blank
     */
    @TestVisible
    private static List<List<String>> parseCSV(String csvContent) {
        if (String.isBlank(csvContent)) {
            return null;
        }

        List<List<String>> result   = new List<List<String>>();
        List<String>       lines    = csvContent.split('\n');
        Boolean            foundHeader = false;

        for (String rawLine : lines) {
            // Normalize Windows line endings
            String line = rawLine.removeEnd('\r');

            List<String> fields = splitCSVLine(line);

            // Detect empty rows: all fields blank → skip until header found
            Boolean allBlank = true;
            for (String f : fields) {
                if (String.isNotBlank(f)) {
                    allBlank = false;
                    break;
                }
            }

            if (allBlank && !foundHeader) {
                continue;  // skip leading blank rows
            }

            foundHeader = true;
            result.add(fields);
        }

        return result;
    }

    /**
     * splitCSVLine
     * Splits a single CSV line respecting double-quoted fields.
     * Handles commas inside quotes and escaped double-quotes ("").
     */
    private static List<String> splitCSVLine(String line) {
        List<String> fields  = new List<String>();
        Boolean      inQuote = false;
        String       current = '';
        Integer      i       = 0;

        while (i < line.length()) {
            String ch = line.substring(i, i + 1);

            if (ch == '"') {
                if (inQuote && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    // Escaped quote inside quoted field
                    current += '"';
                    i += 2;
                } else {
                    inQuote = !inQuote;
                    i++;
                }
            } else if (ch == ',' && !inQuote) {
                fields.add(current.trim());
                current = '';
                i++;
            } else {
                current += ch;
                i++;
            }
        }
        fields.add(current.trim());

        return fields;
    }

    /**
     * sanitizeKey
     * Converts a CSV header to a safe JavaScript property name
     * for use as a fieldName in lightning-datatable column definitions.
     */
    private static String sanitizeKey(String header) {
        return header.replaceAll('[^a-zA-Z0-9]', '_').toLowerCase();
    }
}