/**********************************************************************************************
@author        Pradeep Kumar
@date          2 Sept 2025
@description   This is a constant class
**********************************************************************************************/
public class GlobalConstants {
    /* TriggerFrameworkService Class*/
    //public static final String OBJ_ACCOUNT = 'Account';
    //public static final String OBJ_CONTACT = 'Contact';
    
    /* Logger Class */
    public static final String DEBUG_TYPE = 'Debug';
    public static final String EXCEPTION_TYPE = 'Exception';
    public static final String AES_ENCRYPT = 'AES256';
    public static final String EXECUTION_ID = 'ExId_';
    public static final String CUSTOM_EXCEPTION_METADATA_MESSAGE = 'No Log Management Custom Metadata found';
    public static final String CUSTOM_EXCEPTION_CUSTOMSETTING_MESSAGE = 'No Log Management Custom Setting found';
    public static final List <String> APEX_LIMITS = new List<String>{'QueryLimit','DML Rows Limits',
        'Heap Size Limits','Query Return Limits',
        'Aggregate Queries: ','Callouts', 'CPU Time',
        'DML Statements','Email Invocations',
        'Future Calls', 'Query Locator Rows'
        };
    public static final String COLON_SEPERATOR = ': ';
    public static final String NEW_LINE  = '\n';
    public static final String FORWARD_SLASH  = '/';
    public static final String COMMA_SEPERATOR = ', ';
    public static final String EMPTY_SPACE = '';
    public static final String UNDERSCORE = '_';
    public static final String FIELD_CUSTOMVALIDATION_EXCEPTION   = 'FIELD_CUSTOM_VALIDATION_EXCEPTION';
    public static final String REQUIRED_FIELD_MISSING = 'REQUIRED_FIELD_MISSING';
    public static final String INVALID_RESPONSE_TYPE = 'Invalid response type';     //US #8956
}