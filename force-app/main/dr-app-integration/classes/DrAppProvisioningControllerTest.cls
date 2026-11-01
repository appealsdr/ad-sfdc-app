@isTest
private class DrAppProvisioningControllerTest {

    private class DrAppMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/reset-password')) {
                res.setBody('{"userId":"u-1","username":"jdoe","temporaryPassword":"Temp123!"}');
            } else {
                res.setBody('{"account":{"vuid":"acc-uuid","sfdcAccountId":"001x"},"contact":{"vuid":"user-uuid","sfdcContactId":"003x"},'
                    + '"stores":[{"vuid":"store-uuid","name":"Acme US Store","sfdcStoreId":"a0Xx"}],"username":"jdoe","temporaryPassword":"Temp123!"}');
            }
            return res;
        }
    }

    @TestSetup
    static void setup() {
        // The controller only writes Temp_Password_For_App__c when the running
        // user's FLS allows it (Schema...isUpdateable()). Rather than depending
        // on the Dr_App_Provisioning permission set already being deployed to
        // this org (it may not be, e.g. in a fresh prod deploy), build an
        // equivalent throwaway permission set here so the test is self-contained.
        //
        // It's assigned to a dedicated test user (not the running user) and
        // exercised via System.runAs: newly-inserted FieldPermissions aren't
        // reliably reflected in Schema...isUpdateable() for the *currently
        // running* user within the same test transaction, but System.runAs
        // starts a fresh permission context that picks them up correctly.
        PermissionSet ps = new PermissionSet(
            Name = 'DrApp_Provisioning_Test_' + Math.abs(Crypto.getRandomInteger()),
            Label = 'DrApp Provisioning Test'
        );
        insert ps;

        // Store__c is a custom object - Standard User doesn't get access to it
        // by default the way it does for Account/Contact, so grant it here too
        // since provisionAccount() now queries related Store__c records.
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'Store__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsViewAllRecords = true
        );

        insert new List<FieldPermissions>{
            new FieldPermissions(ParentId = ps.Id, SobjectType = 'Contact', Field = 'Contact.Temp_Password_For_App__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = ps.Id, SobjectType = 'Contact', Field = 'Contact.appealsdoctor_vuid__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = ps.Id, SobjectType = 'Account', Field = 'Account.appealsdoctor_vuid__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = ps.Id, SobjectType = 'Store__c', Field = 'Store__c.Marketplaces__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = ps.Id, SobjectType = 'Store__c', Field = 'Store__c.Seller_ID__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = ps.Id, SobjectType = 'Store__c', Field = 'Store__c.Account__c', PermissionsRead = true, PermissionsEdit = true),
            new FieldPermissions(ParentId = ps.Id, SobjectType = 'Store__c', Field = 'Store__c.appealsdoctor_vuid__c', PermissionsRead = true, PermissionsEdit = true)
        };

        User testUser = TestDataFactory.createUsers(1)[0];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = ps.Id);

        // Account/Contact/Store__c are non-setup objects; inserting them in the
        // same transaction as the PermissionSet/FieldPermissions/PermissionSetAssignment
        // DML above throws MIXED_DML_OPERATION, so they're created separately
        // as the running user via System.runAs.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Dr_App_Api_Setting__c setting = Dr_App_Api_Setting__c.getOrgDefaults();
            setting.Api_Key__c = 'test-key';
            upsert setting;

            Account acct = new Account(Name = 'Test Account', Website = 'https://example.com');
            insert acct;

            Contact cont = new Contact(
                FirstName = 'Jane',
                LastName = 'Doe',
                Email = 'jane.doe@example.com',
                AccountId = acct.Id
            );
            insert cont;

            insert new Store__c(
                Name = 'Acme US Store',
                Account__c = acct.Id,
                Marketplaces__c = 'US;CA',
                Seller_ID__c = 'A1B2C3'
            );
        }
    }

    @isTest
    static void testGetContactsForAccount() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<Contact> contacts = DrAppProvisioningController.getContactsForAccount(acct.Id);
        Test.stopTest();

        System.assertEquals(1, contacts.size(), 'Expected one contact for the account.');
    }

    @isTest
    static void testProvisionAccount() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact cont = [SELECT Id FROM Contact LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE LastName LIKE 'User%' AND Email LIKE 'testuser%' LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        DrAppApiClient.ProvisionResponse res;
        Test.startTest();
        System.runAs(testUser) {
            res = DrAppProvisioningController.provisionAccount(acct.Id, cont.Id);
        }
        Test.stopTest();

        System.assertEquals('Temp123!', res.temporaryPassword);
        System.assertEquals('acc-uuid', res.account.vuid);
        System.assertEquals('user-uuid', res.contact.vuid);
        System.assertEquals(1, res.stores.size());
        System.assertEquals('store-uuid', res.stores[0].vuid);

        Contact updatedContact = [SELECT Temp_Password_For_App__c, appealsdoctor_vuid__c FROM Contact WHERE Id = :cont.Id];
        System.assertEquals('Temp123!', updatedContact.Temp_Password_For_App__c);
        System.assertEquals('user-uuid', updatedContact.appealsdoctor_vuid__c);

        Account updatedAccount = [SELECT appealsdoctor_vuid__c FROM Account WHERE Id = :acct.Id];
        System.assertEquals('acc-uuid', updatedAccount.appealsdoctor_vuid__c);

        Store__c updatedStore = [SELECT appealsdoctor_vuid__c FROM Store__c WHERE Account__c = :acct.Id LIMIT 1];
        System.assertEquals('store-uuid', updatedStore.appealsdoctor_vuid__c);
    }

    @isTest
    static void testResetPassword() {
        Contact cont = [SELECT Id FROM Contact LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE LastName LIKE 'User%' AND Email LIKE 'testuser%' LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new DrAppMock());

        DrAppApiClient.ResetPasswordResponse res;
        Test.startTest();
        System.runAs(testUser) {
            res = DrAppProvisioningController.resetPassword(cont.Id);
        }
        Test.stopTest();

        System.assertEquals('Temp123!', res.temporaryPassword);

        Contact updated = [SELECT Temp_Password_For_App__c FROM Contact WHERE Id = :cont.Id];
        System.assertEquals('Temp123!', updated.Temp_Password_For_App__c);
    }

    @isTest
    static void testProvisionAccountMissingIds() {
        Boolean threw = false;
        try {
            DrAppProvisioningController.provisionAccount(null, null);
        } catch (DrAppProvisioningController.DrAppControllerException e) {
            threw = true;
        }
        System.assert(threw, 'Expected an exception for missing ids.');
    }

    /* =====================================================
       Reset password notification
       (See DrAppResetPasswordNotificationTest for the template-based
       send/attach cases — those need SeeAllData=true to reach a real
       EmailTemplate folder, which can't share a class with @TestSetup.)
    ======================================================*/
    @isTest
    static void testSendResetPasswordNotificationNoTemplateConfigured() {
        Contact cont = [SELECT Id FROM Contact LIMIT 1];

        Boolean threw = false;
        try {
            DrAppProvisioningController.sendResetPasswordNotification(cont.Id, null);
        } catch (DrAppProvisioningController.DrAppControllerException e) {
            threw = true;
            System.assert(e.getMessage().contains('Email template not configured'),
                'Should explain that no template is configured.');
        }
        System.assert(threw, 'Expected an exception when no template is configured.');
    }
}