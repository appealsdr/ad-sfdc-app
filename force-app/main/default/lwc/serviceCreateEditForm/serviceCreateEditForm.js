import { LightningElement, api, wire } from "lwc";
import {ShowToastEvent} from 'lightning/platformShowToastEvent';
import LightningConfirm from "lightning/confirm";
import { getObjectInfo, getPicklistValuesByRecordType } from "lightning/uiObjectInfoApi";
import SERVICE_OBJECT from "@salesforce/schema/Service__c";
import  RETAINER_SERVICE_OBJECT from "@salesforce/schema/Retainer_Service__c";
import * as  SHARED_JAVASCRIPT_CODE from "c/ciSharedJavascriptCode";

const  formatRetainerService = {
    "index" : 1,
    "id": undefined,
    "caseRecordType": "",
    "numberOfCasesAllowedPerPeriod": undefined,
    "amountPerMonth": undefined,
    "month" : undefined,
    "year" : undefined,
    "startDate" : "",
    "endDate" : "",
    "showDeleteButton" : false, 
    "totalCaseOfContractMonth" : undefined
}

const formatJSOnService = {
    "index" : 1,
    "serviceId": "",
    "storeId": "",
    "storeName": "",
    "contractForMonth" : undefined,
    "startDate" : "",
    "endDate" : "",
    "contractLength": "",
    "retainerPeriod": "",
    "price": undefined,
    "swithStoreSection" : true,
    "showDeleteButton" : false,  
    "retainerServices": [
        {
            ...formatRetainerService
        }
    ]
};

export default class ServiceCreateEditForm extends LightningElement {
    @api recordId;
	@api objectApiName;
    serviceRtId; 
    retainerServiceRtId;
    @api actionFor = 'create';
    
    @api selectedStoreRecords = [];
    retainerServiceIdsForDelete = [];
    listWrapServices =  [];
    @api listWrapServicesCopy =  [];
    caseRecordType__options = [];
    contractLength_options = [];
    retainerPeriod_options = [];

    serviceHeader = {};
    retainerServicesHeader = [];

    swithServiceHeader = true;

    get getHeader() {
        return this.actionFor === 'create' ? "Create Retainer" : "Update Retainer";
    }

    get isActionForCreate() {
        return this.actionFor && this.actionFor === 'create';
    }

    get showDeleteButtonForRsHeader() {
        return this.retainerServicesHeader?.length > 1;
    }

    get isDisbleApplyToAllBtn() {
        return this.retainerServicesHeader?.length == 0;
    }

     
    @wire(getObjectInfo, { objectApiName: SERVICE_OBJECT })
    receiptObjectInfo({ data, error }) {
        console.log('getObjectInfo: data==>',data);
        if (data) {
            this.serviceRtId = data.defaultRecordTypeId;
            console.log('this.serviceRtId==>',this.serviceRtId);
        } else if (error) {
            console.error('Error getting help text', error);
        }
    }

    @wire(getObjectInfo, { objectApiName: RETAINER_SERVICE_OBJECT })
    receiptObjectInfo({ data, error }) {
        console.log('RS: getObjectInfo: data==>',data);
        if (data) {
            this.retainerServiceRtId = data.defaultRecordTypeId;
            console.log('this.retainerServiceRtId==>',this.retainerServiceRtId);
        } else if (error) {
            console.error('Error getting help text', error);
        }
    }

    @wire(getPicklistValuesByRecordType, {
        objectApiName: SERVICE_OBJECT,
        recordTypeId: '$serviceRtId',
    })
    wirePicklistService({ error, data }) {
         if (!this.serviceRtId) {
            return;
        }
        console.log('Service Access Picklist data==>', data);
        if (data) { 
            let contractLength_options = data.picklistFieldValues.Contract_Length__c.values.map(val => ({
                label: val.label,
                value: val.value
            })); 

            let retainerPeriod_options = data.picklistFieldValues.Retainer_Period__c.values.map(val => ({
                label: val.label,
                value: val.value
            })); 

            this.contractLength_options = contractLength_options;
            this.retainerPeriod_options = retainerPeriod_options;
           
            console.log('refrenceType_options==>', refrenceType_options);
             console.log('adjustmentAmount_options==>', adjustmentAmount_options);
        }
        else if (error) {
            console.log('error==>', error);
        }
    }

    @wire(getPicklistValuesByRecordType, {
        objectApiName: RETAINER_SERVICE_OBJECT,
        recordTypeId: '$retainerServiceRtId',
    })
    wirePicklistRetainerService({ error, data }) {
         if (!this.retainerServiceRtId) {
            return;
        }
        console.log('Retainer Service Access Picklist data==>', data);
        if (data?.picklistFieldValues?.Case_Record_Type__c) { 
            let caseRecordType__options = data.picklistFieldValues.Case_Record_Type__c.values.map(val => ({
                label: val.label,
                value: val.value
            })); 
            this.caseRecordType__options = caseRecordType__options;
            console.log('caseRecordType__options==>', caseRecordType__options);
        }
        else if (error) {
            console.log('error==>', error);
        }
    }
    
    
    connectedCallback() {
        if (this.listWrapServicesCopy && this.listWrapServicesCopy.length > 0) {
            this.listWrapServices = JSON.parse(JSON.stringify(this.listWrapServicesCopy));
        } 
        //else {
        //     this.buildListWrapServices();
        // }
        if (this.actionFor !== 'update') {
            this.buildListWrapServices();
            this.buildRsHeader();

        }
        console.log('SCE:this.listWrapServices==>',this.listWrapServices);
    }

    buildListWrapServices() {
		const existingMap = new Map();

		// Index existing wrap cases by storeId
		(this.listWrapServices || []).forEach(wrap => {
			existingMap.set(wrap.storeId, wrap);
		});

		const listWrapServices = (this.selectedStoreRecords || []).map((item, index) => {
			
            if (existingMap.has(item.Id)) {
				const existingWrap = { ...existingMap.get(item.Id) };
				existingWrap.index = index + 1; 
				console.log('existingWrap==>',existingWrap);
				return existingWrap;
			}

			// Else → create new
            let objWrapService = {...formatJSOnService}
            objWrapService.index = index + 1;   
            objWrapService.storeId = item.Id;  
            objWrapService.storeName = item.Name;

			return objWrapService;
		});

		this.listWrapServices = listWrapServices;
        console.log('this.listWrapServices==>',this.listWrapServices);
    }

    buildRsHeader() {
        const currentHeaders = Array.isArray(this.retainerServicesHeader)
            ? [...this.retainerServicesHeader]
            : [];

        // Deep clone to avoid reference issues
        const objWrapRS = JSON.parse(JSON.stringify(formatRetainerService));

        objWrapRS.index = currentHeaders.length + 1;

        this.retainerServicesHeader = [...currentHeaders, objWrapRS];

        console.log('Updated retainerServicesHeader =>', this.retainerServicesHeader);
    }
 
    handleInputChangeServiceHeader(event) {
        let serviceHeader = {...this.serviceHeader};
        let {name, value} =  event.target;
        serviceHeader[name] = value;
        
        if (name === 'startDate') {
            serviceHeader.endDate = this.getEndDate(serviceHeader, value);
            this.checkAndSetContractForMonth(serviceHeader);

        } else if (name === 'endDate') {
            this.checkAndSetContractForMonth(serviceHeader);

        } else if (name === 'contractForMonth') {
           serviceHeader.endDate = this.getEndDate(serviceHeader, value);
        }
     
        this.serviceHeader = serviceHeader;
        console.log('this.serviceHeader==>',this.serviceHeader);

    }

    handleInputChangeRSHeader(event) {
        const {indexrs} = event.target.dataset;
        const {name, value} = event.target;

        let retainerServicesHeader = [...this.retainerServicesHeader];
        retainerServicesHeader[indexrs][name] = value;
        this.retainerServicesHeader = [...retainerServicesHeader];
        console.log('this.retainerServicesHeader==>',this.retainerServicesHeader);
    }

    switchSectionServHeader(event) {
        const {name} = event.target;
        this[name] = !this[name];
    }

    handleAddRsHeader(event) {
        this.buildRsHeader();
       // this.indexingRsHeader();
    }

    handleRemoveRsHeader(event) {
        const {indexrs} = event.target.dataset;

        let retainerServicesHeader = [...this.retainerServicesHeader];
        retainerServicesHeader.splice(indexrs, 1);
        this.retainerServicesHeader = retainerServicesHeader;
        this.indexingRsHeader();
    }

    indexingRsHeader() {
        this.retainerServicesHeader = (this.retainerServicesHeader || []).map((item, index)=>
           item.index = index+1
        );
    }

    handleApplyToStores(event) {
        let isSuccess = true;
        const isValidRsHeader = this.checkValidityRsHeader();
        console.log('isValidRsHeader==>', isValidRsHeader);

        if (!isValidRsHeader) {
            this.showToast('Error', 'Please fill all required fields', 'error');
            return;
        }

        let listWrapServices = JSON.parse(JSON.stringify(this.listWrapServices));

        (listWrapServices || []).forEach((objWrapService, idx) => {
            objWrapService = {...objWrapService , ...this.serviceHeader };
            console.log('11objWrapService==>',objWrapService);
            if (objWrapService?.retainerServices) {

                // Merge header services
                let mergedServices = [
                    ...objWrapService.retainerServices,
                    ...this.retainerServicesHeader
                ];

                // Filter invalid rows
                mergedServices = mergedServices.filter(rs => {
                    return !(
                        !rs.caseRecordType &&
                        !rs.numberOfCasesAllowedPerPeriod &&
                        !rs.amountPerMonth
                    );
                });

                // Update values + indexing
                mergedServices = mergedServices.map((rs, indexrs) => ({
                    ...rs,
                    amountPerMonth: objWrapService.price,
                    index: indexrs + 1,
                    showDeleteButton:
                        mergedServices.length > 1 &&
                        SHARED_JAVASCRIPT_CODE.isEmpty(rs.id)
                }));

                objWrapService.retainerServices = mergedServices;
                isSuccess = true;

            } else {
                objWrapService.retainerServices = [];
                objWrapService.showDeleteButton = false;
            }
             listWrapServices[idx] = objWrapService;
        });

        this.indexingElement(listWrapServices);
        this.listWrapServices = [...listWrapServices];

        console.log(
            'handleApplyToStores.listWrapServices==>',
            this.listWrapServices
        );

        if (isSuccess) {
           this.showToast('Success', 'The common service has been successfully applied to all stores.', 'success');
           this.retainerServicesHeader = [];
          setTimeout(() => {
              this.buildRsHeader();
              this.serviceHeader = {};
            
          }, 100);
        }
    }

    //Cancel Services
    async handleCancelService(event) {
        console.log('handleCancelService');

        const { name } = event.currentTarget;
        const {index} = event.currentTarget.dataset;
        console.log('name==>',name);
        console.log('index==>',index);

         const result = await LightningConfirm.open({
            message: 'Do you want to cancel the service?',
            label: 'Confirm Service Cancelation?',
            theme: 'warning',
        });
        console.log('confirm result', this.listWrapServices);
        
        if (result) {
            if (this.listWrapServices?.[index]?.hasOwnProperty(name)) {
                const serviceId = this.listWrapServices[index][name];
                console.log('serviceId==>',serviceId);
                this.passServiceIdToParentToCancel(serviceId);
            }
        }
    }

    passServiceIdToParentToCancel(serviceId) {
        const cancelServiceEve = new CustomEvent('cancelservice',
            {
                detail : {
                    serviceId : serviceId
                }
            }
        )
        console.log('cancelServiceEve==>',cancelServiceEve);
        this.dispatchEvent(cancelServiceEve);
    }

    // Action Functions
    handleInputChange(event) {
        event.preventDefault();
        event.stopPropagation();
        const { name, value } = event.target;
        const {index} = event.target.dataset;

        let listWrapServices = JSON.parse(JSON.stringify(this.listWrapServices));
        listWrapServices[index][name] = value;

        if (name === 'startDate' || name === 'endDate') {
            let isValid = this.checkStartEndDateValidityAndShowError(listWrapServices[index], event);
            console.log('isValid==>',isValid);
            if (!isValid) {
                listWrapServices[index].contractForMonth = name === 'endDate' ? undefined : listWrapServices[index].contractForMonth;
                return;
            }
        }
        
        if (name === 'startDate') {
            listWrapServices[index].endDate = this.getEndDate(listWrapServices[index], value);
            this.checkAndSetContractForMonth(listWrapServices[index]);

        } else if (name === 'endDate') {
            this.checkAndSetContractForMonth(listWrapServices[index]);

        } else if (name === 'contractForMonth') {

            listWrapServices[index].endDate = this.getEndDate(listWrapServices[index], value);
        } else if (name === 'price' && this.isActionForCreate) {
            listWrapServices[index] = this.assignServiceAmToRsAm(listWrapServices[index]);
        }
       
        this.listWrapServices = [...listWrapServices];
        console.log('this.listWrapServices==>',this.listWrapServices);
    }

    assignServiceAmToRsAm(objWrapService) {
        const retainerServices = objWrapService?.retainerServices || [];
        if (!retainerServices.length) {
            return objWrapService;
        }

        const updatedRetainerServices = retainerServices.map(rs => {
            return {
                ...rs,
                amountPerMonth: objWrapService.price
            };
        });

        return {
            ...objWrapService,
            retainerServices: updatedRetainerServices
        };
    }

  

    checkStartEndDateValidityAndShowError(objWrap, event) {
        let isValid = true;
        let isValidStartEnd = this.isStartEndDateValid(objWrap);
        
        if (!isValidStartEnd) {
            isValid = isValidStartEnd;
            this.showToast('Error', 'End Date cannot be earlier than Start Date', 'error');
            event.target.value = undefined;
            objWrap[event.target.name] = undefined;
        }
        
        let isValidMonthDifference = this.isValidMonthDifference(objWrap);
        if (!isValidMonthDifference) { 
            isValid = isValidMonthDifference; 
            this.showToast('Error', 'The difference between the Start Date and End Date must not exceed 99 months.', 'error');
            event.target.value = undefined;
            objWrap[event.target.name] = undefined;
        }

        return isValid;
    }

    getEndDate(objWrap) {
        let startDate = new Date(objWrap.startDate);
        if (!isNaN(startDate) && objWrap.contractForMonth && objWrap.contractForMonth > 0) {
            let endDate = this.addFractionalMonths(startDate, Number(objWrap.contractForMonth));
            // let endDate = new Date(startDate);
            // endDate.setMonth(endDate.getMonth() + Number(objWrap.contractForMonth));
            // ✅ Convert Date → YYYY-MM-DD
            objWrap.endDate = endDate.toISOString().split('T')[0];
        } else {
             objWrap.endDate = undefined;
        }
        return objWrap.endDate;
    }

    addFractionalMonths(date, months) {
        const fullMonths = Math.floor(months);       // 1
        const fraction = months - fullMonths;        // 0.3

        // Add full months
        const newDate = new Date(date);
        newDate.setMonth(newDate.getMonth() + fullMonths);

        // Add fractional months as days (assuming 1 month = 30 days)
        newDate.setDate(newDate.getDate() + Math.round(fraction * 30));

        return newDate;
    }

    checkAndSetContractForMonth(objWrap) {
        if (objWrap && objWrap.startDate && objWrap.endDate) {
            objWrap.contractForMonth = this.getContractForMonth(objWrap.startDate, objWrap.endDate);
        }
    }

    getContractForMonth(startDate, endDate) {
        const diffInDays = SHARED_JAVASCRIPT_CODE.diffInDays(startDate, endDate);
        const calMonths = Number((diffInDays / 30).toFixed(1));
        return calMonths;
    }

    isStartEndDateValid(objWrapService) {
        if (!objWrapService?.startDate || !objWrapService?.endDate) {
            return true; // validation not applicable yet
        }

        const startDate = new Date(objWrapService.startDate);
        const endDate = new Date(objWrapService.endDate);

        // Handle invalid date values
        if (isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
            return true;
        }

        // Normalize time to avoid timezone issues
        startDate.setHours(0, 0, 0, 0);
        endDate.setHours(0, 0, 0, 0);

        return endDate >= startDate;
    }

    isValidMonthDifference(objWrapService) {

        if (!objWrapService?.startDate || !objWrapService?.endDate) {
            return true; 
        }

        let months = this.getContractForMonth(objWrapService.startDate, objWrapService.endDate);
        return months >= 0 && months <= 100.40;
    }



    handlePicklistChange(event) {
        const {index} = event.target.dataset;
        const {name, value} = event.target;
        console.log(`index: ${index},  name: ${name} , value: ${value} `);
        
        let listWrapServices = JSON.parse(JSON.stringify(this.listWrapServices));;

        let objWrapService = listWrapServices[index];
        let retainerServices = objWrapService?.retainerServices || [];
        if (index > -1 && objWrapService ) {
            listWrapServices[index][name] = value;
           
        } 

        this.listWrapServices = listWrapServices;
        console.log('this.listWrapServices==>',this.listWrapServices);
    }

    handleInputChangeRS(event) {
        const {index, indexrs} = event.target.dataset;
        const {name, value} = event.target;
        console.log(`index: ${index}, indexrs: ${indexrs}, name: ${name} , value: ${value} `);
        
        let listWrapServices = JSON.parse(JSON.stringify(this.listWrapServices));;

        let objWrapService = listWrapServices[index];
        let retainerServices = objWrapService?.retainerServices || [];

        if (index > -1 && indexrs > -1 && objWrapService && retainerServices[indexrs] ) {
            const caseRecordTypeIds = retainerServices.map(c => c.caseRecordType);
            if (caseRecordTypeIds.includes(value) && this.isActionForCreate ) {
                event.target.value = undefined;
                retainerServices[indexrs][name] = undefined;
                this.showToast('Error', `${value} - Case Record Type is already added.`, 'error');
                return;
            } else {

                retainerServices[indexrs][name] = value;
                
                    if ( (name === 'startDate' || name === 'endDate') ) {
                        let isValid = this.checkStartEndDateValidityAndShowError(retainerServices[indexrs], event);
                        console.log('isValid==>',isValid);
                        if (!isValid) {
                            return;
                       }
                    }

            }
        }

        this.listWrapServices = listWrapServices;
        console.log('this.listWrapServices==>',this.listWrapServices);
    }

   
    restrictInvalidKeyForNo(event) {
        if (( ['+' , '-' , ','  ,'b' ,'e' , 'k', 'm', 't'].includes(event.key))) {
            event.preventDefault();
        }
    }

    switchSection(event) {
        const {index} = event.target.dataset;
        const {name, value} = event.target;
        console.log(`index: ${index}, name: ${name} , value: ${value} `);
        
        let listWrapServices = JSON.parse(JSON.stringify(this.listWrapServices));
        let objWrapService = listWrapServices[index];
        if (index > -1 && objWrapService ) {
            listWrapServices[index][name] = !listWrapServices[index][name]; 
        }
        this.listWrapServices = listWrapServices;
        console.log('this.listWrapServices==>',this.listWrapServices);
    }

    handleRemoveRetainerService(event) {
        const { index, indexrs } = event.target.dataset;

        let listWrapServices = JSON.parse(JSON.stringify(this.listWrapServices));
        let objWrapService = listWrapServices[index];
        let retainerServices = [...(objWrapService.retainerServices || [])];

        if (retainerServices.length > 1) {
            const removedService = retainerServices[indexrs];
            retainerServices.splice(indexrs, 1);

            if (removedService?.id) {
                this.retainerServiceIdsForDelete = [
                    ...this.retainerServiceIdsForDelete,
                    removedService.id
                ];
            }

            objWrapService.retainerServices = [...retainerServices];
            listWrapServices[index] = { ...objWrapService };

            this.indexingElement(listWrapServices);
        }
        this.listWrapServices = [...listWrapServices];
    }

    handleAddRetainerService(event) {
        const index = Number(event.target.dataset.index);
        console.log(`index: ${index}`);

        let listWrapServices = JSON.parse(JSON.stringify(this.listWrapServices));
        let objWrapService = listWrapServices[index];

        if (index > -1 && objWrapService) {
            let retainerServices = [...(objWrapService.retainerServices || [])];
            retainerServices.push({
                ...formatRetainerService,
                index: retainerServices.length + 1,
                amountPerMonth: objWrapService.price 
            });

            objWrapService.retainerServices = retainerServices;
            listWrapServices[index] = { ...objWrapService };
            this.indexingElement(listWrapServices);
        }
        this.listWrapServices = [...listWrapServices];
        console.log('this.listWrapServices==>', this.listWrapServices);
    }


    indexingElement(listWrapServices) {
        listWrapServices.forEach((objWrapService, index) => {
            objWrapService.index = index + 1;
            if (objWrapService.retainerServices) {
                objWrapService.retainerServices.forEach((rs, indexrs) => {
                    rs.index = indexrs + 1;
                    rs.showDeleteButton = objWrapService.retainerServices.length > 1 
                        && SHARED_JAVASCRIPT_CODE.isEmpty(rs.id)
                });
            } else {
                objWrapService.showDeleteButton = false;
                objWrapService.retainerServices = [];
            }

            // if (objWrapService.retainerServices.length > 1 && SHARED_JAVASCRIPT_CODE.isEmpty(objWrapService.retainerService.id)) {
            //     objWrapService.showDeleteButton = true;
            // } else {
            //     objWrapService.showDeleteButton = false;
            // }
        });

    }
    

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title,
            message,
            variant,
        });
        this.dispatchEvent(evt);
    }

    @api checkValidity() {
        let isRequiredInputfieldHasValue = SHARED_JAVASCRIPT_CODE.isInputValid('validate',this.template);
		console.log('isRequiredInputfieldHasValue==>'+isRequiredInputfieldHasValue);
        return isRequiredInputfieldHasValue;
    }

    @api getListWrapServices() {
        return JSON.parse(JSON.stringify(this.listWrapServices));
    }

    restrictNumberUpto1Decimal(event) {
        // Block 'e', 'E', '+', '-', and '.'
        const fieldName = event.target.name;
        const input = event.target;
        const value = input.value ?? '' ;
        const key = event.key;
        console.log('fieldName: ' + fieldName);
        const step = input.step ? parseFloat(input.step) : null;
        console.log('step: ' + step);
          console.log('key: ' + key);
         console.log('value: ' + value);

        if (key ==='Backspace') {
            return;
        }

        if ( ['e', 'E', '+', '-', 't','k','m','b'].includes(event.key)) {
            event.preventDefault();
        }

        if (value.includes('.') && (value+'').length >= 3) {
            event.preventDefault();
            return;
        } 

        if (!value.includes('.') && (value+'').length >= 2) {
            event.preventDefault();
            return;
        }

        if (value.includes('.') && /[0-9]/.test(key)) {
            const decimals = value.split('.')[1];
            const cursorPos = input.selectionStart;
            const decimalIndex = value.indexOf('.');
            if (cursorPos > decimalIndex && decimals.length >= 2) {
                event.preventDefault();
                return;
            }
        }

        else if (step === 0.1) {
        // Prevent more than one decimal point
            if (key === '.' && value.includes('.')) {
                event.preventDefault();
                return;
            }

            // If there's a decimal point, restrict to 3 digits after it
            if (value.includes('.') && /[0-9]/.test(key)) {
                const decimals = value.split('.')[1];
                const cursorPos = input.selectionStart;
                const decimalIndex = value.indexOf('.');
                if (cursorPos > decimalIndex && decimals.length >= 2) {
                    event.preventDefault();
                    return;
                }
            }
        }
        
    }

     @api checkValidityRsHeader() {
        let isRequiredInputfieldHasValue = SHARED_JAVASCRIPT_CODE.isInputValid('validateRsHeader',this.template);
		console.log('isRequiredInputfieldHasValue==>'+isRequiredInputfieldHasValue);
        return isRequiredInputfieldHasValue;
    }
}