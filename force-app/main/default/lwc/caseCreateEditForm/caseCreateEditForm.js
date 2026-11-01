import { LightningElement, api } from "lwc";
import {ShowToastEvent} from 'lightning/platformShowToastEvent';
import * as  SHARED_JAVASCRIPT_CODE from "c/ciSharedJavascriptCode";
import isPricingVisible from '@salesforce/apex/PricingVisibilityController.isPricingVisible';

const RUSH_FEE_AMOUNT = 900;

const priceFields = () => ([
	{id:0, label:'Total Price', apiName:'Total_Price__c', value:'', type:'number', required: true, cssClass: 'validateInputField', showError:false, errorMsg: 'Deposit upfront is required.'}, 
	{id:1, label:'Deposit upfront', apiName:'Deposit_Upfront__c', value:'', type:'number', required: true, cssClass: 'validateInputField', showError:false, errorMsg: 'Deposit upfront is required.'}
]);

const BRAND_REGISTRY_RECORD_TYPE_NAME = 'Brand Registry';

const formatJsonCase = () => ({
	"index":1,
	"recordTypeId" : undefined,
	"recordTypeName" : undefined,
	"id": "",
	"uniqueId": `Case_${Date.now()}_${Math.random().toString(36).substring(2,8)}`,
	"ownerId" : "",
	"ownerName" : "",
	"isBrandRegistry" : false,
	"isPricingReq" : false,
	"totalPrice" : 0,
	"depositUpfront" : 0,
	"fields" : [],
	"priceFields": [...priceFields()],
	"rushFee" : false,
	"priority" : null,
	"swithCaseSection" : true,
	"showDeleteButton" : false,
	"disabled" : false,
	"isNew" : true,
	"showCaseRecTypeReqErr" : false
});

const formatJSON = () => ({
    "index" : 1,
    "storeId": "",
    "storeName": "",
	"whiteGlove" : false,
	"swithStoreSection" : true,
    "showDeleteButton" : false,  
    "cases":  [
	 {... (formatJsonCase())}
	 ],
});

    

export default class CaseCreateEditForm extends LightningElement {
	@api recordId;
	@api objectApiName;
    // @api currentStep = '1';
	@api actionFor = 'create';
	@api selectedStoreRecords = [];
	//@api recordTypeOptions = [];
	_recordTypeOptions = [];
	@api mapRtIdAndName = [];
	@api caseFieldSetWrap = [];
	@api listWrapCasesCopy =  [];
	@api mapServiceTypePrice = {};
	listWrapCases = [];
	isPricingUser = false;
	showSpinner = false;
	
    get recordTypeOptions() {
        return this._recordTypeOptions;
    }

	@api set recordTypeOptions(value) {
        this._recordTypeOptions = [...value];
		setTimeout(() => {
			this.buidLookupOptions();
		}, 400); 
	}

	connectedCallback() {
			isPricingVisible()
		.then(result => {
			this.isPricingUser = result;
		})
		.catch(error => {
			console.error(error);
		});

		this.listWrapCases = JSON.parse(JSON.stringify(this.listWrapCasesCopy));
        // if (this.listWrapCasesCopy && this.listWrapCasesCopy.length > 0) {
        //     this.listWrapCases = JSON.parse(JSON.stringify(this.listWrapCasesCopy));
        // } else {
        //     this.buildListWrap();
        // }
		this.buildListWrap();
		console.log('this.listWrapCases==>',this.listWrapCases);
		console.log('this.caseFieldSetWrap==>',this.caseFieldSetWrap);
		console.log('this.mapRtIdAndName==>',this.mapRtIdAndName);
    }

	buildListWrap() {
		const existingMap = new Map();

		// Index existing wrap cases by storeId
		(this.listWrapCases || []).forEach(wrap => {
			existingMap.set(wrap.storeId, wrap);
		});

		const listWrapCases = (this.selectedStoreRecords || []).map((item, index) => {
			// If already exists → reuse
			if (existingMap.has(item.Id)) {
				const existingWrap = { ...existingMap.get(item.Id) };
				existingWrap.index = index + 1; // reindex if order changed
				console.log('existingWrap==>',existingWrap);
				return existingWrap;
			}

			// Else → create new
			let objWrapCase = JSON.parse(JSON.stringify(formatJSON()));
			objWrapCase.index = index + 1;
			objWrapCase.storeId = item.Id;
			objWrapCase.storeName = item.Name;
			objWrapCase.whiteGlove = item.White_Glove__c;

			return objWrapCase;
		});

		this.listWrapCases = listWrapCases;

		console.log('buildListWrap.listWrapCases==>', this.listWrapCases);
    }




	buidLookupOptions() {
		console.log('1this.listWrapCases==>',this.listWrapCases);
		console.log('1this.recordTypeOptions==>',this.recordTypeOptions);
		this.listWrapCases.forEach(item => { 
			if (item.cases && item.cases.length > 0) {
				item.cases.forEach(objCase => { 
					console.log('objCase.uniqueId==>'+objCase.uniqueId);
					this.updateCustomLookupOptions( { 
						className: objCase.uniqueId,
						options : [...this.recordTypeOptions], 
						selectedOption :  objCase.recordTypeId
				    });
			    });
	        }
	    });
	}

	updateCustomLookupOptions(objCustomLookupData) {
        let {className, options = [], selectedOption} = objCustomLookupData;
        className  = '.'+className;
        let customLookupChild = this.template.querySelector(className);
        console.log('customLookupChild==>',customLookupChild);
        if (customLookupChild) {
            customLookupChild.setOptions(options);
            customLookupChild.setSelectedValues(selectedOption);

        }
        console.log('selectedOption==>',selectedOption);
    }

	getFieldSetFields(rtLabelName) {
		let listFields = [];
		if (this.caseFieldSetWrap && this.caseFieldSetWrap.length > 0) {
			let objCaseFieldSet = this.caseFieldSetWrap.find( item => (item.name === rtLabelName || item.label === rtLabelName ));
			if (objCaseFieldSet) {
				listFields = objCaseFieldSet.fields;
			}
		}
		return listFields;
	}

	handleLookupSelectionChange(event) {  
        let {label, value, className} = event.detail;
        console.log(`label: ',${label}, value: ',${value}, className: ',${className} `);

        // let objCase = this.getRelatedCase(className);
		let {objWrap, objCase } = this.getRelatedCaseAndParent(className);
        if (!objCase) return;
        let cleaned = value ? (value+'').replace(/^"|"$/g, '') : undefined;
		//let recordTypeApiName = this.mapRtIdAndName[cleaned];
		//console.log('recordTypeApiName==>',recordTypeApiName);
		let listFields = this.getFieldSetFields(label);
		objCase.fields = [...listFields]
        objCase['recordTypeId'] = cleaned;
		objCase['recordTypeName'] = label;
		objCase.isBrandRegistry = (label === BRAND_REGISTRY_RECORD_TYPE_NAME);
		objCase.ownerName = '';
		objCase.ownerId = '';
        objCase.isPricingReq = false;

		if (cleaned && !(objWrap?.whiteGlove)&& this.isPricingUser) {
            objCase.isPricingReq = true;
			objCase.priceFields = this.getPriceFieldsAsPerCaseRt(label);
		}

		// Reset rush fee when record type changes
		objCase.rushFee = false;
		objCase.priority = null;

		if (cleaned && !SHARED_JAVASCRIPT_CODE.isEmpty(cleaned)) {
			this.showSpinner = true;
            objCase.showCaseRecTypeReqErr = false;
		}
		console.log('objCase=>', objCase);
		this.listWrapCases = [...this.listWrapCases];
		setTimeout(() => {
			this.showSpinner = false;
		}, 800);

    }

	// getPriceFieldsAsPerCaseRt11(caseRecordTypeName) {
	// 	console.log('caseRecordTypeName==>',caseRecordTypeName);
	// 	console.log('this.mapServiceTypePrice==>',this.mapServiceTypePrice);
	//     let priceFieldsTem = [];
    //     if (this.mapServiceTypePrice[caseRecordTypeName]) {
	// 		 console.log('1==>');
	// 	    let objServiceTypePrice = this.mapServiceTypePrice[caseRecordTypeName];
	// 		 console.log('2==>',objServiceTypePrice);
	// 		priceFieldsTem = priceFields().map((field, index) => {
	// 			field.value = objServiceTypePrice[field.name];
	// 		});
	//     }
    //     console.log('priceFieldsTem==>',priceFieldsTem);
	// 	return priceFieldsTem;
	// }

	getPriceFieldsAsPerCaseRt(caseRecordTypeName) {
		let serviceTypeName = (caseRecordTypeName+'').toLowerCase().trim();
		console.log('caseRecordTypeName==>', caseRecordTypeName);
		console.log('this.mapServiceTypePrice==>', this.mapServiceTypePrice);

		let priceFieldsTemp = [];

		if (this.mapServiceTypePrice?.[serviceTypeName]) {
			console.log('1==>');
			const objServiceTypePrice = this.mapServiceTypePrice[serviceTypeName];
            console.log('2==>',objServiceTypePrice);
			priceFieldsTemp = priceFields().map((field, index) => {
				//let apiName = field.apiName == 'Deposit_Upfront__c' ? 'Deposit_upfront__c'
				console.log('field==>',field);
				console.log('field.apiName==>',field.apiName);
				console.log('field1==>',objServiceTypePrice[field.apiName]);
				return {
					...field,
					value: objServiceTypePrice[field.apiName] ?? ''
				};
			});
			console.log('00priceFieldsTemp==>',priceFieldsTemp);
		} else {
			priceFieldsTemp = priceFields().map((field, index) => { 
				return {
					...field
				};
			})
		}

		console.log('priceFieldsTemp==>', priceFieldsTemp);
		return priceFieldsTemp;
    }


    handleLookupServerSearch(event) {
        let {className, searchTerm, value} = event.detail;
        console.log(`handleLookupServerSearch : searchTerm: ${searchTerm} , className: ${className}, value: ${value}`);
        if (searchTerm && searchTerm.length > 1 && className) {
			//this.buidLookupOptions();
            // let objCase = this.getRelatedCase(className);
            // if (!objCase) return;
        } 
		
    }

	getRelatedCaseAndParent(className) {
		let parentIndex = -1;
		let childIndex = -1;
		let objCase = null;
		let objWrap = null;

		this.listWrapCases.some((wrapper, pIndex) => {
		const cIndex = wrapper.cases.findIndex(
			c => c.uniqueId === className
		);

		if (cIndex !== -1) {
			parentIndex = pIndex;
			childIndex = cIndex;
			objCase = wrapper.cases[cIndex];
			objWrap = wrapper;
			return true; // stop iteration
		}
		return false;
		});

		console.log('Parent Index:', parentIndex);
		console.log('Child Index:', childIndex);
		console.log('Case Record:', objCase);

		return {objWrap, objCase};

	}

	getRelatedCase(className) {
		const caseRecord = this.listWrapCases
		.flatMap(w => w.cases)
		.find(c => c.uniqueId === className);

		console.log('caseRecord==>',caseRecord);
		return caseRecord;
    }

	switchSection(event) {
        const {index} = event.target.dataset;
        const {name, value} = event.target;
        console.log(`index: ${index}, name: ${name} , value: ${value} `);
        
        let listWrapCases = JSON.parse(JSON.stringify(this.listWrapCases));
        let objWrapService = listWrapCases[index];
        if (index > -1 && objWrapService ) {
            listWrapCases[index][name] = !listWrapCases[index][name]; 
        }
        this.listWrapCases = listWrapCases;
        console.log('this.listWrapCases==>',this.listWrapCases);
		setTimeout(() => {
			this.buidLookupOptions();
		}, 600); 
    }

	handleAddCase(event) {
        const {index} = event.target.dataset;
        const {name, value} = event.target;
        console.log(`index: ${index}, name: ${name} , value: ${value} `);
        
        if (this.listWrapCases[index] && this.listWrapCases[index].cases ) {
			let objNewCase = {...formatJsonCase()};
			objNewCase.index = this.listWrapCases[index].cases.length + 1;
			this.listWrapCases[index].cases = [...this.listWrapCases[index].cases, objNewCase];
			this.updateDeleteButton(index);
			setTimeout(() => {
				this.buidLookupOptions();
			}, 600); 
        }
	}

	handleRemoveCase(event) {
		const {index, indexcase} = event.target.dataset;
		console.log(`index: ${index}, indexCase: ${indexcase}`);
		if (this.listWrapCases[index]?.cases?.length > indexcase) {
			this.listWrapCases[index].cases.splice(indexcase, 1);
			console.log('Rem:this.listWrapCases==>',this.listWrapCases);
			this.updateDeleteButton(index);
        }
    }

	updateDeleteButton(index) {
		const cases = this.listWrapCases[index].cases;
		const showDelete = cases.length > 1;

		cases.forEach((c, idx) => {
			c.index = idx + 1;       
			c.showDeleteButton = showDelete;
        });

		// Force LWC reactivity
		this.listWrapCases = [...this.listWrapCases];
		console.log('22this.listWrapCases==>',this.listWrapCases);
    }

	@api checkValidity() {
		return this.checkValidityCaseRecordType();
    }

	// checkValidityCaseRecordType111() {
	// 	console.log('checkValidityCaseRecordType');
	// 	let hasCasesRt = true;

	// 	this.listWrapCases = (JSON.parse(JSON.stringify(this.listWrapCases))).map((newWrap, index) => {
	// 		//this.listWrapCase = (this.listWrapCase).map((newWrap, index) => {
	// 		let wrapCase = newWrap;
	// 		wrapCase.showCaseRecTypeReqErr = false;
	// 		if (SHARED_JAVASCRIPT_CODE.isEmpty(wrapCase.recordTypeId)) {
	// 			wrapCase.showCaseRecTypeReqErr = true;
	// 			hasCasesRt = false;
	// 			//wrapCase = {...wrapCase}
	// 		}
			
	// 		if (wrapCase?.cases?.length > 0 && wrapCase.recordTypeId)
	// 		wrapCase.cases.forEach((caseItem, indexcase) => {
	// 	        if (caseItem?.fields?.length > 0) 
	// 			caseItem.fields.forEach((fieldItem, indexfield) => { 
	// 		        fieldItem.showError = false;
    //                 if (fieldItem.required && SHARED_JAVASCRIPT_CODE.isEmpty(fieldItem.value)) {
    //                     fieldItem.showError = true;
	// 					fieldItem.errorMsg = `${fieldItem.label} is required.`;
	// 					hasCasesRt = false;
	// 				} 
	// 			});

	// 			if (caseItem?.priceFields?.length > 0 && wrapCase.recordTypeId) 
	// 			caseItem.priceFields.forEach((fieldItem, indexfield) => { 
	// 		        fieldItem.showError = false;
    //                 if (fieldItem.required && SHARED_JAVASCRIPT_CODE.isEmpty(fieldItem.value)) {
    //                     fieldItem.showError = true;
	// 					fieldItem.errorMsg = `${fieldItem.label} is required.`;
	// 					hasCasesRt = false;
	// 				} 
	// 			});



	// 		});
	// 		return wrapCase;
	// 	});
    //     console.log('this.listWrapCases==>',this.listWrapCases);
	// 	return hasCasesRt;
	// }

	checkValidityCaseRecordType() {
		console.log('checkValidityCaseRecordType');
		let isValidInput = true;

		this.listWrapCases = this.listWrapCases.map(wrapCase => {
			let newWrap = { ...wrapCase};

			// Cases
			if (newWrap.cases?.length) {
				console.log('#1');
				newWrap.cases = newWrap.cases.map(caseItem => {
					let newCase = { ...caseItem,showCaseRecTypeReqErr: false  };

					// Record Type validation
					if (SHARED_JAVASCRIPT_CODE.isEmpty(caseItem.recordTypeId)) {
						newCase.showCaseRecTypeReqErr = true;
						isValidInput = false;
						return newCase;
					}

					// Fields
					if (newCase.fields?.length) {
						console.log('#2');
						newCase.fields = newCase.fields.map(field => {
							console.log('#3');
							let newField = { ...field, showError: false };

							if (newField.required && SHARED_JAVASCRIPT_CODE.isEmpty(newField.value)) {
								console.log('#3.1');
								newField.showError = true;
								newField.errorMsg = `${newField.label} is required.`;
								isValidInput = false;
							}
							return newField;
						});
					}

					// Price Fields
					if (newCase.priceFields?.length && newCase.isPricingReq) {
						newCase.priceFields = newCase.priceFields.map(field => {
							console.log('#4');
							let newField = { ...field, showError: false };

							if (newField.required && SHARED_JAVASCRIPT_CODE.isEmpty(newField.value)) {
								console.log('#5');
								newField.showError = true;
								newField.errorMsg = `${newField.label} is required.`;
								isValidInput = false;
							}
							return newField;
						});
					}

					return newCase;
				});
			}  

			return newWrap;
		});
		
		this.listWrapCases = [...this.listWrapCases];
		console.log('this.listWrapCases==>', this.listWrapCases);
		return isValidInput;
    }


	handleRecordPicker(event) {

		let selectedRecordId = event.detail.recordId;
		let objectApiName = event.target.objectApiName;

		const {index, indexcase, fieldname} = event.target.dataset;

		if (this.listWrapCases[index]?.cases?.length > indexcase) {
			
			const updatedList = [...this.listWrapCases];
			const updatedCases = [...updatedList[index].cases];
			const objCase = {...updatedList[index].cases[indexcase]};
		    objCase[fieldname] = selectedRecordId;

			updatedCases[indexcase] = objCase;

			updatedCases[indexcase] = {...updatedCases[indexcase]};

			updatedList[index] = {
				...updatedList[index],
				cases: updatedCases
			};

			this.listWrapCases = updatedList;

			 console.log('handleFieldChangeTopLevel:this.listWrapCases==>',this.listWrapCases);
        } else {
			console.log('handleFieldChangeTopLevel Field was not found');
		}

	}
	

	handleOwnerNameChange(event) {
		const { index, indexcase, fieldname } = event.target.dataset;
		const value = event.target.value;

		if (this.listWrapCases[index]?.cases?.length > indexcase) {
			const updatedList = [...this.listWrapCases];
			const updatedCases = [...updatedList[index].cases];
			const objCase = { ...updatedCases[indexcase] };
			objCase[fieldname] = value;
			updatedCases[indexcase] = objCase;
			updatedList[index] = { ...updatedList[index], cases: updatedCases };
			this.listWrapCases = updatedList;
		}
	}


	handleFieldChange(event) {
		
		const {index, indexcase, indexfield, fieldfor} = event.target.dataset;
		const {fieldName, value} = event.target; 
		console.log(`index: ${index} , indexCase: ${indexcase} , indexField: ${indexfield} , fieldfor: ${fieldfor}, fieldName: ${fieldName}  , value: ${value}  `);

		if (this.listWrapCases[index]?.cases[indexcase]?.[fieldfor]?.length > indexfield) {
			
			const updatedList = [...this.listWrapCases];

			const updatedCases = [...updatedList[index].cases];
			const updatedFields = [...updatedCases[indexcase][fieldfor]];

			updatedFields[indexfield] = {
				...updatedFields[indexfield],
				value: value
			};

			updatedCases[indexcase][fieldfor] = updatedFields;
			updatedCases[indexcase] = {...updatedCases[indexcase]};

			updatedList[index] = {
				...updatedList[index],
				cases: updatedCases
			};

			this.listWrapCases = updatedList;

			console.log('Rem:this.listWrapCases==>',this.listWrapCases);
        } else {
			console.log('Field was not found');
		}
 
	}

	@api getlistWrapCases() {
		return this.listWrapCases;
	}

	handleRushFeeChange(event) {
		const { index, indexcase } = event.target.dataset;
		const checked = event.target.checked;

		if (!this.listWrapCases[index]?.cases?.[indexcase]) return;

		const updatedList = [...this.listWrapCases];
		const updatedCases = [...updatedList[index].cases];
		const caseRec = { ...updatedCases[indexcase] };

		caseRec.rushFee = checked;
		caseRec.priority = checked ? 'High' : null;

		const delta = checked ? RUSH_FEE_AMOUNT : -RUSH_FEE_AMOUNT;
		if (caseRec.priceFields) {
			caseRec.priceFields = caseRec.priceFields.map(field => {
				if (field.apiName === 'Total_Price__c' || field.apiName === 'Deposit_Upfront__c') {
					const current = parseFloat(field.value) || 0;
					return { ...field, value: (current + delta).toString() };
				}
				return field;
			});
		}

		updatedCases[indexcase] = caseRec;
		updatedList[index] = { ...updatedList[index], cases: updatedCases };
		this.listWrapCases = updatedList;
	}



}