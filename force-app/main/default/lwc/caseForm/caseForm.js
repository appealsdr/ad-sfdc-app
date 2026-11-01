import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Store_Form_Config_LABEL from '@salesforce/label/c.Store_Form_Config';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import getAllFieldSetInfo from '@salesforce/apex/CaseFormController.getAllFieldSetInfo';
import getPricingInfo from '@salesforce/apex/CaseFormController.getPricingInfo';
import upsertCases from '@salesforce/apex/CaseFormController.upsertCases';
import NO_STORES from '@salesforce/label/c.Store_available';
import { CurrentPageReference } from 'lightning/navigation';

export default class CaseForm extends LightningElement {
    Store_Form_Config_LABEL = Store_Form_Config_LABEL || {};
    @api recordId;
    @api objectApiName;
    @api currentStep = '1';
    @api actionFor = 'create'
    oppId;
    listWrapCases = [];
    @api recordTypeOptions = [];
    mapRtIdAndName = [];
    listRtLabel;
    selectedStoreRecords = [];
    selectedStoreIds = [];
    caseFieldSetWrap = [];
    mapServiceTypePrice = {};

    showSpinner = false;

    @api
    set pageReference(value) {

        this._pageReference = value;

        // Component isn't necessarily re-created so reset
        //this.parentRecordId = null;

        // See e.g. https://sfdclesson.com/2019/11/23/get-parent-record-id-from-lightning-url/
        if (this.pageReference) {
            let base64Context = this.pageReference?.state?.inContextOfRef;
            if (base64Context) {
                if (base64Context.startsWith("1\.")) {
                    base64Context = base64Context.substring(2);
                    this.originalPageReference = JSON.parse(atob(base64Context));

                    // Extract whatever is needed here; just the parent id in this example
                    // This data can be used to do further querying bofore the navigation if needed
                    const recordId = this.originalPageReference?.attributes?.recordId;
                    this.recordId = recordId;
                    console.log('this.recordId==>', this.recordId);
                    console.log(this.currentStep + '--this.showNextBtn==>', this.showNextBtn);
                }
            }
        }


    }
    get pageReference() {
        return this._pageReference;
    }
    _pageReference;


    handleRecordPicker(event) {
        let selectedRecordId = event.detail.recordId;
        let objectApiName = event.target.objectApiName;
        this.oppId = selectedRecordId;
    }

    get getRecordId() {
        return this.recordId ? this.recordId : this.oppId;
    }

    getOppId() {
        if (this.recordId && this.recordId.startsWith("006")) {
            return this.recordId;
        } else {
            return this.oppId;
        }
    }

    get showOpportunityLookup() {
        return !this.recordId && this.currentStep == '1';
    }

    get labelForAction() {
        return this.actionFor === 'create' ? 'Create Cases' : 'Update Cases';
    }

    get showNextBtn() {
        return this.currentStep
            && !this.isStoreRecordId
            && [1].includes(Number(this.currentStep))
            && this.getRecordId;
    }

    get showBackBtn() {
        return this.actionFor === 'create'
            && !this.isStoreRecordId
            && (this.currentStep && [2].includes(Number(this.currentStep)));
    }

    get showCreateUpdateBtn() {
        return (this.currentStep && Number(this.currentStep) === 2);
    }

    get showStoreScreen() {
        return this.currentStep === '1' && this.getRecordId
    }

    get showCaseScreen() {
        return this.currentStep === '2'
    }

    get isDisabledNextBtn() {
        return !this.selectedStoreRecords || this.selectedStoreRecords.length == 0;
    }

    get isStoreRecordId() {
        return this.recordId && this.recordId.startsWith("a0Q");
    }

    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    objectInfo({ data, error }) {
        let listRtLabel = [];
        if (data) {
            const rtInfos = data.recordTypeInfos;
            let mapRtIdAndName = {};
            this.recordTypeOptions = Object.keys(rtInfos)
                .filter(rtId => rtInfos[rtId].available && !rtInfos[rtId].master) // only accessible RTs
                .map(rtId => {
                    //mapRtIdAndName.set(rtId, rtInfos[rtId].name);
                    listRtLabel.push(rtInfos[rtId].name);
                    mapRtIdAndName[rtId] = rtInfos[rtId].name;
                    return {
                        label: rtInfos[rtId].name,
                        value: rtId
                    };
                });
            this.mapRtIdAndName = mapRtIdAndName;
            this.listRtLabel = listRtLabel;
            console.log('Case Record Types:', this.recordTypeOptions);
        } else if (error) {
            console.error(error);
        }
    }

    @wire(getAllFieldSetInfo)
    wiredDataCaseFieldSet({ error, data }) {
        if (data) {
            this.caseFieldSetWrap = data;
            // ([...data] || []).map((item) => {
            //     item.fields = item.fields || [];
            // });
            console.log('caseFieldSetWrap: ', this.caseFieldSetWrap);
        } else if (error) {
            console.error('Error:', error);
        }
    }

    @wire(getPricingInfo, { listRtLabel: '$listRtLabel' })
    wiredData({ error, data }) {
        if (data) {
            this.mapServiceTypePrice = data;
            console.log('mapServiceTypePrice==>', this.mapServiceTypePrice);
        } else if (error) {
            console.error('Error:', error);
        }
    }

    handleNextBack(event) {
        const { name } = event.target;
        if (name == 'Next') {
            this.currentStep = String((Number(this.currentStep) + 1));
        } else if (name == 'Back') {
            this.getlistWrapCases();
            this.currentStep = String((Number(this.currentStep) - 1));
        }

    }

    handleStoreData(event) {
        const { selectedStoreRecords, selectedStoreIds, oppId } = event.detail;
        this.selectedStoreRecords = selectedStoreRecords || [];
        this.selectedStoreIds = selectedStoreIds || [];
        this.oppId = oppId;
        this.openCaseCreateScreen();
    }

    openCaseCreateScreen() {
        console.log('this.isStoreRecordId==>', this.isStoreRecordId);
        if (this.isStoreRecordId) {
            this.currentStep = '2';
        }
    }




    async handleUpsertCases(event) {
        event.preventDefault();
        event.stopPropagation();

        try {

            console.log('handleUpsertCases');
            let isAllValid = this.checkAllvalidity();
            console.log('isAllValid==>', isAllValid);
            if (!isAllValid) {
                this.showToast('Error', 'Please fill all required fields', 'error');
                return;
            } else {
                this.showSpinner = true;
                let isSuccess = await this.upsertCasesJS();
                if (isSuccess) {
                    this.showToast('Success', 'Cases have been saved successfully.', 'success');
                    setTimeout(() => {
                        window.location.reload();
                    }, 1100);
                } else {
                    this.showToast('Error', 'An error occurred. Please contact the administrator.', 'error');
                }
            }
        } catch (error) {

            let errorMessage = 'An error occurred. Please contact the administrator.';
            if (error.body) {
                if (Array.isArray(error.body.pageErrors) && error.body.pageErrors.length > 0) {
                    errorMessage = error.body.pageErrors[0].message;
                } else if (error.body.message) {
                    errorMessage = error.body.message;
                }
            }

            this.showToast('Error', errorMessage, 'error');
            console.log('error==>', error);
        } finally {
            this.showSpinner = false;
        }
    }

    async upsertCasesJS() {
        var oppId = this.getOppId();
        console.log('oppId==>', oppId);
        let strWrapCaseAllData = JSON.stringify(this.getlistWrapCases());
        console.log('---strWrapCaseAllData==>', strWrapCaseAllData);
        let isSuccess = await upsertCases({ strWrapCaseAllData, oppId });
        return isSuccess;
    }

    @api getlistWrapCases() {
        let listWrapCases = [];
        let childEle = this.template.querySelector('c-case-create-edit-form');
        if (childEle) {
            listWrapCases = childEle.getlistWrapCases();
        }

        this.listWrapCases = listWrapCases;
        return this.listWrapCases;
    }


    checkAllvalidity() {
        return this.checkChildValidity();
    }

    checkChildValidity() {
        let isValidInput = false
        let childEle = this.template.querySelector('c-case-create-edit-form');
        console.log('childEle==>', childEle);
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


}