/** Flow-invocable wrapper around DrAppApiClient.provisionAccount. */
public with sharing class DrAppApiFlowProvision {

    @InvocableMethod(label='DrApp: Provision Account' description='Creates a Dr App account/user and returns a one-time temp password.')
    public static List<DrAppApiClient.FlowProvisionOutput> provisionAccountFlow(List<DrAppApiClient.FlowProvisionInput> inputs) {
        List<DrAppApiClient.FlowProvisionOutput> results = new List<DrAppApiClient.FlowProvisionOutput>();
        for (DrAppApiClient.FlowProvisionInput input : inputs) {
            DrAppApiClient.ProvisionRequest reqBody = new DrAppApiClient.ProvisionRequest();
            reqBody.companyName = input.companyName;
            reqBody.firstName = input.firstName;
            reqBody.lastName = input.lastName;
            reqBody.email = input.email;
            reqBody.phone = input.phone;
            reqBody.website = input.website;
            reqBody.sfdcAccountId = input.sfdcAccountId;
            reqBody.sfdcContactId = input.sfdcContactId;

            DrAppApiClient.ProvisionResponse res = DrAppApiClient.provisionAccount(reqBody);

            DrAppApiClient.FlowProvisionOutput out = new DrAppApiClient.FlowProvisionOutput();
            if (res.account != null) {
                out.accountVuid = res.account.vuid;
                out.sfdcAccountId = res.account.sfdcAccountId;
            }
            if (res.contact != null) {
                out.contactVuid = res.contact.vuid;
                out.sfdcContactId = res.contact.sfdcContactId;
            }
            out.username = res.username;
            out.temporaryPassword = res.temporaryPassword;
            results.add(out);
        }
        return results;
    }
}