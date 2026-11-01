@IsTest
private class LeadImportControllerTest {

    private static String getValidLeadSource() {
        for (Schema.PicklistEntry entry : Lead.LeadSource.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String buildSampleCsv() {
        return 'First Name,Last Name,Mail,Phone,Seller Name,City,State,Notes (MUST)\n' +
               'John,Doe,john.doe+' + String.valueOf(Crypto.getRandomInteger()) +
               '@example.com,555-1111,Acme Corp,Austin,TX,Note one\n' +
               'Jane,Smith,jane.smith+' + String.valueOf(Crypto.getRandomInteger()) +
               '@example.com,555-2222,Beta LLC,Dallas,TX,Note two';
    }

    private static String buildCsvMissingCompany() {
        return 'First Name,Last Name,Mail,Seller Name\n' +
               'John,Doe,john@example.com,\n' +
               'Jane,Smith,jane@example.com,Valid Co';
    }

    @IsTest
    static void testGetSourceOptions_ReturnsActivePicklistValues() {
        Test.startTest();
        List<Map<String, String>> options = LeadImportController.getSourceOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Options list must not be null');

        String validSource = getValidLeadSource();
        if (validSource != null) {
            System.assert(options.size() > 0, 'Expected at least one active LeadSource option');
            Boolean found = false;
            for (Map<String, String> opt : options) {
                if (opt.get('value') == validSource) {
                    found = true;
                    break;
                }
            }
            System.assertEquals(true, found, 'Expected active LeadSource value in options');
        }
    }

    @IsTest
    static void testParseCSVPreview_ReturnsColumnsAndRows() {
        Test.startTest();
        LeadImportController.PreviewResult result =
            LeadImportController.parseCSVPreview(buildSampleCsv());
        Test.stopTest();

        System.assertEquals(2, result.totalCount, 'Expected 2 data rows');
        System.assertEquals(2, result.rows.size(), 'Preview should include both rows');
        System.assert(result.columns.size() > 0, 'Columns should be populated');
        System.assertEquals('1', result.rows[0].get('__id'), 'First row id should be 1');
        System.assertEquals('John', result.rows[0].get('first_name'), 'First Name should be mapped');
    }

    @IsTest
    static void testParseCSVPreview_EmptyFileThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            LeadImportController.parseCSVPreview('');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Empty CSV should throw AuraHandledException');
    }

    @IsTest
    static void testParseCSVPreview_HandlesQuotedCommas() {
        String csv =
            'First Name,Last Name,Seller Name\n' +
            '"John","Doe","Acme, Inc"';

        Test.startTest();
        LeadImportController.PreviewResult result =
            LeadImportController.parseCSVPreview(csv);
        Test.stopTest();

        System.assertEquals(1, result.totalCount);
        System.assertEquals('Acme, Inc', result.rows[0].get('seller_name'));
    }

    @IsTest
    static void testParseCSVPreview_CapsPreviewAt50Rows() {
        List<String> lines = new List<String>{ 'First Name,Last Name,Seller Name' };
        for (Integer i = 0; i < 60; i++) {
            lines.add('First' + i + ',Last' + i + ',Company' + i);
        }
        String csv = String.join(lines, '\n');

        Test.startTest();
        LeadImportController.PreviewResult result =
            LeadImportController.parseCSVPreview(csv);
        Test.stopTest();

        System.assertEquals(60, result.totalCount, 'Total count should reflect all rows');
        System.assertEquals(50, result.rows.size(), 'Preview should cap at 50 rows');
    }

    @IsTest
    static void testImportLeads_InsertsValidRows() {
        String source = getValidLeadSource();
        System.assertNotEquals(null, source, 'Org must have at least one active LeadSource value');

        Test.startTest();
        LeadImportController.ImportResult result = LeadImportController.importLeads(
            buildSampleCsv(),
            'Batch-A',
            source
        );
        Test.stopTest();

        System.assertEquals(2, result.successCount, 'Both rows should succeed');
        System.assertEquals(0, result.failureCount);
        System.assertEquals(2, [SELECT COUNT() FROM Lead WHERE LeadSource = :source]);
    }

    @IsTest
    static void testImportLeads_SetsUploadNameAndSource() {
        String source = getValidLeadSource();
        System.assertNotEquals(null, source, 'Org must have at least one active LeadSource value');

        Test.startTest();
        LeadImportController.importLeads(
            'First Name,Last Name,Seller Name\nJohn,Doe,Acme Corp',
            'My Upload Batch',
            source
        );
        Test.stopTest();

        Lead inserted = [
            SELECT LeadSource, Import_Batch_Name__c, Description
            FROM Lead
            WHERE Company = 'Acme Corp'
            LIMIT 1
        ];

        System.assertEquals(source, inserted.LeadSource);

        if (inserted.Import_Batch_Name__c != null) {
            System.assertEquals('My Upload Batch', inserted.Import_Batch_Name__c);
        } else {
            System.assert(
                inserted.Description != null && inserted.Description.contains('My Upload Batch'),
                'Upload name should fall back to Description prefix'
            );
        }
    }

    @IsTest
    static void testImportLeads_MissingCompanyCapturedAsFailedLead() {
        String source = getValidLeadSource();

        Test.startTest();
        LeadImportController.ImportResult result = LeadImportController.importLeads(
            buildCsvMissingCompany(),
            'Batch-B',
            source
        );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'One row has Company');
        System.assertEquals(1, result.failureCount, 'One row missing Company');
        System.assertEquals(1, result.failedLeads.size());
        System.assert(
            result.failedLeads[0].reason.contains('Missing required value: Company'),
            'Failure reason should mention missing Company'
        );
        System.assertEquals(2, result.failedLeads[0].rowNumber, 'First data row is spreadsheet row 2');
    }

    @IsTest
    static void testImportLeads_InvalidLeadSourceHandling() {
        String invalidSource = 'DefinitelyNotAValidLeadSourceValue12345';
        Boolean isRestricted = Lead.LeadSource.getDescribe().isRestrictedPicklist();

        Test.startTest();
        LeadImportController.ImportResult result = LeadImportController.importLeads(
            'First Name,Last Name,Seller Name\nJohn,Doe,Acme Corp',
            'Batch-C',
            invalidSource
        );
        Test.stopTest();

        if (isRestricted) {
            System.assertEquals(0, result.successCount);
            System.assertEquals(1, result.failureCount);
            System.assertEquals(1, result.failedLeads.size());
            System.assert(result.errors.size() > 0, 'Errors list should contain DB validation message');
        } else {
            System.assertEquals(1, result.successCount, 'Unrestricted picklist should accept custom source');
            System.assertEquals(invalidSource, [SELECT LeadSource FROM Lead WHERE Company = 'Acme Corp' LIMIT 1].LeadSource);
        }
    }

    @IsTest
    static void testImportLeads_NoDataRowsThrows() {
        Boolean threw = false;

        Test.startTest();
        try {
            LeadImportController.importLeads('First Name,Last Name,Seller Name', 'Batch-D', 'Web');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Header-only CSV should throw');
    }

    @IsTest
    static void testParseCSV_ReturnsNullForBlankContent() {
        System.assertEquals(null, LeadImportController.parseCSV(null));
        System.assertEquals(null, LeadImportController.parseCSV('   '));
    }

    @IsTest
    static void testParseCSV_SkipsLeadingBlankRows() {
        String csv =
            '\n\n' +
            'First Name,Last Name,Seller Name\n' +
            'John,Doe,Acme Corp';

        List<List<String>> parsed = LeadImportController.parseCSV(csv);

        System.assertEquals(2, parsed.size(), 'Header + one data row after skipping blanks');
        System.assertEquals('First Name', parsed[0][0]);
    }

    @IsTest
    static void testParseCSV_HandlesWindowsLineEndings() {
        String csv = 'First Name,Last Name\r\nJohn,Doe';

        List<List<String>> parsed = LeadImportController.parseCSV(csv);

        System.assertEquals(2, parsed.size());
        System.assertEquals('John', parsed[1][0]);
    }
}