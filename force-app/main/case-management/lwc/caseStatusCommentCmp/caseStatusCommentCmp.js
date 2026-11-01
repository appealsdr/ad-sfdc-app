import { LightningElement, api, track, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import STATUS_FIELD from '@salesforce/schema/Case.Status';
import getDefaultComment from '@salesforce/apex/CaseStatusCommentController.getDefaultComment';
import saveCaseUpdate from '@salesforce/apex/CaseStatusCommentController.saveCaseUpdate';
import getMessages from '@salesforce/apex/CaseStatusCommentController.getMessages'; // make sure method name matches Apex
//import getPicklistValues from '@salesforce/apex/CaseStatusCommentController.getPicklistValues';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class CaseStatusCommentCmp extends LightningElement {
    @api recordId;

    @track status = '';
    @track comment = '';
    @track internalOnly = false;

    @track sortAscending = true; // Track sort order
    @track sortIconName = 'utility:arrowdown'; // Initial icon

    @track commentOption = 'default';
    @track commentOptions = [];
   // searchable decorator
  //  @track selectedStatus;
    @track searchKey = '';
    @track isDropdownOpen = false;
    @track filteredStatusOptions = [];
    outsideClickHandler;

    @track statusOptions = [];
    @track commentTableData = [];
    @track selectedRowIds = [];
    @track selectedDefault = false;

    // Track all recent comments as an array of objects with unique keys
    @track recentComments = [];
    @track currentUserName;
    @track isInternal = false;

    wiredMessagesResult;

    @track commentTableColumns = [
        { label: 'Comment', fieldName: 'defaultComment', type: 'text' }
    ];

    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    caseObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$caseObjectInfo.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    statusPicklistValues({ error, data }) {
        if (data) {
            this.statusOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
            this.filteredStatusOptions = [...this.statusOptions];    

        } else if (error) {
            console.error('Error loading status picklist: ', error);
        }
    } 
   get comboboxClass() {
    return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${
        this.isDropdownOpen ? 'slds-is-open' : ''
    }`;
}

    openDropdown(event) {
        event.stopPropagation();
        this.isDropdownOpen = true;
        this.filterOptions();
    }

    handleSearch(event) {
    event.stopPropagation();
    this.searchKey = event.target.value;
    this.isDropdownOpen = true;
    this.filterOptions();
    }

    filterOptions() {
        const key = this.searchKey.toLowerCase();

        this.filteredStatusOptions = this.statusOptions.map(opt => ({
            ...opt,
            selected: opt.value === this.status
        })).filter(opt =>
            opt.label.toLowerCase().includes(key)
        );
    }

    handleSelect(event) {
            const value = event.currentTarget.dataset.value;
            const selected = this.statusOptions.find(opt => opt.value === value);

            this.status = selected.value;
            this.searchKey = selected.label;
            this.isDropdownOpen = false;

            // Existing logic call
            //this.handleStatusChange({ detail: { value: this.status } });
            this.handleStatusChange();
            
        }

        get noResult() {
            return this.filteredStatusOptions.length === 0;
        }

        connectedCallback() {
            this.outsideClickHandler = this.handleOutsideClick.bind(this);
            document.addEventListener('click', this.outsideClickHandler);
        }
        disconnectedCallback() {
        document.removeEventListener('click', this.outsideClickHandler);
        }

        handleOutsideClick(event) {
            const combobox = this.template.querySelector('[data-id="status-combobox"]');

            if (!combobox) return;

            // agar click combobox ke bahar hua
            if (!combobox.contains(event.target)) {
                this.isDropdownOpen = false;
            }
        }




    handleStatusChange() {
       // this.status = event.target.value;
    
        getDefaultComment({ statusValue: this.status })
            .then(result => {
                const comments = result[this.status] || [];

                if (comments.length > 0) {
                    this.commentOptions = [
                        { label: 'Use Template', value: 'default' },
                        { label: 'Other (Write My Own)', value: 'other' }
                    ];
                    this.commentOption = 'default';
                    this.selectedDefault = true;

                    this.commentTableData = comments.map((comment, index) => ({
                        id: index + 1,
                        defaultComment: comment
                    }));

                    this.comment = comments[0];
                    this.selectedRowIds = [1];
                } else {
                    this.commentOptions = [
                        { label: 'Other (Write My Own)', value: 'other' }
                    ];
                    this.commentOption = 'other';
                    this.commentTableData = [];
                    this.comment = '';
                    this.selectedDefault = false;
                }
            })
            .catch(error => {
                console.error('Error fetching default comments:', error);
                this.commentOptions = [
                    { label: 'Other (Write My Own)', value: 'other' }
                ];
                this.commentOption = 'other';
                this.commentTableData = [];
                this.comment = '';
                this.selectedDefault = false;
            });
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        if (selectedRows.length > 0) {
            this.comment = selectedRows[0].defaultComment;
            this.selectedRowIds = [selectedRows[0].id];
        }
    }

    handleCommentOptionChange(event) {
        this.commentOption = event.detail.value;
        this.selectedDefault = this.commentOption === 'default';
        if (!this.selectedDefault) this.comment = '';
    }

    handleCommentChange(event) {
        this.comment = event.target.value;
    }

    handleInternalChange(event) {
        this.internalOnly = event.target.checked;
    }

    @wire(getMessages, { recordId: '$recordId' })
    wiredMessages(result) {
        this.wiredMessagesResult = result;
        const { data, error } = result;

        if (data) {
            this.recentComments = data.map(msg => ({
                id: msg.id,
                status: msg.status,
                SourceType: msg.SourceType,
                Incoming: msg.Incoming,
                isInternal: msg.internalComment,
                comment: msg.comment,
                sender: msg.senderUserName,
                //formattedDate: msg.createdDate ? new Date(msg.createdDate).toLocaleString() : ''
                formattedDate: msg.createdDate
                    ? new Date(msg.createdDate).toLocaleString('en-US', {
                        month: '2-digit',
                        day: '2-digit',
                        year: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit',
                        hour12: true // shows AM/PM
                    })
                    : ''


            }));

            // Set default status from latest comment
            if (this.recentComments.length > 0) {
                const latest = this.recentComments[this.recentComments.length - 1];
                this.status = latest.status;
            }

        } else if (error) {
            console.error('Error fetching case messages:', error);
            this.messages = [];
        }
    }


    handleSave() {
        if (!this.status || !this.comment) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please select a status and enter a comment.',
                variant: 'error'
            }));
            return;
        }

        saveCaseUpdate({
            caseId: this.recordId,
            statusValue: this.status,
            commentBody: this.comment,
            internalOnly: this.internalOnly
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Case updated and comment saved.',
                    variant: 'success'
                }));

                return refreshApex(this.wiredMessagesResult);
            })
            .then(() => {
                 this.status = '';
                this.comment = '';
                this.searchKey = '';
                this.internalOnly = false;
                this.commentOption = '';
                this.commentOptions = [];
                this.commentTableData = [];
                this.selectedRowIds = [];
                this.selectedDefault = false; 

                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'An error occurred.',
                    variant: 'error'
                }));
            });
    }


    handleCancel() {
        this.showModal = false;
    }

    handleConfirm() {
        this.showModal = false;
        this.modalConfirmed = true;
        this.handleSave();
    }


    handleSortClick() {

         this.sortAscending = !this.sortAscending;
        this.sortIconName = this.sortAscending ? 'utility:arrowdown' : 'utility:arrowup';

         this.recentComments = [...this.recentComments].sort((a, b) => {
            const dateA = new Date(a.formattedDate);
            const dateB = new Date(b.formattedDate);

            return this.sortAscending
                ? dateA - dateB   
                : dateB - dateA;  
        });
    }

}