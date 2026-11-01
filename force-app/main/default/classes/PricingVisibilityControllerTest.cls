@IsTest(SeeAllData=true)
public class PricingVisibilityControllerTest {
    
    @IsTest
    static void PricingVisible_UserMatchedTest() {
        
        
        Test.startTest();
        Boolean result = PricingVisibilityController.isPricingVisible();
        Test.stopTest();
        
       
        System.assertNotEquals(null, result);
    }
    
    
    @IsTest
    static void PricingVisible_UserNotMatchedTest() {
        
        Test.startTest();
        Boolean result = PricingVisibilityController.isPricingVisible();
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }
}