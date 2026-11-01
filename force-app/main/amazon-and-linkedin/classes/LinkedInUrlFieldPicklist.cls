/**
 * Lightning App Builder datasource for linkedInProfileCard's "LinkedIn URL Field"
 * property. Defaults to e.g. LinkedIn_URL__c over fields that merely mention
 * LinkedIn (Decision_Maker_LinkedIn__c).
 */
global class LinkedInUrlFieldPicklist extends RecordTextFieldPicklist {

    global LinkedInUrlFieldPicklist(VisualEditor.DesignTimePageContext context) {
        super(context);
    }

    global override List<String> defaultFieldPatterns() {
        return new List<String>{ '^linkedin', 'linked\\s?in' };
    }
}