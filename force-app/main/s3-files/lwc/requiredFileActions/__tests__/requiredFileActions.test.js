import { createElement } from 'lwc';
import RequiredFileActions from 'c/requiredFileActions';

const ACTIONS = [
    { label: 'Preview', name: 'preview' },
    { label: 'View', name: 'view' }
];
const flushPromises = () => Promise.resolve();

function mountComponent(actions = ACTIONS) {
    const element = createElement('c-required-file-actions', { is: RequiredFileActions });
    element.documentId = 'uploaded-document';
    element.actions = actions;
    document.body.appendChild(element);
    return element;
}

describe('c-required-file-actions', () => {
    afterEach(() => {
        document.body.replaceChildren();
    });

    it('omits the menu for folders without actions', () => {
        const element = mountComponent([]);

        expect(element.shadowRoot.querySelector('lightning-button-menu')).toBeNull();
    });

    it('renders the available actions and follows the tree-grid keyboard tab order', async () => {
        const element = mountComponent();
        const menu = element.shadowRoot.querySelector('lightning-button-menu');
        expect(menu.alternativeText).toBe('File actions');
        expect(menu.menuAlignment).toBe('auto');
        expect(menu.tabIndex).toBe(-1);
        expect(menu.dataset.navigation).toBe('enable');
        expect([...element.shadowRoot.querySelectorAll('lightning-menu-item')]
            .map((item) => ({ label: item.label, value: item.value })))
            .toEqual(ACTIONS.map((action) => ({ label: action.label, value: action.name })));

        element.internalTabIndex = 0;
        await flushPromises();

        expect(menu.tabIndex).toBe(0);
    });

    it.each(ACTIONS)('forwards the selected $name action with its document id', (action) => {
        const element = mountComponent();
        const handler = jest.fn();
        const selectHandler = jest.fn();
        element.addEventListener('fileaction', handler);
        element.addEventListener('select', selectHandler);

        element.shadowRoot.querySelector('lightning-button-menu').dispatchEvent(new CustomEvent('select', {
            detail: { value: action.name },
            bubbles: true,
            composed: true
        }));

        expect(handler).toHaveBeenCalledTimes(1);
        const event = handler.mock.calls[0][0];
        expect(event.detail).toEqual({ documentId: 'uploaded-document', action });
        expect(event.bubbles).toBe(true);
        expect(event.composed).toBe(true);
        expect(selectHandler).not.toHaveBeenCalled();
    });

    it('does not forward an action that is unavailable for the row', () => {
        const element = mountComponent();
        const handler = jest.fn();
        element.addEventListener('fileaction', handler);

        element.shadowRoot.querySelector('lightning-button-menu').dispatchEvent(new CustomEvent('select', {
            detail: { value: 'delete' }
        }));

        expect(handler).not.toHaveBeenCalled();
    });
});
