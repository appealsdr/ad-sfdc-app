import { createElement } from 'lwc';
import RequiredFiles from 'c/requiredFiles';
import getRequiredFiles from '@salesforce/apex/RequiredFileController.getRequiredFiles';
import getDocumentAccess from '@salesforce/apex/S3DocumentController.getDocumentAccess';
import { refreshApex } from '@salesforce/apex';

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn().mockResolvedValue() }), { virtual: true });

jest.mock(
    '@salesforce/apex/RequiredFileController.getRequiredFiles',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/RequiredFileController.getDocumentTemplates',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/RequiredFileController.createRequiredFileDefault',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/RequiredFileController.createRequiredFileFromTemplate',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/S3DocumentController.getDocumentAccess',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    'lightning/navigation',
    () => {
        const Navigate = Symbol('Navigate');
        const NavigationMixin = (Base) => class extends Base {
            [Navigate](pageReference) {
                this.dispatchEvent(new CustomEvent('navigate', { detail: pageReference }));
            }
        };
        NavigationMixin.Navigate = Navigate;
        return { NavigationMixin };
    },
    { virtual: true }
);

const FILES = [
    {
        id: 'identity',
        rowType: 'requiredFile',
        name: 'Identity documents',
        shortDescription: 'Government ID and signed forms',
        fileUploaded: true,
        uploadedLabel: 'Yes',
        lastVersionId: 'agreement',
        uploadedFileName: 'agreement.docx',
        uploadedFiles: [
            {
                id: 'passport',
                name: 'passport.pdf',
                shortDescription: 'Photo identification',
                canPreview: true
            },
            {
                id: 'agreement',
                name: 'agreement.docx',
                shortDescription: 'Executed agreement',
                canPreview: false
            }
        ]
    },
    {
        id: 'billing',
        rowType: 'requiredFile',
        name: 'Billing documents',
        shortDescription: 'Monthly charges',
        fileUploaded: true,
        uploadedLabel: 'Yes',
        uploadedFiles: [
            { id: 'invoice', name: 'invoice.pdf', shortDescription: 'October invoice', canPreview: true }
        ]
    },
    {
        id: 'pending',
        rowType: 'requiredFile',
        name: 'Pending statement',
        shortDescription: 'Awaiting upload',
        fileUploaded: false,
        uploadedLabel: 'No',
        uploadedFiles: []
    },
    {
        id: 'standalone-evidence',
        rowType: 'uploadedFile',
        name: 'extra-evidence.pdf',
        shortDescription: 'Supplemental evidence',
        fileUploaded: true,
        uploadedLabel: 'Yes',
        canPreview: true,
        uploadedFiles: []
    }
];

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function mountComponent() {
    const element = createElement('c-required-files', { is: RequiredFiles });
    element.recordId = '500000000000001AAA';
    document.body.appendChild(element);
    return element;
}

function tree(element) {
    return element.shadowRoot.querySelector('lightning-tree-grid');
}

async function search(element, value) {
    const input = element.shadowRoot.querySelector('.toolbar lightning-input');
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

function openRow(element, row) {
    tree(element).dispatchEvent(new CustomEvent('rowaction', {
        detail: { action: { name: 'open' }, row }
    }));
}

function runRowAction(element, name, row) {
    tree(element).dispatchEvent(new CustomEvent('rowaction', {
        detail: { action: { name }, row }
    }));
}

describe('c-required-files tree view', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.restoreAllMocks();
        jest.clearAllMocks();
    });

    it('shows required-file folders with their uploads alongside standalone document leaves', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        const grid = tree(element);
        expect(grid.keyField).toBe('id');
        expect(grid.hideCheckboxColumn).toBe(true);
        expect(grid.columnWidthsMode).toBe('fixed');
        expect(grid.columns.map((column) => column.label)).toEqual([
            'File Name', 'Short Description', 'Uploaded', undefined
        ]);
        expect(grid.columns[0].initialWidth).toBe(420);
        expect(grid.data).toHaveLength(4);
        expect(grid.data[0].rowType).toBe('requiredFile');
        expect(grid.data[0].iconName).toBe('utility:open_folder');
        expect(grid.data[0].name).toBe('Identity documents (2)');
        expect(grid.data[0].rowActions).toEqual([]);
        expect(grid.data[0].uploadCount).toBe(2);
        expect(grid.data[0]._children.map((row) => row.name)).toEqual(['passport.pdf', 'agreement.docx']);
        expect(grid.data[0]._children.map((row) => row.documentId)).toEqual(['passport', 'agreement']);
        expect(grid.data[0]._children[0].id).not.toBe(grid.data[0].id);
        expect(grid.data[1]._children.map((row) => row.name)).toEqual(['invoice.pdf']);
        expect(grid.data[2].uploadCount).toBe(0);
        expect(grid.data[2]._children).toBeUndefined();
        expect(grid.data[3]).toMatchObject({
            id: 'standalone-evidence',
            documentId: 'standalone-evidence',
            name: 'extra-evidence.pdf',
            rowType: 'uploadedFile',
            iconName: 'utility:file',
            rowActions: [
                { label: 'Preview', name: 'preview' },
                { label: 'View', name: 'view' }
            ]
        });
        expect(grid.data[3]._children).toBeUndefined();
    });

    it('shows standalone uploads when the record has no required-file folders', async () => {
        const element = mountComponent();
        getRequiredFiles.emit([FILES[3]]);
        await flushPromises();

        expect(tree(element).data).toHaveLength(1);
        expect(tree(element).data[0].documentId).toBe('standalone-evidence');
        expect(tree(element).data[0]._children).toBeUndefined();
        expect(element.shadowRoot.querySelector('.empty-state')).toBeNull();
    });

    it('refreshes the file tree from the card action', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        const refreshButton = element.shadowRoot.querySelector('lightning-button-icon');
        expect(refreshButton.iconName).toBe('utility:refresh');
        expect(refreshButton.alternativeText).toBe('Refresh files');
        refreshButton.click();
        await flushPromises();

        expect(refreshApex).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelector('lightning-tree-grid').data).toHaveLength(4);
    });

    it.each(['  EXTRA-EVIDENCE.PDF  ', 'supplemental evidence'])('finds standalone documents by %s without expanding a folder', async (term) => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        await search(element, term);

        expect(tree(element).data.map((row) => row.documentId)).toEqual(['standalone-evidence']);
        expect(tree(element).data[0]._children).toBeUndefined();
        expect(tree(element).expandedRows).toEqual([]);
    });

    it('searches all uploaded names, keeps the parent, and expands matching children', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        await search(element, '  PASSPORT.PDF  ');

        expect(tree(element).data.map((row) => row.id)).toEqual(['identity']);
        expect(tree(element).data[0]._children.map((row) => row.documentId)).toEqual(['passport']);
        expect(tree(element).expandedRows).toEqual(['identity']);
    });

    it('searches uploaded descriptions while excluding nonmatching sibling uploads', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        await search(element, 'executed agreement');

        expect(tree(element).data).toHaveLength(1);
        expect(tree(element).data[0]._children.map((row) => row.documentId)).toEqual(['agreement']);
    });

    it.each(['Identity documents', 'government id'])('keeps the full subtree when the requirement matches %s', async (term) => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        await search(element, term);

        expect(tree(element).data).toHaveLength(1);
        expect(tree(element).data[0]._children).toHaveLength(2);
        expect(tree(element).expandedRows).toEqual(['identity']);
    });

    it('still searches the upload status of requirements without uploads', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        await search(element, 'no');

        expect(tree(element).data.map((row) => row.id)).toEqual(['pending']);
        expect(tree(element).expandedRows).toEqual([]);
    });

    it('finds uploaded folders and standalone documents by upload status', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        await search(element, 'yes');

        expect(tree(element).data.map((row) => row.id)).toEqual(['identity', 'billing', 'standalone-evidence']);
        expect(tree(element).data[2].uploadedLabel).toBe('Yes');
        expect(tree(element).data[2]._children).toBeUndefined();
        expect(tree(element).expandedRows).toEqual(['identity', 'billing']);
    });

    it('restores all uploads and the previous expanded rows after clearing a search', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();
        tree(element).dispatchEvent(new CustomEvent('toggle', {
            detail: { name: 'billing', isExpanded: true }
        }));
        await flushPromises();
        expect(tree(element).expandedRows).toEqual(['billing']);

        await search(element, 'passport');
        expect(tree(element).expandedRows).toEqual(['identity']);
        await search(element, '  ');

        expect(tree(element).data).toHaveLength(4);
        expect(tree(element).data[0]._children).toHaveLength(2);
        expect(tree(element).expandedRows).toEqual(['billing']);
    });

    it('shows an explicit no-match state and recovers when the search is cleared', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        await search(element, 'missing-file.xyz');
        expect(tree(element)).toBeNull();
        expect(element.shadowRoot.querySelector('.empty-state').textContent).toContain('match your search');

        await search(element, '');
        expect(tree(element).data).toHaveLength(4);
    });

    it('opens the required file record when a parent name is selected', async () => {
        const element = mountComponent();
        const navigate = jest.fn();
        element.addEventListener('navigate', navigate);
        getRequiredFiles.emit(FILES);
        await flushPromises();

        openRow(element, tree(element).data[0]);

        expect(navigate).toHaveBeenCalledTimes(1);
        expect(navigate.mock.calls[0][0].detail).toEqual({
            type: 'standard__recordPage',
            attributes: { recordId: 'identity', objectApiName: 'Required_File__c', actionName: 'view' }
        });
        expect(getDocumentAccess).not.toHaveBeenCalled();
    });

    it('previews the selected older upload instead of the requirement last version', async () => {
        getDocumentAccess.mockResolvedValue({
            url: 'https://example.com/passport.pdf',
            previewType: 'PDF',
            isPreviewable: true,
            contentType: 'application/pdf'
        });
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        openRow(element, tree(element).data[0]._children[0]);
        await flushPromises();

        expect(getDocumentAccess).toHaveBeenCalledWith({ documentId: 'passport', accessType: 'preview' });
        expect(element.shadowRoot.querySelector('h2').textContent).toBe('passport.pdf');
        expect(element.shadowRoot.querySelector('iframe').src).toBe('https://example.com/passport.pdf');
        const layoutItems = element.shadowRoot.querySelectorAll('lightning-layout-item');
        expect(layoutItems[0].size).toBe('3');
        expect(layoutItems[1].size).toBe('9');
        const navigation = element.shadowRoot.querySelector('lightning-vertical-navigation');
        expect(navigation.selectedItem).toBe('document:passport');
        const navigationItems = element.shadowRoot.querySelectorAll(
            'lightning-vertical-navigation-item-icon'
        );
        expect(navigationItems[0].label).toBe('Identity documents (2)');
        expect(navigationItems[0].iconName).toBe('utility:open_folder');
        expect(navigationItems[1].label).toBe('↳ passport.pdf');
        expect(navigationItems[1].iconName).toBe('utility:file');
    });

    it('switches the preview and highlighted navigation item when another document is selected', async () => {
        getDocumentAccess
            .mockResolvedValueOnce({
                url: 'https://example.com/passport.pdf',
                previewType: 'PDF',
                isPreviewable: true,
                contentType: 'application/pdf'
            })
            .mockResolvedValueOnce({
                url: 'https://example.com/invoice.pdf',
                previewType: 'PDF',
                isPreviewable: true,
                contentType: 'application/pdf'
            });
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        openRow(element, tree(element).data[0]._children[0]);
        await flushPromises();
        const navigation = element.shadowRoot.querySelector('lightning-vertical-navigation');
        navigation.dispatchEvent(new CustomEvent('select', {
            detail: { name: 'document:invoice' }
        }));
        await flushPromises();

        expect(getDocumentAccess).toHaveBeenNthCalledWith(2, {
            documentId: 'invoice', accessType: 'preview'
        });
        expect(navigation.selectedItem).toBe('document:invoice');
        expect(element.shadowRoot.querySelector('h2').textContent).toBe('invoice.pdf');
    });

    it('closes the preview from the header close icon', async () => {
        getDocumentAccess.mockResolvedValue({
            url: 'https://example.com/passport.pdf',
            previewType: 'PDF',
            isPreviewable: true,
            contentType: 'application/pdf'
        });
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        openRow(element, tree(element).data[0]._children[0]);
        await flushPromises();
        const closeIcon = [...element.shadowRoot.querySelectorAll('lightning-button-icon')]
            .find((button) => button.alternativeText === 'Close preview');
        expect(closeIcon).not.toBeNull();
        closeIcon.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.preview-modal-container')).toBeNull();
    });

    it('previews and downloads standalone uploads using their document id', async () => {
        getDocumentAccess.mockResolvedValueOnce({
            url: 'https://example.com/extra-evidence.pdf',
            previewType: 'PDF',
            isPreviewable: true,
            contentType: 'application/pdf'
        }).mockResolvedValueOnce({ url: 'https://example.com/extra-evidence-download.pdf' });
        const openWindow = jest.spyOn(window, 'open').mockImplementation(() => null);
        const element = mountComponent();
        const navigate = jest.fn();
        element.addEventListener('navigate', navigate);
        getRequiredFiles.emit(FILES);
        await flushPromises();

        openRow(element, tree(element).data[3]);
        await flushPromises();

        expect(getDocumentAccess).toHaveBeenNthCalledWith(1, {
            documentId: 'standalone-evidence', accessType: 'preview'
        });
        expect(navigate).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('h2').textContent).toBe('extra-evidence.pdf');
        expect(element.shadowRoot.querySelector('iframe').src).toBe('https://example.com/extra-evidence.pdf');
        const download = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((button) => button.label === 'Download');
        download.click();
        await flushPromises();

        expect(getDocumentAccess).toHaveBeenNthCalledWith(2, {
            documentId: 'standalone-evidence', accessType: 'download'
        });
        expect(openWindow).toHaveBeenCalledWith('https://example.com/extra-evidence-download.pdf', '_blank');
    });

    it('opens Preview from a document action without navigating', async () => {
        getDocumentAccess.mockResolvedValue({
            url: 'https://example.com/passport.pdf',
            previewType: 'PDF',
            isPreviewable: true,
            contentType: 'application/pdf'
        });
        const element = mountComponent();
        const navigate = jest.fn();
        element.addEventListener('navigate', navigate);
        getRequiredFiles.emit(FILES);
        await flushPromises();

        runRowAction(element, 'preview', tree(element).data[0]._children[0]);
        await flushPromises();

        expect(getDocumentAccess).toHaveBeenCalledWith({ documentId: 'passport', accessType: 'preview' });
        expect(element.shadowRoot.querySelector('h2').textContent).toBe('passport.pdf');
        expect(navigate).not.toHaveBeenCalled();
    });

    it('keeps the preview modal open and shows the S3 access error', async () => {
        getDocumentAccess.mockRejectedValue({ body: { message: 'No file URL is available.' } });
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        openRow(element, tree(element).data[3]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-modal')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent)
            .toContain('No file URL is available.');
        expect(element.shadowRoot.querySelector('h2').textContent).toBe('extra-evidence.pdf');
    });

    it('opens View from a document action on the S3 document record', async () => {
        const element = mountComponent();
        const navigate = jest.fn();
        element.addEventListener('navigate', navigate);
        getRequiredFiles.emit(FILES);
        await flushPromises();

        runRowAction(element, 'view', tree(element).data[0]._children[0]);

        expect(navigate).toHaveBeenCalledTimes(1);
        expect(navigate.mock.calls[0][0].detail).toEqual({
            type: 'standard__recordPage',
            attributes: { recordId: 'passport', objectApiName: 'S3_Document__c', actionName: 'view' }
        });
        expect(getDocumentAccess).not.toHaveBeenCalled();
    });

    it('allows downloading the selected upload when a preview is unavailable', async () => {
        getDocumentAccess.mockResolvedValueOnce({
            url: 'https://example.com/agreement.docx', previewType: 'None', isPreviewable: false
        }).mockResolvedValueOnce({ url: 'https://example.com/agreement-download.docx' });
        const openWindow = jest.spyOn(window, 'open').mockImplementation(() => null);
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();

        openRow(element, tree(element).data[0]._children[1]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.preview-content').textContent).toContain('Preview is not available');
        const download = [...element.shadowRoot.querySelectorAll('lightning-button')]
            .find((button) => button.label === 'Download');
        download.click();
        await flushPromises();

        expect(getDocumentAccess).toHaveBeenNthCalledWith(2, { documentId: 'agreement', accessType: 'download' });
        expect(openWindow).toHaveBeenCalledWith('https://example.com/agreement-download.docx', '_blank');
    });

    it('clears stale rows after a load error and accepts subsequent data', async () => {
        const element = mountComponent();
        getRequiredFiles.emit(FILES);
        await flushPromises();
        expect(tree(element).data).toHaveLength(4);

        getRequiredFiles.error({ message: 'Unable to load required files' });
        await flushPromises();
        expect(tree(element)).toBeNull();

        getRequiredFiles.emit(FILES);
        await flushPromises();
        expect(tree(element).data).toHaveLength(4);
    });
});
