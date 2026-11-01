/**
 * LWC-facing controller for the Dr App account/contact provisioning and
 * password reset flows exposed on the Account record page. Wraps
 * DrAppApiClient and persists the one-time temporary password onto the
 * selected Contact (Contact.Temp_Password_For_App__c).
 */
public with sharing class DrAppProvisioningController {

    public class DrAppControllerException extends Exception {}

    @AuraEnabled(cacheable=true)
    public static List<Contact> getContactsForAccount(Id accountId) {
        if (accountId == null) {
            throw new DrAppControllerException('accountId is required.');
        }
        return [
            SELECT Id, FirstName, LastName, Email, Phone
            FROM Contact
            WHERE AccountId = :accountId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ];
    }

    @AuraEnabled
    public static DrAppApiClient.ProvisionResponse provisionAccount(Id accountId, Id contactId) {
        if (accountId == null || contactId == null) {
            throw new DrAppControllerException('accountId and contactId are required.');
        }

        List<Account> accounts = [
            SELECT Id, Name, Website, Phone
            FROM Account
            WHERE Id = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new DrAppControllerException('Account not found.');
        }

        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, Phone
            FROM Contact
            WHERE Id = :contactId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            throw new DrAppControllerException('Contact not found.');
        }

        Account acct = accounts[0];
        Contact cont = contacts[0];

        if (String.isBlank(cont.Email)) {
            throw new DrAppControllerException('Selected contact has no email address.');
        }

        List<Store__c> stores = [
            SELECT Id, Name, Marketplaces__c, Seller_ID__c
            FROM Store__c
            WHERE Account__c = :accountId
            WITH SECURITY_ENFORCED
        ];

        DrAppApiClient.ProvisionRequest reqBody = new DrAppApiClient.ProvisionRequest();
        reqBody.companyName = acct.Name;
        reqBody.firstName = cont.FirstName;
        reqBody.lastName = cont.LastName;
        reqBody.email = cont.Email;
        reqBody.phone = String.isNotBlank(cont.Phone) ? cont.Phone : acct.Phone;
        reqBody.website = acct.Website;
        reqBody.sfdcAccountId = accountId;
        reqBody.sfdcContactId = contactId;
        reqBody.stores = buildStoreRequests(stores);

        DrAppApiClient.ProvisionResponse res = DrAppApiClient.provisionAccount(reqBody);

        if (String.isNotBlank(res.temporaryPassword)) {
            savePassword(contactId, res.temporaryPassword);
        }

        saveVuids(accountId, contactId, stores, res);

        return res;
    }

    private static List<DrAppApiClient.StoreRequest> buildStoreRequests(List<Store__c> stores) {
        List<DrAppApiClient.StoreRequest> storeRequests = new List<DrAppApiClient.StoreRequest>();
        for (Store__c store : stores) {
            DrAppApiClient.StoreRequest sr = new DrAppApiClient.StoreRequest();
            sr.name = store.Name;
            sr.marketplaces = store.Marketplaces__c;
            sr.sellerId = store.Seller_ID__c;
            sr.sfdcStoreId = store.Id;
            storeRequests.add(sr);
        }
        return storeRequests;
    }

    /** Persists the app-side vuid returned for the Account, Contact, and each synced Store. */
    private static void saveVuids(Id accountId, Id contactId, List<Store__c> stores, DrAppApiClient.ProvisionResponse res) {
        if (res.account != null && String.isNotBlank(res.account.vuid)
            && Schema.sObjectType.Account.fields.appealsdoctor_vuid__c.isUpdateable()) {
            update new Account(Id = accountId, appealsdoctor_vuid__c = res.account.vuid);
        }

        if (res.contact != null && String.isNotBlank(res.contact.vuid)
            && Schema.sObjectType.Contact.fields.appealsdoctor_vuid__c.isUpdateable()) {
            update new Contact(Id = contactId, appealsdoctor_vuid__c = res.contact.vuid);
        }

        if (res.stores != null && !stores.isEmpty()
            && Schema.sObjectType.Store__c.fields.appealsdoctor_vuid__c.isUpdateable()) {
            Map<String, Id> storeIdByName = new Map<String, Id>();
            for (Store__c store : stores) {
                if (String.isNotBlank(store.Name)) {
                    storeIdByName.put(store.Name, store.Id);
                }
            }

            List<Store__c> storesToUpdate = new List<Store__c>();
            for (DrAppApiClient.StoreResult storeRes : res.stores) {
                Id storeId = storeIdByName.get(storeRes.name);
                if (storeId != null && String.isNotBlank(storeRes.vuid)) {
                    storesToUpdate.add(new Store__c(Id = storeId, appealsdoctor_vuid__c = storeRes.vuid));
                }
            }
            if (!storesToUpdate.isEmpty()) {
                update storesToUpdate;
            }
        }
    }

    @AuraEnabled
    public static DrAppApiClient.ResetPasswordResponse resetPassword(Id contactId) {
        if (contactId == null) {
            throw new DrAppControllerException('contactId is required.');
        }

        DrAppApiClient.ResetPasswordResponse res = DrAppApiClient.resetPassword(contactId);

        if (String.isNotBlank(res.temporaryPassword)) {
            savePassword(contactId, res.temporaryPassword);
        }

        return res;
    }

    private static void savePassword(Id contactId, String temporaryPassword) {
        if (!Schema.sObjectType.Contact.fields.Temp_Password_For_App__c.isUpdateable()) {
            return;
        }
        Contact cont = new Contact(Id = contactId, Temp_Password_For_App__c = temporaryPassword);
        update cont;
    }

    /**
     * Notifies the Contact that their password was reset, using the Email
     * Template configured on the drAppAccountProvisioning component (App
     * Builder "templateId" property). Sends to the address on the Contact
     * record and logs the email on that Contact's activity history.
     */
    @AuraEnabled
    public static void sendResetPasswordNotification(Id contactId, Id templateId) {
        if (contactId == null) {
            throw new DrAppControllerException('contactId is required.');
        }
        if (templateId == null) {
            throw new DrAppControllerException('Email template not configured.');
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTemplateId(templateId);
        mail.setTargetObjectId(contactId);
        mail.setSaveAsActivity(true);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (EmailException e) {
            throw new DrAppControllerException('Failed to send reset password notification: ' + e.getMessage());
        }
    }
}