/**
 * Calls the Dr App provisioning/reset API (app-side endpoints, not Salesforce's
 * own Account/Contact objects). Set up a Named Credential called "DrApp_API"
 * pointing at the app's base URL, with the bearer API key stored as an
 * External Credential / custom header (or hardcode it in a Custom Metadata
 * / Protected Custom Setting — do NOT hardcode the raw key in Apex source).
 *
 * Named Credential setup (Setup > Named Credentials > New):
 *   Label / Name:      DrApp_API
 *   URL:                https://<your-app-host>
 *   Identity Type:      Named Principal
 *   Authentication:     Custom (no auth) — the Authorization header is added
 *                        manually below from a protected custom setting, OR
 *                        configure a Named Credential "Custom Header" with
 *                        Authorization: Bearer <key> if your org supports it.
 */
public with sharing class DrAppApiClient {

    public class DrAppApiException extends Exception {}

    public class ProvisionRequest {
        public String companyName;
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String website;
        public String sfdcAccountId;
        public String sfdcContactId;
        public List<StoreRequest> stores;
    }

    public class StoreRequest {
        public String name;
        public String marketplaces;
        public String sellerId;
        public String sfdcStoreId;
    }

    public class ProvisionResponse {
        public AccountResult account;
        public ContactResult contact;
        public List<StoreResult> stores;
        public String username;
        public String temporaryPassword;
    }

    public class AccountResult {
        public String vuid;
        public String sfdcAccountId;
    }

    public class ContactResult {
        public String vuid;
        public String sfdcContactId;
    }

    public class StoreResult {
        public String vuid;
        public String name;
        public String sfdcStoreId;
    }

    public class ResetPasswordResponse {
        public String userId;
        public String username;
        public String temporaryPassword;
    }

    private static final String NAMED_CREDENTIAL = 'callout:DrApp_API';

    /** Fetch the raw bearer key from a Protected Custom Setting. Never log this value. */
    private static String getApiKey() {
        Dr_App_Api_Setting__c setting = Dr_App_Api_Setting__c.getInstance();
        if (setting == null || String.isBlank(setting.Api_Key__c)) {
            throw new DrAppApiException('DrApp API key is not configured (Dr_App_Api_Setting__c.Api_Key__c).');
        }
        return setting.Api_Key__c;
    }

    private static HttpRequest buildRequest(String path, String method) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + path);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + getApiKey());
        req.setTimeout(20000);
        return req;
    }

    private static HttpResponse send(HttpRequest req) {
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() >= 400) {
            throw new DrAppApiException(
                'DrApp API error (' + res.getStatusCode() + '): ' + res.getBody()
            );
        }
        return res;
    }

    /**
     * Creates a new Account + user in the app (and mirrors it back to a
     * Salesforce Account/Contact on the app side). Returns the one-time
     * temporary password — persist or send it immediately, it cannot be
     * retrieved again.
     */
    public static ProvisionResponse provisionAccount(ProvisionRequest reqBody) {
        if (String.isBlank(reqBody.companyName) || String.isBlank(reqBody.lastName) || String.isBlank(reqBody.email)) {
            throw new DrAppApiException('companyName, lastName, and email are required.');
        }

        HttpRequest req = buildRequest('/api/sfdc/provision', 'POST');
        req.setBody(JSON.serialize(reqBody, true));

        HttpResponse res = send(req);
        return (ProvisionResponse) JSON.deserialize(res.getBody(), ProvisionResponse.class);
    }

    /**
     * Forces a password reset for the local user linked to the given
     * Salesforce Contact Id. Invalidates existing sessions on the app side.
     */
    public static ResetPasswordResponse resetPassword(Id contactId) {
        if (contactId == null) {
            throw new DrAppApiException('contactId is required.');
        }

        HttpRequest req = buildRequest('/api/sfdc/contacts/' + contactId + '/reset-password', 'POST');

        HttpResponse res = send(req);
        return (ResetPasswordResponse) JSON.deserialize(res.getBody(), ResetPasswordResponse.class);
    }

    // ---- Flow-invocable wrapper types (used by DrAppApiFlowProvision / DrAppApiFlowResetPassword) ----

    public class FlowProvisionInput {
        @InvocableVariable(required=true) public String companyName;
        @InvocableVariable public String firstName;
        @InvocableVariable(required=true) public String lastName;
        @InvocableVariable(required=true) public String email;
        @InvocableVariable public String phone;
        @InvocableVariable public String website;
        @InvocableVariable public String sfdcAccountId;
        @InvocableVariable public String sfdcContactId;
    }

    public class FlowProvisionOutput {
        @InvocableVariable public String accountVuid;
        @InvocableVariable public String sfdcAccountId;
        @InvocableVariable public String contactVuid;
        @InvocableVariable public String sfdcContactId;
        @InvocableVariable public String username;
        @InvocableVariable public String temporaryPassword;
    }

    public class FlowResetPasswordOutput {
        @InvocableVariable public String userId;
        @InvocableVariable public String username;
        @InvocableVariable public String temporaryPassword;
    }
}