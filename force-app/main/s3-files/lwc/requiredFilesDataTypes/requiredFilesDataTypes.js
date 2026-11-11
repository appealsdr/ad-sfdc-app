import { LightningElement, api } from 'lwc';
import fileActionsTemplate from './fileActions.html';

export default class RequiredFilesDataTypes extends LightningElement {
    @api
    getDataTypes() {
        return {
            fileActions: {
                template: fileActionsTemplate,
                standardCellLayout: true,
                typeAttributes: ['documentId', 'rowActions']
            }
        };
    }
}
