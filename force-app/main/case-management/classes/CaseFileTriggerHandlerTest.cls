@isTest
private class CaseFileTriggerHandlerTest {
    @TestSetup
    static void setup() {
        Case c = new Case(Subject = 'Update Test');
        insert c;
        Case_File__c cf = new Case_File__c(
            Case__c = c.Id,
            File_Name__c = 'test.pdf'
        );
        insert cf;
    }
    
    @isTest
    static void testUpdate() {
        Case_File__c file =[SELECT Id, File_Name__c FROM Case_File__c LIMIT 1];
        system.debug('file.File_Name__c before : '+file.File_Name__c);        
        test.startTest();
        file.File_Name__c = file.File_Name__c+'01';
        update file;
        system.debug('file.File_Name__c after : '+file.File_Name__c);  
        test.stopTest();
    }
     @isTest
    static void testBypassMethod() {

        // Ensure clean state
        TriggerFrameworkService.clearAllBypasses();

        String handlerName = 'CaseFileTriggerHandler';

        // Call bypass method
        TriggerFrameworkService.bypass(handlerName);

        // Validate handler is bypassed
        System.assertEquals(
            true,
            TriggerFrameworkService.isBypassed(handlerName),
            'bypass() should add handler to bypassedHandlers'
        );

        // Now test clearBypass()
        TriggerFrameworkService.clearBypass(handlerName);

        System.assertEquals(
            false,
            TriggerFrameworkService.isBypassed(handlerName),
            'clearBypass() should remove handler from bypassedHandlers'
        );

        // Test clearAllBypasses()
        TriggerFrameworkService.bypass(handlerName);
        TriggerFrameworkService.clearAllBypasses();

        System.assertEquals(
            false,
            TriggerFrameworkService.isBypassed(handlerName),
            'clearAllBypasses() should remove all bypasses'
        );
    }
  
}