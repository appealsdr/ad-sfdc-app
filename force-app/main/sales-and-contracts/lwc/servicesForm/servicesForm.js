import { LightningElement, api } from "lwc";
import {ShowToastEvent} from 'lightning/platformShowToastEvent';
import Store_Form_Config_LABEL from '@salesforce/label/c.Store_Form_Config';
import * as  SHARED_JAVASCRIPT_CODE from "c/ciSharedJavascriptCode";
//Apex Import
import upsertStoreAndServices from '@salesforce/apex/ServicesFormController.upsertStoreAndServices';
import getServicesWrapData from '@salesforce/apex/ServicesFormController.getServicesWrapData'; 
import cancelService from '@salesforce/apex/ServicesFormController.cancelService';

export default class ServicesForm extends LightningElement {
	Store_Form_Config_LABEL = Store_Form_Config_LABEL || {};
	@api recordId;
	@api objectApiName;
	@api serviceActionFor = 'create';
	@api currentStep = '2';

    selectedStoreRecords = [];
	selectedStoreIds = [];
    listWrapServices = [];

	hasStepError = false;
	showSpinner = false;

	get actionFor() {
        return this.serviceActionFor;
	}

	get showUpdateScreen () {
		return this.isIndicatorForCreate ||  (this.serviceActionFor === 'update' && (this.listWrapServices && this.listWrapServices.length > 0 ));
	}

	get isIndicatorForCreate() {
		return this.serviceActionFor === 'create' ? true : false
	}

	get labelForAction() {
		return this.serviceActionFor === 'create' ? 'Create Services' : 'Update Services';
	}

	get showNextBtn() {
        return this.serviceActionFor === 'create' && this.currentStep && [2].includes(Number(this.currentStep));
	}

	get showBackBtn() {
        return this.serviceActionFor === 'create' && (this.currentStep && [3].includes(Number(this.currentStep)));
	}
	
	get showCreateServiceBtn() {
        return (this.currentStep && Number(this.currentStep) === 3 );
	}

	get isStoreScreen() {
		return this.serviceActionFor === "create" && (this.currentStep && Number(this.currentStep) === 2 );
	}

	get isServicesScreen() {
		return (this.currentStep && Number(this.currentStep) === 3 ) && this.showUpdateScreen;
	}

	get isDisabledNextBtn() {
        return  this.currentStep != '1' && (!this.selectedStoreRecords || this.selectedStoreRecords.length == 0 );
	}
	

	connectedCallback() {
		this.Store_Form_Config_LABEL = JSON.parse(this.Store_Form_Config_LABEL);
		console.log('this.Store_Form_Config_LABEL==>',this.Store_Form_Config_LABEL);
		//Add this to show create / update in diff tab
		if (this.serviceActionFor === 'update') {
			this.getServicesWrapDataJS()
		} else {
			this.currentStep = 2;
		}
	}
	
	handleStoreData(event) {
		const { selectedStoreRecords, selectedStoreIds }  = event.detail;
		this.selectedStoreRecords = selectedStoreRecords || [];
		this.selectedStoreIds = selectedStoreIds || [];
	}

	handleNextBack(event) {
		const { name } = event.target;

		if (name == 'Next') {
           this.currentStep = String((Number(this.currentStep) + 1) ) ;


		} else if (name == 'Back') {
			this.listWrapServices = this.getChildListWrapServices();
			if (this.actionFor === 'create') {
				this.currentStep = String((Number(this.currentStep) - 1) ) ;

			} else {
				this.currentStep = '1';
			}
		}

	}

	async handleCreateServices(event) {
		event.preventDefault();
		event.stopPropagation();

		try {
			// Testing purpose for navigation Screen
			// console.log('1.currentStep==>',this.currentStep);
			// this.currentStep = String((Number(this.currentStep) + 1) ) ;
            // console.log('this.currentStep==>',this.currentStep);

			console.log('handleSave');
			let isAllValid =  this.checkAllvalidity();
			if (!isAllValid) {
				this.showToast('Error', 'Please fill all required fields', 'error');
				return;
			} else {
				this.showSpinner = true;
				let isSuccess = await this.createServices();
				if (isSuccess) {
					this.showToast('Success', 'Services have been saved successfully.', 'success');
					//this.currentStep = "1" ;
					setTimeout(() => {
						window.location.reload();
					}, 1100);
				} else {
					this.showToast('Error', 'An error occurred. Please contact the administrator.', 'error');
				}
			}
		} catch (error) {
			console.log('error==>',error);
		} finally {
           this.showSpinner = false;
        }
       
	}

	getChildListWrapServices() {
        let listWrapServices = [];
		let childEle =this.template.querySelector('c-service-create-edit-form');
		if (childEle) {
            listWrapServices = childEle.getListWrapServices();
		}
        return listWrapServices;
	}

	async createServices() {
		let listWrapServices = this.getChildListWrapServices();
		if (this.isIndicatorForCreate) {
			listWrapServices = this.buildRetainerServices(listWrapServices);
		}
		
		if (listWrapServices && listWrapServices.length > 0) {
			let objWrapServiceAllData = {
				oppId : this.recordId,
				listWrapServiceData : listWrapServices,
				retainerServiceIdsForDelete : this.retainerServiceIdsForDelete
			}
			let strWrapServiceAllData = JSON.stringify(objWrapServiceAllData);
			console.log('strWrapServiceAllData==>',strWrapServiceAllData);
			//return;

		 	let isSuccess = await upsertStoreAndServices({strWrapServiceAllData});
		  
			return isSuccess;
		}
	}

	buildRetainerServices(listWrapServices) {
		let tempListWrapServices = (listWrapServices || []).map((wrapService) => {

			const diffInDays = SHARED_JAVASCRIPT_CODE.diffInDays(wrapService.startDate , wrapService.endDate);
			console.log('diffInDays==>',diffInDays);
			const calMonths = wrapService.contractForMonth ? wrapService.contractForMonth : Number((diffInDays / 30).toFixed(2));

			let {integerPart, fractionPart, hasFraction} = SHARED_JAVASCRIPT_CODE.splitNumber(calMonths);
			wrapService.contractForMonth =  integerPart; //Math.float(calMonths);
			console.log(`integerPart: ${integerPart}, fractionPart: ${fractionPart}, hasFraction: ${hasFraction}, diffInDays: ${diffInDays}`);
            let is31Days = false;
			if (diffInDays < 32) {
                wrapService.contractForMonth = 1;
				is31Days = true;
			}

			if (!wrapService?.retainerServices?.length || !wrapService.endDate || !wrapService.startDate) {
				return wrapService;
			}

			const contractForMonth = Number(wrapService.contractForMonth);
			const baseStartDate = new Date(wrapService.startDate);

			let retainerServices = [];

			wrapService.retainerServices.forEach(item => {
	            
				// let eqDistribute = Math.ceil(
				// 	Number(item.numberOfCasesAllowedPerPeriod) / contractForMonth
				// );

			   let eqDistribute = Number(item.numberOfCasesAllowedPerPeriod);

				console.log('eqDistribute==>',eqDistribute);
				let currentDate = new Date(baseStartDate); 

				let startDateRS = wrapService.startDate;
				let endDateRS = wrapService.endDate;
				let startDateDefultDay = 0;
				let endDateDefultDay = 30;
				for (let i = 0; i < contractForMonth; i++) {
                    
					//if ( Number(i) != 0 && Number(contractForMonth) > (i+1)) {
						startDateRS = new Date(startDateRS);
                        startDateRS.setDate(startDateRS.getDate() + startDateDefultDay);
						console.log('0startDateDefultDay==>',startDateDefultDay);
                        console.log('startDateRS==>',startDateRS);
						//startDateDefultDay +=30;
                       
						endDateRS = new Date(endDateRS);

						if (contractForMonth > 1 ||  (hasFraction && !is31Days)) {
							endDateRS = new Date(startDateRS);
							console.log('000endDateRS==>',endDateRS);
							endDateRS.setDate(startDateRS.getDate() + Number(endDateDefultDay));
							//endDateRS.setDate(endDateRS.getDate() + endDateDefultDay);
							console.log('1startDateDefultDay==>',startDateDefultDay);
							console.log('endDateRS==>',endDateRS);
							
							//endDateDefultDay +=30;
						}
						
					//}

					//const monthName = currentDate.toLocaleString('en-US', { month: 'long' });
					//const month = currentDate.getMonth() + 1;
					//const year = currentDate.getFullYear();
					//console.log('month==>',month);
					retainerServices.push({
						...item,
						index: i + 1,
						// month,
						// year,
						startDate: startDateRS.toISOString().split('T')[0],
						endDate: endDateRS.toISOString().split('T')[0],
						numberOfCasesAllowedPerPeriod: eqDistribute
					});
					console.log('retainerServices==>',retainerServices);
					currentDate.setMonth(currentDate.getMonth() + 1); // ✅ fixed
					console.log('currentDate==>',currentDate);	
					startDateRS = new Date(endDateRS);
				}

				if (hasFraction && !is31Days) {
					const fractionPartInDay = (fractionPart * 30).toFixed(2);
                    const fractionAmount = +(fractionPart * eqDistribute).toFixed(2);
					startDateRS = new Date(endDateRS);
					startDateRS.setDate(startDateRS.getDate() + 1);

					//startDateDefultDay +=fractionPartInDay;

					endDateRS = new Date(startDateRS);
					endDateRS.setDate(endDateRS.getDate() + Number(fractionPartInDay));

					retainerServices.push({
						...item,
						index: contractForMonth + 1,
						startDate: startDateRS.toISOString().split('T')[0],
						endDate: endDateRS.toISOString().split('T')[0],
						numberOfCasesAllowedPerPeriod: fractionAmount
					});
                    
				}
			});

            wrapService.contractForMonth = is31Days ? 1 : calMonths;

			return {
				...wrapService,
				retainerServices
			};
		});

		console.log('tempListWrapServices ==>', tempListWrapServices);
		return tempListWrapServices;
    }

	checkAllvalidity() {
        return this.checkChildValidity();
    }

    checkChildValidity() {
		let isValidInput = false
        let childEle = this.template.querySelector('c-service-create-edit-form');
        console.log('childEle==>',childEle);
        if (childEle) {
            isValidInput = childEle.checkValidity();
		}
        return isValidInput;
    }

	showToast(title, message, variant) {
		const evt = new ShowToastEvent({
			title,
			message,
			variant,
		});
		this.dispatchEvent(evt);
	}

	// Screen 3 : Navigation code
	handleNavigation(event) {
        let {currentStep, actionFor}  = event.detail;
		console.log('currentStep==>',currentStep);
        // this.currentStep = currentStep;
		this.actionFor = actionFor;
		this.selectedStoreIds = [];
		this.selectedStoreRecords = [];
	}

	async getServicesWrapDataJS() {
		let strobjWrapAllData = await getServicesWrapData({recordId : this.recordId});
		let objWrapAllData = JSON.parse(strobjWrapAllData);
		console.log('objWrapAllData==>',objWrapAllData);
		this.listWrapServices = objWrapAllData.listWrapServiceData;
		console.log('getServicesWrapDataJS: listWrapServices==>',this.listWrapServices);
		setTimeout(() => {
			this.currentStep = '3';
		}, 400);
	}

	async handleCancelService(event) {
		const {serviceId} = event.detail;
		console.log('serviceId==>',serviceId);
		if (!SHARED_JAVASCRIPT_CODE.isEmpty(serviceId)) {
			const isSuccess = await cancelService({serviceId});
			if (isSuccess) {
                this.showToast('Success', 'Service has been cancelled successfully.', 'success');
				this.currentStep = 0;
					setTimeout(() => {
						this.currentStep = 3;
						this.getServicesWrapDataJS();
					}, 1);
			} else {
				console.error('Something went wrong while cancelling service.: '+serviceId);
				this.showToast('Error', 'Something went wrong while cancelling service.', 'error');
			}
		}

	}
}