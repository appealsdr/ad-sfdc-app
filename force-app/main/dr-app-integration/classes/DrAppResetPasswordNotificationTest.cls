/**
 * Covers DrAppProvisioningController.sendResetPasswordNotification against a
 * real Email Template. Kept out of DrAppProvisioningControllerTest only
 * because inserting the template (a setup object, via System.runAs) alongside
 * a @TestSetup method that also does non-setup DML gets awkward - not because
 * it needs org data. It creates its own template into the running user's
 * personal folder, so it runs fully isolated with SeeAllData=false.
 */
@isTest
private class DrAppResetPasswordNotificationTest {

    @isTest
    static void sendsEmailAndConsumesInvocation() {
        // EmailTemplate is a setup object; mixing its DML with a non-setup
        // object (Account/Contact) in the same transaction throws
        // MIXED_DML_OPERATION regardless of order. System.runAs opens a
        // separate execution context that sidesteps the restriction.
        Id templateId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            templateId = createTemplate();
        }

        Account acct = new Account(Name = 'Notify Test Account');
        insert acct;

        Contact cont = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'jane.doe.notify.test@example.com',
            AccountId = acct.Id
        );
        insert cont;

        Test.startTest();
        // sendResetPasswordNotification wraps Messaging.sendEmail in a
        // try/catch that rethrows as DrAppControllerException on failure,
        // so completing without one is the success signal here.
        DrAppProvisioningController.sendResetPasswordNotification(cont.Id, templateId);
        Test.stopTest();
    }

    @isTest
    static void missingContactIdThrows() {
        Id templateId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            templateId = createTemplate();
        }

        Boolean threw = false;
        try {
            DrAppProvisioningController.sendResetPasswordNotification(null, templateId);
        } catch (DrAppProvisioningController.DrAppControllerException e) {
            threw = true;
        }
        System.assert(threw, 'Expected an exception for a missing contactId.');
    }

    /**
     * Every org-level EmailTemplate folder here is Hidden and rejects new
     * templates even from an admin, so file into the running user's personal
     * template folder instead (FolderId = the user's own Id) — always writable.
     */
    private static Id createTemplate() {
        EmailTemplate template = new EmailTemplate(
            Name = 'Dr App Reset Password Test Template',
            DeveloperName = 'Dr_App_Reset_Password_Test_' + Math.abs(Crypto.getRandomInteger()),
            TemplateType = 'text',
            FolderId = UserInfo.getUserId(),
            IsActive = true,
            Subject = 'Your password was reset',
            Body = 'Hi {!Contact.FirstName}, your Dr App password was reset.'
        );
        insert template;
        return template.Id;
    }
}