/**
* Email services are automated processes that use Apex classes
* to process the contents, headers, and attachments of inbound
* email.
*/
global class PerformanceNotificationEmailService
implements Messaging.InboundEmailHandler {
    
    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        result.success = false;
        
        try {
            Performance_Notifications__c pn = new Performance_Notifications__c();
            // From Address
            pn.From_Address__c = email.fromAddress;
            // To Address (safe null check)
            pn.To_Address__c = envelope != null ? envelope.toAddress : null;
            // Subject (fallback)
            pn.Subject__c = String.isBlank(email.subject) ? 'No Subject' : email.subject;
            pn.Date__c = System.now().format('dd MMM yyyy HH:mm:ss');
            
            String bodyText;
            
            //System.debug('bodyText' + bodyText);
            
            if (!String.isBlank(email.plainTextBody)) {
                bodyText = email.plainTextBody;
            } else {
                bodyText = email.htmlBody;
            }
            pn.Body__c = bodyText != null ? bodyText.left(32000) : 'No Body';
            
            //Extract ASIN from email body 
            String ASIN = extractASIN(bodyText);
            System.debug('ASIN' + ASIN);
            if (ASIN != null) {
                pn.ASIN__c = ASIN;
            }
            
            
            // Custom Label (expects 'true' or 'false')
            Map<String, Object> mapPNLabel = (Map<String, Object>) JSON.deserializeUntyped(String.valueOf(System.Label.Performance_Notification));
            Boolean In_Testing_Mode = Boolean.ValueOf(mapPNLabel.get('In_Testing_Mode'));
            
            // Hardcoded email
            String hardcodedFromAddress = String.ValueOf(mapPNLabel.get('Test_From_Address'));
            
            // Decide which TO address to use
            String finalFromAddress = In_Testing_Mode
                ? hardcodedFromAddress
                : (email.fromAddress != null ? email.fromAddress : null);
                    
                    Id StoreId = extractIdFromToAddress(finalFromAddress);
            
            if (StoreId != null) {
                pn.Store__c = StoreId;
            }
            
            insert pn;
            result.success = true;
        }
        catch (Exception e) {
            System.debug('Email Service Error: ' + e.getMessage());
        }
        
        return result;
    }
    
    // 🔹 Extract Salesforce Id from To Address
    private static Id extractIdFromToAddress(String toAddress) {
        if (String.isBlank(toAddress)) {
            return null;
        }
        
        // after + sign 15/18 char Salesforce Id
        Pattern p = Pattern.compile('\\+([a-zA-Z0-9]{15,18})@');
        Matcher m = p.matcher(toAddress);
        
        if (m.find()) {
            try {
                return (Id)m.group(1);
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }
    
    
    // Extract ASIN from email body or subject
    private static String extractASIN(String text) {
        if (String.isBlank(text)) {
            return null;
        }
        
        // Convert to uppercase to handle case-insensitivity
        String normalizedText = text.toUpperCase();
        
        // Matches: ASIN: B0B6P34PB9
        Pattern p = Pattern.compile('\\bASIN\\s*[:\\-]?\\s*([A-Z0-9]{10})\\b');
        Matcher m = p.matcher(normalizedText);
        
        if (m.find()) {
            return m.group(1);
        }
        return null;
    }
}