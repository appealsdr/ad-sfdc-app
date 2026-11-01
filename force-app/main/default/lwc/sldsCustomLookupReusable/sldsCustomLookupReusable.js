import { LightningElement, api } from "lwc";
export default class SldsCustomLookupReusable extends LightningElement {
	@api recordId;
	@api objectApiName;
    selectedItem = '';
	selectedValue = '';
	@api className = ''
	@api label = 'Search Input..';
	@api placeholder = 'Search Input..';
	searchTerm = '';
	debounceTimer;
	
	@api required = false;
	@api isDisabled = false;
	noResults = false;
	isOpen = false;
	options = [];
    optionsCopy = [];

	@api open(){
		if (!this.isDisabled) this.isOpen = true;
	}

	@api close(){
        this.isOpen = false;
	}

	@api setOptions(newOptions = []) {
		this.options = Array.isArray(newOptions) ? newOptions : [];
        this.optionsCopy = JSON.parse(JSON.stringify(this.options));
		this.filterOptions();
        console.log('setOptions=>');
    }

    @api setSelectedValues(value) {
		this.selectedValue = value;
		this.setSelectedItem();
    }
	
	setSelectedItem() {
		this.selectedItem = this.options.find(item => item.value === this.selectedValue)?.label;
		console.log('this.selectedValue==>',this.selectedValue);
		console.log('this.selectedItem==>',this.selectedItem);
	}



	handleOptionClick(evt) {
		console.log('handleOptionClick');
		evt.preventDefault();
		evt.stopPropagation();
		this.selectedValue  = evt.currentTarget.dataset.value;
		console.log('this.selectedValue==>',this.selectedValue);
		this.setSelectedItem();
		console.log('selectedItem==>',this.selectedItem);
		this.dispatchSelectionChange();
		this.close();

	}

	handleSearchInput(evt) {
		this.searchTerm = evt.target.value;
		console.log('handleSearchInput==>',this.searchTerm);
        this.open();

		if (!this.searchTerm || this.searchTerm == '') {
            this.syncOnBlank();
			return;
		}
        // debounce filter
        window.clearTimeout(this.debounceTimer);
        this.debounceTimer = window.setTimeout(() => {
            this.filterOptions();
            // If server side search required, emit event
            if (this.noResults) {
                this.dispatchEvent(new CustomEvent('search', { 
                    detail: { 
                        searchTerm: this.searchTerm, 
                        className : this.className,
                        value: this.selectedValue
                    } 
                }));
            }
        }, 220);
    }

	syncOnBlank() {
		this.selectedValue = undefined;
		this.selectedItem= undefined;
        this.options = [...this.optionsCopy];
        this.noResults = false;
        this.dispatchSelectionChange();
	}

	filterOptions() {
		const term = (this.searchTerm || '').trim().toLowerCase();
		if (!term) {
		    this.options = this.options.slice(0, 1000); // show first N as needed
		} else {
		    this.options = this.options.filter(o => (o.label || '').toLowerCase().includes(term));
		}

		this.noResults = this.options.length === 0;
    }

	dispatchSelectionChange() {
		this.dispatchEvent(new CustomEvent('selectionchange', {
		    detail: { label: this.selectedItem, value: this.selectedValue, className : this.className }
		}));
    }

	stopClose(event) {
		console.log('stopClose');
		event.preventDefault();
		event.stopPropagation();
    } 

	handleKeyDown(evt) {
		if (this.isDisabled) return;
		switch (evt.key) {
			case 'ArrowDown':
				evt.preventDefault();
				this.open();
				break;
			case 'ArrowUp':
				evt.preventDefault();
				this.open();
				break;
			case 'Enter':
				break;
			case 'Escape':
				this.close();
				break;
			case 'Backspace':
				break;
			default:
				break;
		}
    }
}