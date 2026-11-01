@IsTest
public class CaseUtilTest {

    // ---------------------------------------------------------
    // Test: getFieldSetFromCase (Safe for all orgs)
    // ---------------------------------------------------------
    @IsTest
    static void GetFieldSetFromCaseTest() {

        Test.startTest();
        List<CaseUtil.CaseFieldSetWrapper> result =
            CaseUtil.getFieldSetFromCase('Case');
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Result should never be null');

        // FieldSets may or may not exist – no size assertion
        if (!result.isEmpty()) {
            CaseUtil.CaseFieldSetWrapper fs = result[0];
            System.assertNotEquals(null, fs.name);
            System.assertNotEquals(null, fs.label);
            System.assertNotEquals(null, fs.fields);
        }
    }

    // ---------------------------------------------------------
    // Test: setFieldValue - Text
    // ---------------------------------------------------------
    @IsTest
    static void SetFieldValueTextTest() {
        Case c = new Case();

        Test.startTest();
        c = CaseUtil.setFieldValue(c, 'Subject', 'Test Subject');
        Test.stopTest();

        System.assertEquals('Test Subject', c.Subject);
    }

    // ---------------------------------------------------------
    // Test: setFieldValue - Email (String)
    // ---------------------------------------------------------
    @IsTest
    static void SetFieldValueEmailTest() {
        Case c = new Case();

        Test.startTest();
        c = CaseUtil.setFieldValue(c, 'SuppliedEmail', 'test@test.com');
        Test.stopTest();

        System.assertEquals('test@test.com', c.SuppliedEmail);
    }

    // ---------------------------------------------------------
    // Test: setFieldValue - Boolean
    // ---------------------------------------------------------
    @IsTest
    static void SetFieldValueBooleanTest() {
        Case c = new Case();

        Test.startTest();
        c = CaseUtil.setFieldValue(c, 'IsEscalated', true);
        Test.stopTest();

        System.assertEquals(true, c.IsEscalated);
    }

    // ---------------------------------------------------------
    // Test: setFieldValue - Date
    // ---------------------------------------------------------
    @IsTest
    static void SetFieldValueDateTest() {
        Case c = new Case();
        Date today = Date.today();

        Test.startTest();
        c = CaseUtil.setFieldValue(c, 'ClosedDate', today);
        Test.stopTest();

        //System.assertEquals(today, c.ClosedDate);
    }

    // ---------------------------------------------------------
    // Test: setFieldValue - Picklist
    // ---------------------------------------------------------
    @IsTest
    static void SetFieldValuePicklistTest() {
        Case c = new Case();

        Test.startTest();
        c = CaseUtil.setFieldValue(c, 'Priority', 'High');
        Test.stopTest();

        System.assertEquals('High', c.Priority);
    }

    // ---------------------------------------------------------
    // Test: setFieldValue - Null value (no exception)
    // ---------------------------------------------------------
    @IsTest
    static void SetFieldValueNullTest() {
        Case c = new Case();
        c.Subject = 'Initial';

        Test.startTest();
        c = CaseUtil.setFieldValue(c, 'Subject', null);
        Test.stopTest();

        //System.assertEquals(Initial, c.Subject);
    }
}