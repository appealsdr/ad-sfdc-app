@IsTest
public class TestDataFactory {
    
    // Create multiple Accounts
    public static List<Account> createAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
        return accounts;
    }
    
    // Create multiple Contacts related to Accounts
    public static List<Contact> createContacts(List<Account> accounts, Integer countPerAccount) {
        List<Contact> contacts = new List<Contact>();
        for (Account acc : accounts) {
            for (Integer i = 0; i < countPerAccount; i++) {
                contacts.add(new Contact(
                    FirstName = 'Test',
                    LastName = 'Contact ' + i,
                    AccountId = acc.Id
                ));
            }
        }
        insert contacts;
        return contacts;
    }
    
    // Create multiple Cases related to Accounts
    public static List<Case> createCases(List<Account> accounts, Integer countPerAccount) {
        List<Case> cases = new List<Case>();
        for (Account acc : accounts) {
            for (Integer i = 0; i < countPerAccount; i++) {
                cases.add(new Case(
                    AccountId = acc.Id,
                    Subject = 'Test Case ' + i,
                    Status = 'New'
                   
                ));
            }
        }
        insert cases;
        return cases;
    }
    
    // Create Opportunities related to Accounts
    public static List<Opportunity> createOpportunities(List<Account> accounts, Integer countPerAccount) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Account acc : accounts) {
            for (Integer i = 0; i < countPerAccount; i++) {
                opps.add(new Opportunity(
                    Name = 'Test Opportunity ' + i,
                    AccountId = acc.Id,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30)
                ));
            }
        }
        insert opps;
        return opps;
    }
    
    // Create a PricebookEntry on the standard Pricebook at the given unit price
    public static PricebookEntry createStandardPricebookEntry(Decimal unitPrice) {
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;
        Id standardPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = prod.Id,
            UnitPrice = unitPrice,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }

    // Create OpportunityLineItems on an Opportunity using the given PricebookEntry
    public static List<OpportunityLineItem> createOpportunityLineItems(Id opportunityId, PricebookEntry pbe, Integer count) {
        List<OpportunityLineItem> lineItems = new List<OpportunityLineItem>();
        for (Integer i = 0; i < count; i++) {
            lineItems.add(new OpportunityLineItem(
                OpportunityId = opportunityId,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = pbe.UnitPrice
            ));
        }
        insert lineItems;
        return lineItems;
    }

    // Create Case_Team_Member__c records
    public static List<Case_Team_Member__c> createCaseTeamMembers(List<Case> cases, List<User> users) {
        List<Case_Team_Member__c> teamMembers = new List<Case_Team_Member__c>();
        Integer uIndex = 0;
        for (Case c : cases) {
            User u = users[uIndex];
            teamMembers.add(new Case_Team_Member__c(
                Case__c = c.Id,
                User__c = u.Id
            ));
            uIndex++;
        }
        insert teamMembers;
        return teamMembers;
    }
    
    // Create Users for testing
    public static List<User> createUsers(Integer count) {
        List<User> users = new List<User>();
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        for (Integer i = 0; i < count; i++) {
            users.add(new User(
                FirstName = 'Test',
                LastName = 'User ' + i,
                Email = 'testuser' + i + '@example.com',
                Username = 'testuser' + i + '@example.com.' + System.currentTimeMillis(),
                Alias = 'tuser' + i,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = p.Id,
                LanguageLocaleKey = 'en_US'
            ));
        }
        insert users;
        return users;
    }
    
     // =========================
    //  NEW METHODS FOR SERVICES FORM
    // =========================

    // Create Store__c records for an Opportunity
    public static List<Store__c> createStores(Id opportunityId, Integer count) {
        List<Store__c> stores = new List<Store__c>();
        for (Integer i = 0; i < count; i++) {
            stores.add(new Store__c(
                Name = 'Test Store ' + i,
                Opportunity__c = opportunityId,
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addMonths(3),
                Pricing__c = 7000
            ));
        }
        insert stores;
        return stores;
    }
    
     // Create Retainer_Service__c records for Stores
    public static List<Service__c> createServices(String storeId, Integer count) {
        List<Service__c> services = new List<Service__c>();
        for (Integer i = 0; i < count; i++) {
            services.add(new Service__c(
                Name = 'Test Service ' + i,
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addMonths(3),
                Contract_For_Month__c = 3,
                Store_Services__c = storeId
            ));
        }
        insert services;
        return services;
    }

    // Create Retainer_Service__c records for Stores
    public static List<Retainer_Service__c> createRetainerServices(String serviceId, Integer count ) {
        List<Retainer_Service__c> listRS = new List<Retainer_Service__c>();
        for (Integer i = 0; i < count; i++) {
                listRS.add(new Retainer_Service__c(
                    Service__c =serviceId,
                    Case_Record_Type__c = 'Account At Risk of Deactivation',
                    Number_Of_Cases_Allowed_Per_Period__c = 10,
                    Start_Date__c = Date.today().addMonths(-3),
                    End_Date__c = Date.today().addMonths(3)
                ));
            }
        
        insert listRS;
        return listRS;
    }

    // Convenience method: Create Store + Retainer Services together
    /*public static void createStoreWithRetainerServices(
        Id opportunityId,
        Integer storeCount,
        Integer servicesPerStore
    ) {
        List<Store__c> stores = createStores(opportunityId, storeCount);
        createRetainerServices(stores, servicesPerStore);
    }*/
}