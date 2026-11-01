/**
 * Backs the "templateId" App Builder design attribute on drAppAccountProvisioning
 * with a live dropdown of every Email Template in the org, so an admin picks the
 * reset-password notification template when configuring the component instead of
 * hardcoding an Id.
 */
global class DrAppEmailTemplateOptions extends VisualEditor.DynamicPickList {

    global DrAppEmailTemplateOptions(VisualEditor.DesignTimePageContext context) {
    }

    global override VisualEditor.DataRow getDefaultValue() {
        return new VisualEditor.DataRow('-- Select a template --', '');
    }

    global override VisualEditor.DynamicPickListRows getValues() {
        VisualEditor.DynamicPickListRows rows = new VisualEditor.DynamicPickListRows();

        for (EmailTemplate et : [
            SELECT Id, Name, DeveloperName
            FROM EmailTemplate
            WHERE IsActive = true
            ORDER BY Name
        ]) {
            rows.addRow(new VisualEditor.DataRow(et.Name, et.Id));
        }

        return rows;
    }
}