/**
 * Base Lightning App Builder datasource listing the URL / text fields of the
 * object the page is for, so record-page components can be configured on any
 * object. Subclasses supply regexes (checked in priority order against the
 * lower-cased API name and label) that decide the default field.
 */
global abstract class RecordTextFieldPicklist extends VisualEditor.DynamicPickList {

    private VisualEditor.DesignTimePageContext context;

    global RecordTextFieldPicklist(VisualEditor.DesignTimePageContext context) {
        this.context = context;
    }

    /** Regexes in priority order; the first field matching the earliest regex is the default. */
    global abstract List<String> defaultFieldPatterns();

    global override VisualEditor.DataRow getDefaultValue() {
        List<Schema.DescribeFieldResult> fields = candidateFields();
        for (String regex : defaultFieldPatterns()) {
            Pattern p = Pattern.compile(regex);
            for (Schema.DescribeFieldResult f : fields) {
                if (p.matcher(f.getName().toLowerCase()).find() || p.matcher(f.getLabel().toLowerCase()).find()) {
                    return row(f);
                }
            }
        }
        return null;
    }

    global override VisualEditor.DynamicPickListRows getValues() {
        VisualEditor.DynamicPickListRows rows = new VisualEditor.DynamicPickListRows();
        for (Schema.DescribeFieldResult f : candidateFields()) {
            rows.addRow(row(f));
        }
        return rows;
    }

    private static VisualEditor.DataRow row(Schema.DescribeFieldResult f) {
        return new VisualEditor.DataRow(f.getLabel() + ' (' + f.getName() + ')', f.getName());
    }

    private List<Schema.DescribeFieldResult> candidateFields() {
        List<Schema.DescribeFieldResult> result = new List<Schema.DescribeFieldResult>();
        if (context == null || String.isBlank(context.entityName)) {
            return result;
        }
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(context.entityName);
        if (objType == null) {
            return result;
        }

        Map<String, Schema.DescribeFieldResult> byLabel = new Map<String, Schema.DescribeFieldResult>();
        for (Schema.SObjectField field : objType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult f = field.getDescribe();
            Schema.DisplayType t = f.getType();
            if (t == Schema.DisplayType.URL || t == Schema.DisplayType.STRING) {
                byLabel.put(f.getLabel().toLowerCase() + '|' + f.getName(), f);
            }
        }
        List<String> keys = new List<String>(byLabel.keySet());
        keys.sort();
        for (String k : keys) {
            result.add(byLabel.get(k));
        }
        return result;
    }
}