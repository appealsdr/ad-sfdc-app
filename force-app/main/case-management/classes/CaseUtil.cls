public with sharing class CaseUtil {

    // Wrapper for individual field
    public class FieldWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public Object value = null;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean required;
        @AuraEnabled public String cssClass;

        // public FieldWrapper(String apiName, String label, String type, String id) {
        //     this.apiName = apiName;
        //     this.label = label;
        //     this.type = type;
        //     this.id = id;
        // }
    }

    // Wrapper for FieldSet
    public class CaseFieldSetWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public List<FieldWrapper> fields;
        @AuraEnabled public Id recordTypeId;

        // public CaseFieldSetWrapper(String label, String name, List<FieldWrapper> fields, String id) {
        //     this.label = label;
        //     this.name = name;
        //     this.fields = fields;
        //     this.id = id;
        // }
    }

    public static List<CaseFieldSetWrapper> getFieldSetFromCase(String objectApiName) {
        List<CaseFieldSetWrapper> result = new List<CaseFieldSetWrapper>();

        Map<String, Schema.FieldSet> fsMap = Schema.SObjectType.Case.fieldSets.getMap();
        Map<String, Schema.SObjectField> caseFieldsMap = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        integer i = 0;
        for (String fsName : fsMap.keySet()) {
            Schema.FieldSet fs = fsMap.get(fsName);
            List<FieldWrapper> fields = new List<FieldWrapper>();
            integer j = 0;
            for (Schema.FieldSetMember f : fs.getFields()) {
                String apiName = f.getFieldPath();
                Schema.DescribeFieldResult d;

                if (caseFieldsMap.containsKey(apiName)) {
                    d = caseFieldsMap.get(apiName).getDescribe();
                } else {
                    d = null;
                }

                String type = (d != null) ? mapFieldType(d.getType()) : 'text';

                FieldWrapper objFW = new FieldWrapper();
                objFW.id = (j++) +'';
                objFW.label = f.getLabel();
                objFW.apiName = apiName;
                objFW.type = type;
                objFW.required =  f.getRequired();
                objFW.cssClass = f.getRequired() ? 'validateInputField' : '';
                objFW.value = '';
                fields.add(objFW);
            }

            CaseFieldSetWrapper objCF = new CaseFieldSetWrapper();
            objCF.id = (i++) +'';
            objCF.label = fs.getLabel();
            objCF.name = fsName;
            objCF.fields =fields;
            result.add(objCF);
        }

        return result;
    }

    // Map Salesforce types to LWC input types
    private static String mapFieldType(Schema.DisplayType type) {
        switch on type {
            when Currency,
                 Double,
                 Integer,
                 Long,
                 Percent {
                return 'number';
            }
            when Date {
                return 'date';
            }
            when DateTime {
                return 'datetime';
            }
            when Boolean {
                return 'checkbox';
            }
            when Email {
                return 'email';
            }
            when Phone {
                return 'tel';
            }
            when Url {
                return 'url';
            }
            when else {
                return 'text';
            }
        }
    }

    public static Case setFieldValue(Case objCase, String fieldApiName, object rawValue) {
        Schema.DescribeFieldResult dfr = Schema.SObjectType.Case.fields.getMap().get(fieldApiName).getDescribe();

        if (rawValue != null) {
            switch on dfr.getType() {

                when  Currency, Double, Percent {
                    objCase.put(fieldApiName, Decimal.valueOf(String.valueOf(rawValue)));
                }

                when Integer {
                    objCase.put(fieldApiName, Integer.valueOf(String.valueOf(rawValue)));
                }

                when Boolean {
                    objCase.put(fieldApiName, Boolean.valueOf(String.valueOf(rawValue)));
                }

                when Date {
                    objCase.put(fieldApiName, Date.valueOf(String.valueOf(rawValue)));
                }

                when DateTime {
                    objCase.put(fieldApiName, DateTime.valueOf(String.valueOf(rawValue)));
                }

                when else {
                    // Text, Picklist, Email, Phone, etc.
                    objCase.put(fieldApiName, rawValue);
                }
            }
        }

        return objCase;
    }
}