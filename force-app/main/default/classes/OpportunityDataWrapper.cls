public class OpportunityDataWrapper {
public String object_type;
public String action;
public Data data;
public String timestamp;

// Inner class for "data"
public class Data {
    public Customer customer;
    public String link_expiration;
    public String CurrencyIsoCode;
}

// Inner class for "customer"
public class Customer {
    public String Id;
    public String Name;
    Public String PrimaryEmail;
    
    public List<Opportunity> Opportunities;
    public List<Contact> Contacts;
    public List<Store> stores;
}

// Inner class for "Opportunity"
public class Opportunity {
    public String Id;
    public String Name;
    public Decimal Amount;
    public String StageName;
    public Date CloseDate;
    public List<Service> Services;
}

    // ---------------- SERVICE ----------------
public class Service {
    public String serviceId;
    public String serviceName;
    public Date startDate;
    public Date endDate;
    public Decimal months;
    public String storeId;
    public String oppId;
    public Decimal amountPerMonth;
    public String createdById;
    public String description;
    public DateTime createdDateTime;

    public List<RetainerService> RetainerServices;
}

// ---------------- RETAINER SERVICE ----------------
public class RetainerService {
    public String retainerServiceNo;
    public String caseRecordType;
    public String storeOpportunity;
    public String serviceId;
    public Date startDate;
    public Date endDate;
    public Decimal amountPerMonth;
    public Integer totalCase;
    public Decimal numberOfCasesAllowedPerPeriod;
}

// Inner class for "Contact"
public class Contact {
    public String Id;
    public String FirstName;
    public String LastName;
    public String Email;
    public String Phone;
    
}

// Inner class for "Store"
public class Store {
    public String Id;
    public String Name;
    public String SellerId;
    public List<CaseRecord> Cases;
}

// Inner class for "Case"
public class CaseRecord {
public String id;
public String amazonStoreName;
public String areYouCurrentlySellingProductsOrSe;
public String areYouTheOwner;
public String areYouUsingYourTrademarkOnAProduct;
public String areYouWillingToAcknowledgeTheViolation;
public String asin;
public Id assetId;
public String atRiskOfSuspensionDueToOdr;
public String brandDescription;
public String brandDetails;
public String brandName;
public String brandRegistryEmail;
public String brandRegistryPhoneNumber;
public String brieflyExplainHowYouWillBeUsingTh;
public Id businessHoursId;
public String caseNumber;
public String origin;
public Id ownerId;
public String reason;
public Id recordTypeId;
public Id sourceId;
public String category;
public String categoryDuplicateField;
public Boolean isClosedOnCreate;
public String contactEmail;
public String contactFax;
public String contactMobile;
public Id contactId;
public String contactPhone;
public String contactPosition;
public Id createdById;
public Decimal currentIpiScore;
public Date dateAccountWasSuspended;
public Date dateLinkedAccountWasSuspended;
public Datetime closedDate;
public Datetime createdDate;
public Decimal depositUpfront;
public String description;
public String descriptionOfInventory;
public Decimal desiredInventoryLimitInCubicFt;
public String details;
public String doYouHaveATrademark;
public String doYouNeedAnUrgentDisbursementRequest;
public String doYouNeedAnUrgentRemovalOrder;
public String doYouPlanToContinueSellingThisAsin;
public String doesThisNeedToBeExpedited;
public String email;
public Id entitlementId;
public Boolean isEscalated;
public String firstName;
public Date firstUseAnywhereInTheWorld;
public Date firstUseInCommerce;
public Decimal frozenFundsUsd;
public String fulfillmentType;
public String fullDetailsOfLinkedAccountSuspension;
public String fullDetailsOfSuspension;
public String haveYouAppliedForATrademarkBefore;
public String haveYouEverFiledThisTrademarkInOther;
public String haveYouUsedThisNameBefore;
public String impactLevel;
public String individualServiceOptions;
public String comments;
public Decimal inventoryValue;
public String isTheAccountSuspensionLinkedToAnother;
public String isTheIncreaseRequestForTheCurrent;
public String isThereInventoryAtRiskOfDisposal;
public String isYourAccountAtRiskOfDeactivation;
public String language;
public Id lastModifiedById;
public String lastName;
public String linkedAccountSuspensionCategory;
public String listAllOfTheProductsOrServices;
public String milestoneStatus;
public Id accountId;
public String nameOfLinkedSuspendedAccount;
public String nameOrSloganToProtect;
public Id opportunityId;
public String orderId;
public String otherIssues;
public Id parentId;
public String paymentStatus;
public String phoneNumber;
public String pleaseConfirmTheFilingCountry;
public String pleaseSelectTheCountryWhereYouFirst;
public Date pleaseSelectTheDateWhenYouFirstFiled;
public String priority;
public Id productId;
public Decimal quantity;
public String reasonForLinkedAccountSuspension;
public String reasonForLosingApproval;
public String reasonForStorageIncrease;
public String reasonForSuspension;
public String reasonsForAtRiskStatus;
public String relevantAsins;
public String selectFileType;
public Id serviceContractId;
public String serviceName;
public String serviceType;
public Datetime slaExitDate;
public Datetime slaStartDate;
public String status;
public Boolean isStopped;
public Datetime stopStartDate;
public String store;
public String storeName;
public String subject;
public String suspensionCategory;
public String toProtect;
public Decimal totalPrice;
public String type;
public String typeOfInventory;
public String violationCategory;
public String suppliedCompany;
public String suppliedEmail;
public String suppliedName;
public String suppliedPhone;
public String whatIsTheNameOfTheMarkHolder;
public String whatIsYourBusinessName;
public String whatIssuesAreYouExperiencingWithBrand;
public String whatProductsOrServicesDoYouOffer;
public Decimal whatsTheCurrentLsr;
public Decimal whatsTheCurrentOdr;
public Decimal whatsTheCurrentPfcr;
public Decimal whatsTheCurrentVtr;
public String wouldYouLike;
}


// Utility methods
public static OpportunityDataWrapper parse(String json) {
    return (OpportunityDataWrapper) System.JSON.deserialize(json, OpportunityDataWrapper.class);
}

public String toJson() {
    return System.JSON.serializePretty(this);
}
}