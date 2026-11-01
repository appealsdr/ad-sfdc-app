@IsTest
private class LoggerTest {
    
    @TestSetup
    static void setupTestData() {
        // No specific data needed; Logger works with static lists
    }
    
    @IsTest
    static void testLogDebug() {
        // Log a simple debug message
        Logger.logDebug('Test debug message');
        Logger.logDebug('Test debug message with source', 'LoggerTestClass');
        
        // Flush logs to DB
        Test.startTest();
        Logger.flushLogs();
        Test.stopTest();
        
        // Verify logs inserted
        List<Log__c> debugLogs = [SELECT Message__c, LogType__c, ApexClass__c FROM Log__c WHERE LogType__c = :GlobalConstants.DEBUG_TYPE];
        System.assert(debugLogs.size() >= 2, 'At least 2 debug logs should be inserted');
        
    }
    
    @IsTest
    static void testLogException() {
        // Log Exception by passing Exception instance
        try {
            Integer x = 1/0; // causes exception
        } catch (Exception ex) {
            Logger.logException(ex);
            Logger.logException(ex, 'LoggerTestClass');
        }
        
        // Log Exception by passing message
        Logger.logException('Custom exception message');
        Logger.logException('Custom exception message with source', 'LoggerTestClass');
        Logger.logException('Custom exception message with source and class', 'LoggerTestClass', 'LoggerTestClass');
        
        // Flush logs
        Test.startTest();
        Logger.flushLogs();
        Test.stopTest();
        
        // Verify exception logs
        List<Log__c> exceptionLogs = [SELECT Message__c, LogType__c, ApexClass__c FROM Log__c WHERE LogType__c = :GlobalConstants.EXCEPTION_TYPE];
        System.assert(exceptionLogs.size() >= 5, 'At least 5 exception logs should be inserted');
        
        Boolean foundClassLog = false;
        for (Log__c l : exceptionLogs) {
            if (l.ApexClass__c == 'LoggerTestClass') {
                foundClassLog = true;
            }
        }
        System.assert(foundClassLog, 'Exception log with ApexClass should be present');
    }
    
    @IsTest
    static void testFlushLogsEmpty() {
        // Clear logs first
        Logger.flushLogs(); 
        
        // Call flushLogs again when empty (should not throw)
        Test.startTest();
        Logger.flushLogs();
        Test.stopTest();
        
        System.assert(true, 'FlushLogs with empty logs should not fail');
    }
    
    @IsTest
    static void testGetAuraHandledException() {
        Boolean exceptionThrown = false;
        
        try {
            Logger.getAuraHandledException('Test Aura Exception');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.debug('Caught AuraHandledException as expected');
        }
        
        System.assert(exceptionThrown, 'AuraHandledException should have been thrown');
    }
    
    
    
}