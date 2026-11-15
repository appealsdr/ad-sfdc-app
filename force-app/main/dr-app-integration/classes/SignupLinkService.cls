/******************************************************************************
@description: Generates signed, single-use customer signup links for the web app.
******************************************************************************/
public with sharing class SignupLinkService {

    private static final Integer LINK_LIFETIME_SECONDS = 14 * 24 * 60 * 60;
    private static final String REGISTER_PATH = '/register/link?t=';

    /**
     * Generates a link for each eligible Opportunity and stores it on the
     * related Account. An Opportunity is eligible when it has an Account and a
     * Contact that belongs to that Account, and the web app settings are present.
     */
    public static void generateAndStoreForOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        Appeals_Dr_Setting__c settings = Appeals_Dr_Setting__c.getInstance();
        if (settings == null || String.isBlank(settings.App_Url__c)
                || String.isBlank(settings.Signup_Link_Secret__c)) {
            return;
        }

        List<Opportunity> opportunities = [
            SELECT Id, AccountId, ContactId
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        Set<Id> contactIds = new Set<Id>();
        for (Opportunity opportunity : opportunities) {
            if (opportunity.AccountId != null && opportunity.ContactId != null) {
                contactIds.add(opportunity.ContactId);
            }
        }
        if (contactIds.isEmpty()) {
            return;
        }

        Map<Id, Contact> contactsById = new Map<Id, Contact>([
            SELECT Id, AccountId
            FROM Contact
            WHERE Id IN :contactIds
        ]);

        Map<Id, Account> accountsToUpdate = new Map<Id, Account>();
        for (Opportunity opportunity : opportunities) {
            Contact contact = contactsById.get(opportunity.ContactId);
            if (opportunity.AccountId == null || contact == null
                    || contact.AccountId != opportunity.AccountId) {
                continue;
            }

            accountsToUpdate.put(opportunity.AccountId, new Account(
                Id = opportunity.AccountId,
                Signup_Link__c = buildSignupLink(
                    opportunity.AccountId,
                    contact.Id,
                    null,
                    settings.App_Url__c,
                    settings.Signup_Link_Secret__c
                )
            ));
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate.values();
        }
    }

    /**
     * Generates the signed checkout/signup URL for unprovisioned Accounts after
     * their Service Contract has been created. The contract claim lets the app
     * resume checkout immediately after registration.
     */
    public static void generateAndStoreCheckoutLinksForOpportunityIds(
            Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        Appeals_Dr_Setting__c settings = Appeals_Dr_Setting__c.getInstance();
        if (settings == null || String.isBlank(settings.App_Url__c)
                || String.isBlank(settings.Signup_Link_Secret__c)) {
            return;
        }

        List<Opportunity> opportunities = [
            SELECT Id, AccountId, ContactId, Account.appealsdoctor_vuid__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];
        Set<Id> contactIds = new Set<Id>();
        for (Opportunity opportunity : opportunities) {
            if (opportunity.AccountId != null && opportunity.ContactId != null
                    && String.isBlank(opportunity.Account.appealsdoctor_vuid__c)) {
                contactIds.add(opportunity.ContactId);
            }
        }
        if (contactIds.isEmpty()) {
            return;
        }

        Map<Id, Contact> contactsById = new Map<Id, Contact>([
            SELECT Id, AccountId
            FROM Contact
            WHERE Id IN :contactIds
        ]);
        Map<Id, ServiceContract> contractByOpportunityId =
            new Map<Id, ServiceContract>();
        for (ServiceContract contractRecord : [
            SELECT Id, Opportunity__c
            FROM ServiceContract
            WHERE Opportunity__c IN :opportunityIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!contractByOpportunityId.containsKey(contractRecord.Opportunity__c)) {
                contractByOpportunityId.put(contractRecord.Opportunity__c, contractRecord);
            }
        }

        Map<Id, Account> accountsToUpdate = new Map<Id, Account>();
        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        List<ServiceContract> contractsToUpdate = new List<ServiceContract>();
        for (Opportunity opportunity : opportunities) {
            Contact contact = contactsById.get(opportunity.ContactId);
            ServiceContract contractRecord = contractByOpportunityId.get(opportunity.Id);
            if (opportunity.AccountId == null || contact == null
                    || contact.AccountId != opportunity.AccountId
                    || contractRecord == null
                    || !String.isBlank(opportunity.Account.appealsdoctor_vuid__c)) {
                continue;
            }

            String checkoutUrl = buildSignupLink(
                opportunity.AccountId,
                contact.Id,
                contractRecord.Id,
                settings.App_Url__c,
                settings.Signup_Link_Secret__c
            );
            accountsToUpdate.put(opportunity.AccountId, new Account(
                Id = opportunity.AccountId,
                Signup_Link__c = checkoutUrl
            ));
            opportunitiesToUpdate.add(new Opportunity(
                Id = opportunity.Id,
                Checkout_URL__c = checkoutUrl
            ));
            contractsToUpdate.add(new ServiceContract(
                Id = contractRecord.Id,
                Checkout_URL__c = checkoutUrl
            ));
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate.values();
        }
        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
        if (!contractsToUpdate.isEmpty()) {
            update contractsToUpdate;
        }
    }

    @TestVisible
    private static String buildSignupLink(
            Id accountId,
            Id contactId,
            Id serviceContractId,
            String appUrl,
            String secret) {
        Map<String, Object> body = new Map<String, Object>{
            'a' => String.valueOf(accountId),
            'c' => String.valueOf(contactId),
            'n' => EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16),
            'e' => (DateTime.now().getTime() / 1000) + LINK_LIFETIME_SECONDS
        };
        if (serviceContractId != null) {
            body.put('k', String.valueOf(serviceContractId));
        }

        String payload = base64UrlEncode(Blob.valueOf(JSON.serialize(body)));
        Blob signature = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(payload),
            Blob.valueOf(secret)
        );

        String normalizedAppUrl = appUrl.trim();
        while (normalizedAppUrl.endsWith('/')) {
            normalizedAppUrl = normalizedAppUrl.substring(0, normalizedAppUrl.length() - 1);
        }
        return normalizedAppUrl + REGISTER_PATH + payload + '.' + base64UrlEncode(signature);
    }

    @TestVisible
    private static String base64UrlEncode(Blob value) {
        return EncodingUtil.base64Encode(value)
            .replace('+', '-')
            .replace('/', '_')
            .replace('=', '');
    }
}
