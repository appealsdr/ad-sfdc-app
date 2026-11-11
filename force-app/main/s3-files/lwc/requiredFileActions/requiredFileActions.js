import { LightningElement, api } from 'lwc';

export default class RequiredFileActions extends LightningElement {
    @api documentId;
    @api actions = [];
    @api internalTabIndex = -1;

    get hasActions() {
        return this.actions?.length > 0;
    }

    handleSelect(event) {
        event.stopPropagation();
        const action = this.actions.find((entry) => entry.name === event.detail.value);
        if (action) {
            this.dispatchEvent(new CustomEvent('fileaction', {
                detail: { documentId: this.documentId, action: { ...action } },
                bubbles: true,
                composed: true
            }));
        }
    }
}
