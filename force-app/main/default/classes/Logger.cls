/******************************************************************************
@author:      Pradeep Kumar
@date:        02 Sep 2025
@description: Logger class for logging Custom Log records.
********************************************************************************/
public class Logger {

    public class CustomException extends Exception {}

    private static final String DEBUGTYPE = GlobalConstants.DEBUG_TYPE;
    private static final String EXCEPTIONTYPE = GlobalConstants.EXCEPTION_TYPE;

    // Static storage for logs during transaction
    private static List<Log__c> logs = new List<Log__c>();
    private static Integer sequence = 0;
    private static String executionId;

    /******************************************************************************
     * Log a debug message
    *******************************************************************************/
    public static void logDebug(String message) {
        createLog(DEBUGTYPE, message, null, null, null);
    }

    public static void logDebug(String message, String source) {
        createLog(DEBUGTYPE, message, source, null, null);
    }

    /******************************************************************************
     * Log an exception
    *******************************************************************************/
    public static void logException(Exception ex) {
        createLog(EXCEPTIONTYPE, ex.getMessage(), ex.getTypeName(), ex, null);
    }

    public static void logException(Exception ex, String source) {
        createLog(EXCEPTIONTYPE, ex.getMessage(), ex.getTypeName(), ex, source);
    }

    public static void logException(String exceptionMessage) {
        CustomException ex = new CustomException(exceptionMessage);
        logException(ex);
    }

    public static void logException(String exceptionMessage, String source) {
        CustomException ex = new CustomException(exceptionMessage);
        createLog(EXCEPTIONTYPE, exceptionMessage, null, ex, source);
    }

    public static void logException(String exceptionMessage, String source, String apexClassName) {
        CustomException ex = new CustomException(exceptionMessage);
        createLog(EXCEPTIONTYPE, exceptionMessage, null, ex, source, apexClassName);
    }

 
    /******************************************************************************
     * Flush all accumulated logs to database (call in finally block)
    *******************************************************************************/
    public static void flushLogs() {
        if (!logs.isEmpty()) {
            try {
                insert logs;
            } catch (Exception e) {
                System.debug('Logger flush failed: ' + e.getMessage());
            } finally {
                logs.clear();
                sequence = 0;
            }
        }
    }

    /******************************************************************************
     * Internal method to create a log
    *******************************************************************************/
    private static void createLog(String logType, String message, String exceptionSource, Exception ex, String apexClassName) {
        createLog(logType, message, exceptionSource, ex, apexClassName, null);
    }

    private static void createLog(String logType, String message, String exceptionSource, Exception ex, String apexClassName, String additionalInfo) {
        String stackTrace = (ex != null) ? ex.getStackTraceString() : GlobalConstants.EMPTY_SPACE;

        Log__c log = new Log__c(
            ExecutionId__c = getExecutionId(),
            StackTrace__c = stackTrace,
            Limits__c = getLimits(),
            Message__c = message,
            LogType__c = logType,
            User__c = UserInfo.getUserId(),
            ExceptionType__c = (ex != null) ? ex.getTypeName() : exceptionSource,
            Sequence__c = sequence + GlobalConstants.UNDERSCORE + getExecutionId(),
            ApexClass__c = apexClassName
        );

        logs.add(log);
        sequence++;
    }

    /******************************************************************************
     * Get unique execution ID
    *******************************************************************************/
    private static String getExecutionId() {
        if (String.isNotBlank(executionId)) {
            return executionId;
        }
        executionId = GlobalConstants.EXECUTION_ID + String.valueOf(System.currentTimeMillis());
        return executionId;
    }

    /******************************************************************************
     * Get Apex limits
    *******************************************************************************/
    private static String getLimits() {
        String limitsStr = '';
        limitsStr += 'Queries:' + Limits.getQueries() + '/' + Limits.getLimitQueries() + '\n';
        limitsStr += 'DMLRows:' + Limits.getDMLRows() + '/' + Limits.getLimitDMLRows() + '\n';
        limitsStr += 'HeapSize:' + Limits.getHeapSize() + '/' + Limits.getLimitHeapSize() + '\n';
        limitsStr += 'QueryRows:' + Limits.getQueryRows() + '/' + Limits.getLimitQueryRows() + '\n';
        limitsStr += 'AggregateQueries:' + Limits.getAggregateQueries() + '/' + Limits.getLimitAggregateQueries() + '\n';
        limitsStr += 'Callouts:' + Limits.getCallouts() + '/' + Limits.getLimitCallouts() + '\n';
        limitsStr += 'CPUTime:' + Limits.getCpuTime() + '/' + Limits.getLimitCpuTime() + '\n';
        limitsStr += 'DMLStatements:' + Limits.getDMLStatements() + '/' + Limits.getLimitDMLStatements() + '\n';
        limitsStr += 'EmailInvocations:' + Limits.getEmailInvocations() + '/' + Limits.getLimitEmailInvocations() + '\n';
        limitsStr += 'FutureCalls:' + Limits.getFutureCalls() + '/' + Limits.getLimitFutureCalls() + '\n';
        limitsStr += 'QueryLocatorRows:' + Limits.getQueryLocatorRows() + '/' + Limits.getLimitQueryLocatorRows() + '\n';
        return limitsStr;
    }

    /******************************************************************************
     * Throw AuraHandledException
    *******************************************************************************/
    public static void getAuraHandledException(String strErrorMessage) {
        AuraHandledException e = new AuraHandledException(strErrorMessage);
        throw e;
    }
}