@isTest
private class DrAppEmailTemplateOptionsTest {

    @isTest
    static void testGetDefaultValue() {
        DrAppEmailTemplateOptions picklist = new DrAppEmailTemplateOptions(null);

        Test.startTest();
        VisualEditor.DataRow defaultRow = picklist.getDefaultValue();
        Test.stopTest();

        System.assertEquals('-- Select a template --', defaultRow.getLabel());
        System.assertEquals('', defaultRow.getValue());
    }

    @isTest
    static void testGetValuesReturnsActiveTemplates() {
        DrAppEmailTemplateOptions picklist = new DrAppEmailTemplateOptions(null);

        Test.startTest();
        VisualEditor.DynamicPickListRows rows = picklist.getValues();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Expected a non-null set of picklist rows.');
    }
}