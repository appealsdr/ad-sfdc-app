@IsTest
private class SignupLinkServiceTest {

    private static final String SECRET =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    @IsTest
    static void generatesSignedLinkAndStoresItOnAccount() {
        Account account = new Account(Name = 'Signup Account');
        insert account;
        Contact contact = new Contact(
            FirstName = 'Signup',
            LastName = 'Contact',
            AccountId = account.Id
        );
        insert contact;
        Opportunity opportunity = new Opportunity(
            Name = 'Signup Opportunity',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert opportunity;
        insert new OpportunityContactRole(
            OpportunityId = opportunity.Id,
            ContactId = contact.Id,
            IsPrimary = true
        );
        opportunity = [
            SELECT Id, AccountId, ContactId
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];
        insert new Appeals_Dr_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            App_Url__c = 'https://app.example.com/',
            Signup_Link_Secret__c = SECRET
        );

        Test.startTest();
        SignupLinkService.generateAndStoreForOpportunityIds(
            new Set<Id>{ opportunity.Id }
        );
        Test.stopTest();

        String link = [
            SELECT Signup_Link__c
            FROM Account
            WHERE Id = :account.Id
        ].Signup_Link__c;
        System.assert(link.startsWith('https://app.example.com/register/link?t='));

        String token = link.substringAfter('?t=');
        List<String> tokenParts = token.split('\\.');
        System.assertEquals(2, tokenParts.size(), 'The token must contain one payload and one signature.');
        System.assert(!tokenParts[0].contains('='), 'The payload must not contain base64 padding.');
        System.assert(!tokenParts[1].contains('='), 'The signature must not contain base64 padding.');

        String expectedSignature = SignupLinkService.base64UrlEncode(
            Crypto.generateMac('HmacSHA256', Blob.valueOf(tokenParts[0]), Blob.valueOf(SECRET))
        );
        System.assertEquals(expectedSignature, tokenParts[1], 'The signature must cover the encoded payload.');

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
            decodeBase64Url(tokenParts[0]).toString()
        );
        System.assertEquals(String.valueOf(account.Id), payload.get('a'));
        System.assertEquals(String.valueOf(contact.Id), payload.get('c'));
        System.assert(payload.containsKey('n'), 'The token must contain a unique nonce.');
        System.assert(payload.containsKey('e'), 'The token must contain an expiry timestamp.');
        System.assert(!payload.containsKey('k'), 'The contract claim is omitted before contract creation.');
    }

    @IsTest
    static void skipsContactThatDoesNotBelongToAccount() {
        Account account = new Account(Name = 'Target Account');
        Account otherAccount = new Account(Name = 'Other Account');
        insert new List<Account>{ account, otherAccount };
        Contact contact = new Contact(LastName = 'Wrong Account', AccountId = otherAccount.Id);
        insert contact;
        Opportunity opportunity = new Opportunity(
            Name = 'Mismatched Contact Opportunity',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert opportunity;
        insert new OpportunityContactRole(
            OpportunityId = opportunity.Id,
            ContactId = contact.Id,
            IsPrimary = true
        );
        opportunity = [
            SELECT Id, AccountId, ContactId
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];
        insert new Appeals_Dr_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            App_Url__c = 'https://app.example.com',
            Signup_Link_Secret__c = SECRET
        );

        Test.startTest();
        SignupLinkService.generateAndStoreForOpportunityIds(
            new Set<Id>{ opportunity.Id }
        );
        Test.stopTest();

        System.assertEquals(null, [
            SELECT Signup_Link__c
            FROM Account
            WHERE Id = :account.Id
        ].Signup_Link__c);
    }

    private static Blob decodeBase64Url(String value) {
        String base64Value = value.replace('-', '+').replace('_', '/');
        while (Math.mod(base64Value.length(), 4) != 0) {
            base64Value += '=';
        }
        return EncodingUtil.base64Decode(base64Value);
    }
}
