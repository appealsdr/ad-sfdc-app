/** Flow-invocable wrapper around DrAppApiClient.resetPassword. */
public with sharing class DrAppApiFlowResetPassword {

    @InvocableMethod(label='DrApp: Reset Password' description='Forces a password reset for the Dr App user linked to a Contact.')
    public static List<DrAppApiClient.FlowResetPasswordOutput> resetPasswordFlow(List<Id> contactIds) {
        List<DrAppApiClient.FlowResetPasswordOutput> results = new List<DrAppApiClient.FlowResetPasswordOutput>();
        for (Id contactId : contactIds) {
            DrAppApiClient.ResetPasswordResponse res = DrAppApiClient.resetPassword(contactId);

            DrAppApiClient.FlowResetPasswordOutput out = new DrAppApiClient.FlowResetPasswordOutput();
            out.userId = res.userId;
            out.username = res.username;
            out.temporaryPassword = res.temporaryPassword;
            results.add(out);
        }
        return results;
    }
}