import { LightningElement, api, wire } from "lwc";
import { getRecord} from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import { gql, graphql } from "lightning/graphql";
import {ShowToastEvent} from 'lightning/platformShowToastEvent';
import STORE_OBJECT from '@salesforce/schema/Store__c'; 
import ACCOUNTID_FIELD from '@salesforce/schema/Opportunity.AccountId';
import NO_STORES from '@salesforce/label/c.Store_available';

export default class StoreForm extends LightningElement {
	@api recordId;
	@api objectApiName;
	@api selectionMode = 'radio'; // radio or checkbox
	storeRecords = [];
	@api selectedStoreRecords = [];
	@api selectedStoreIds = [];
	recordTypeOptions = [];
	marketPlaceOptions = [];
    whiteGloveRecordTypeName = 'White Glove';

	@api storeCreationSource = 'OppStore'; // OppStore/OppCase/OppService
	marketPlace;
	swichInfoSecExistStrores = true;
	storeName;
	newStoreId;
	_refresh;
	errors;
	marketPlaces;
	selectedRecordTypeId = undefined;

	accountId;

	get storeCrreation (){
		return this.storeCreationSource === 'OppStore' || this.storeCreationSource === 'OppService' ;
	}

	get getExistingStoreColumns() {
        return [
           // { label: 'Store Name', fieldName: 'Name',  type: 'text', initialWidth: 150},
			{ label: 'Store Name', fieldName: 'recordUrl',  type: 'url',
				typeAttributes: {
                label: { fieldName: 'Name' }, // 👈 clickable text
                target: '_blank'               // open in same tab
            },
				initialWidth: 150},
			{ label: 'Marketplaces', fieldName: 'Marketplaces__c', type: 'text', initialWidth: 150},
            { label: 'Account', fieldName: 'Account__r', type: 'text', initialWidth: 150},
            { label: 'Account Type', fieldName: 'Account_Type_c__c', type: 'text', initialWidth: 150},
            { label: 'Seller Id', fieldName: 'Seller_ID__c', type: 'text', initialWidth: 110},
            { label: 'Status', fieldName: 'Status__c',  initialWidth: 100},
            { label: 'White Glove', fieldName: 'White_Glove__c', type: 'boolean', initialWidth: 100},
            { label: 'Created Date', fieldName: 'CreatedDate', type: 'date',
				typeAttributes: {
					year: 'numeric',month: 'short', day: '2-digit',
					hour: '2-digit', minute: '2-digit', second: '2-digit',
					hour12: true
				},
				initialWidth: 200
			},
        ]
    }

	get isDisbleCreateNewStoreBtn() {
		return !this.storeName || this.storeName == '' || !this.selectedRecordTypeId || this.selectedRecordTypeId == '' || this.selectedRecordTypeId == null;
	}

    get variables() {
        return {
            recordId: this.recordId,
			accountId: this.accountId
        };
    }

	get showStoreInstruction() {
		return  this.storeCreationSource 
			&& ['OppCase'].includes(this.storeCreationSource)
			&& (this.getStoreRecords || []).length == 0;
	}

	get isOppStore() {
		return this.storeCreationSource && ['OppService'].includes(this.storeCreationSource);
	}

	get showStoreSelection() {
		return this.storeCreationSource && ['OppStore'].includes(this.storeCreationSource);
	}

	get storeRecordTypeOptions() {
        let recordTypeOptions = [...(this.recordTypeOptions || [])];

		if (this.isOppStore) {
			return recordTypeOptions.filter(
				option => option.label === this.whiteGloveRecordTypeName
			);
		}

		return recordTypeOptions;
	}


	get getStoreRecords() {
		const records = [...(this.storeRecords || [])];

		if (this.isOppStore) {
			return records.filter(
				item => item.White_Glove__c === true && item.Opportunity__c
			);
		}

		return records;
	}


	setDefaultRecordType() {
		if (this.isOppStore && this.recordTypeOptions?.length) {

			const whiteGlove = this.recordTypeOptions.find(
				option => option.label === this.whiteGloveRecordTypeName
			);

			if (whiteGlove) {
				this.selectedRecordTypeId = whiteGlove.value;
			}
		}
	}

    @wire(getObjectInfo, { objectApiName: STORE_OBJECT })
	wireGetStoreInfo({ error, data }) {

		if (data) {
			try {
				const rtis = data.recordTypeInfos || {};

				this.recordTypeOptions = Object.keys(rtis)
				.filter(rtId => rtis[rtId].available && !rtis[rtId].master)
				.map(key => ({
					label: rtis[key].name,
					value: rtis[key].recordTypeId
				}));

				
				this.recordTypeOptions = [{label: '--None--', value: undefined}, ...this.recordTypeOptions];
				this.setDefaultRecordType();

			} catch (e) {
				console.error('Processing Error:', e);
			}

		} else if (error) {
			console.error('Wire Error:', error);
		}
	}

	@wire(getPicklistValuesByRecordType, {
		objectApiName: STORE_OBJECT,
		recordTypeId: '$selectedRecordTypeId',
	})
	wirePicklistStore({ error, data }) {
		if (!this.selectedRecordTypeId) {
			return;
		}
		console.log('Store Picklist data==>', data);
		if (data?.picklistFieldValues?.Marketplaces__c) { 
			let marketPlaceOptions = data.picklistFieldValues.Marketplaces__c.values.map(val => ({
				label: val.label,
				value: val.value
			})); 
			this.marketPlaceOptions = marketPlaceOptions;
			console.log('marketPlaceOptions==>', marketPlaceOptions);

			this.updateCustomLookupOptions( { 
				className: 'marketplace',
				options : [...this.marketPlaceOptions], 
				selectedOption :  this.marketPlace
			});
		}
		else if (error) {
			console.log('error==>', error);
		}
	}

	@wire(getRecord, {
        recordId: '$recordId',
        fields: [ACCOUNTID_FIELD]
    })
    wireOppRecordGet({data, error}) {
       
		if (data?.fields?.AccountId?.value) { 
            this.accountId = data?.fields?.AccountId?.value;
			console.log('this.accountId==>',this.accountId);
		} 

		if (error) {
            console.error('wireOppRecordGet Error:', error);
        }
	}

	// Query records by graph gql : start //
    @wire(graphql, {
        query: gql`
            query StoreByOpportunity($recordId: ID!, $accountId: ID ) {
                uiapi {
                    query {
                        Store__c(
						    first: 2000
                            where: {
								or: [
									{
										and: [
											{ Account__c: {eq: $accountId } }
										]
									},
									{ Opportunity__c: { eq: $recordId } },
									{ Id: { eq: $recordId } }
								]
							}
                        ) {
                            edges {
                                node {
                                    Id
                                    Name {
                                        value
                                    }
									Marketplaces__c { value }
									Account__r {
										... on Account {
											Id
											Name {
												value
											}
										}
                                    }
									Seller_ID__c { value }
									Status__c { value }
									White_Glove__c { value }
									CreatedDate { value }
									Opportunity__c { value }
                                }
                            }
                        }
                    }
                }
            }
        `,
        variables: '$variables'
    })
    graphqlQueryResult({ data, errors, refresh }) {
        if (data) {
            this.storeRecords = data.uiapi.query.Store__c.edges.map(
                edge => this.flattenUiApiNode(edge.node)
            );
            console.log(this.objectApiName,'--Records:', this.storeRecords);
			this.selectedStoreIds = [...this.selectedStoreIds];

	       setTimeout(() => {
			    this.checkStoreIdAndpassDataToParent();
		   }, 100);
        }

		if (refresh) {
           this._refresh = refresh;
		}

        if (errors) {
            this.errors = errors;
            console.error('GraphQL Errors:', errors);
        }

		console.log('this._refresh-1');
    }

	async refreshStoresTable() {
		if (this._refresh) {
		    await this._refresh();
		}
    }

	checkStoreIdAndpassDataToParent() {
		console.log('checkStoreIdAndpassDataToParent.storeRecords==>',this.storeRecords);
		if (this.recordId && this.recordId.startsWith("a0Q")) {
			let eventForStore = { 
				detail : { selectedRows :  [...this.storeRecords] } 
			}
			this.handleRowSelection(eventForStore);

		}
	}

	flattenUiApiNode(node) {
		const result = {};

		Object.keys(node).forEach(key => {
			const value = node[key];

			// UI API fields come as { value, displayValue }
			if (value && typeof value === 'object' && 'value' in value) {
				result[key] = value.value;
			} else if ( value && typeof value === 'object' && value.Name && value.Name.value) {
                result[key] = value.Name.value;
				if (value.Id) {
					result[`${key}_Id`] = value.Id;
				}
            } else {
				result[key] = value; // Id or other primitives
			}

			if (result['Name'] && result['Id'] ) {
                result['recordUrl'] = '/'+result['Id'];
			}
		});

		return result;
    }
	// Query records by graph gql : end //

	renderedCallback() {
		const container = this.template.querySelector('.store-message');

		if (container && !container.dataset.rendered) {

			const badge = document.createElement('div');
			badge.className = 'slds-box slds-theme_warning slds-m-around_small';
			badge.style.position = 'relative';
			badge.innerHTML = NO_STORES;

			//Utiltiy Close Icon
			const closeBtn = document.createElement('span');
			closeBtn.innerHTML = '&times;';
			closeBtn.style.position = 'absolute';
			closeBtn.style.right = '10px';
			closeBtn.style.top = '5px';
			closeBtn.style.cursor = 'pointer';
			closeBtn.style.fontSize = '16px';
			closeBtn.style.fontWeight = 'bold';

			closeBtn.addEventListener('click', () => {
				badge.remove(); 
			});

			badge.appendChild(closeBtn);
			container.appendChild(badge);

			container.dataset.rendered = true;
		}
    }

    handleInputChange(event) {
		this.storeName = event.target.value;
	}

	handlePicklistChange(event) {
		this.selectedRecordTypeId = event.detail.value;
	}

	getOppId() {
		if (this.recordId && this.recordId.startsWith("006")) {
			return this.recordId;
		} else if (this.storeRecords?.length > 0) {
			return this.storeRecords[0].Opportunity__c;
		}
	}

	handleSubmit(event) {
		event.preventDefault(); // stop default submit

		const fields = event.detail.fields;
        fields.Account__c = this.accountId;
		fields.Marketplaces__c = this.marketPlace;
		if (this.isOppStore) {
			fields.Opportunity__c = this.getOppId(); // inject lookup
		}

		this.template.querySelector('lightning-record-edit-form').submit(fields);
		
		setTimeout(() => {
			this.marketPlace = undefined;
			this.selectedRecordTypeId = undefined;
		    this.updateCustomLookupOptions( { 
				className: 'marketplace',
				options : [...this.marketPlaceOptions], 
				selectedOption :  this.marketPlace
		    });
			
		}, 200);
		
	}

	handleSuccess(event) {
       this.newStoreId = event.detail.id;
	   console.log('this.newStoreId==>',this.newStoreId);
	   this.showToast('Success', 'Store has been saved successfully.', 'success');
	   this.handleReset();
	   this.storeName = undefined;
	   this.refreshStoresTable();
	}

	handleReset(event) {
		const inputFields = this.template.querySelectorAll(
			'lightning-input-field'
		);
		if (inputFields) {
			inputFields.forEach(field => {
				field.reset();
			});
		}
	}

	handleRowSelection(event) {
		const selectedRows = event.detail.selectedRows;
		console.log('selectedRow==>',selectedRows);
		this.selectedStoreRecords = selectedRows;
		this.selectedStoreIds = selectedRows.map(row => row.Id);
		this.passDataToParent();
	}
	
	passDataToParent() {
		const storeSelectedEvent = new CustomEvent('storedata', {
			detail: {
				selectedStoreRecords: [...this.selectedStoreRecords],
				selectedStoreIds: [...this.selectedStoreIds],
				oppId : this.getOppId()
			}
		});
		this.dispatchEvent(storeSelectedEvent);
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
    }

	handleLookupSelectionChange(event) {  
        let {label, value, className} = event.detail;
        console.log(`label: ',${label}, value: ',${value}, className: ',${className} `);
	
        let cleaned = value ? (value+'').replace(/^"|"$/g, '') : undefined;
		this.marketPlace = cleaned;
    }

	handleLookupServerSearch(event) {
        let {className, searchTerm, value} = event.detail;
        console.log(`handleLookupServerSearch : searchTerm: ${searchTerm} , className: ${className}, value: ${value}`);
        if (searchTerm && searchTerm.length > 1 && className) {
        } 	
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