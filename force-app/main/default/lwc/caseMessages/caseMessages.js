import { LightningElement, api, wire, track } from 'lwc';
import { gql, graphql } from 'lightning/graphql';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveCaseMessage from '@salesforce/apex/CaseMessagesController.saveCaseMessage';
import markMessageRead from '@salesforce/apex/CaseMessagesController.markMessageRead';

const ALLOWED_RICH_TEXT_FORMATS = 'bold, italic, underline, strike, list, indent, link, clean';
const MAX_VISIBLE_MESSAGES = 25;

const CASE_MESSAGES_QUERY = gql`
    query CaseMessages($recordId: ID!) {
        uiapi {
            query {
                Case_Message__c(
                    first: 2000
                    where: { Case__c: { eq: $recordId } }
                    orderBy: { CreatedDate: { order: ASC } }
                ) {
                    edges {
                        node {
                            Id
                            Message_Body__c {
                                value
                            }
                            Sender_Type__c {
                                value
                            }
                            CreatedDate {
                                value
                            }
                            Sender_User__r {
                                Name {
                                    value
                                }
                            }
                            Sender_Contact__r {
                                Name {
                                    value
                                }
                            }
                            Reply_To_Message__c {
                                value
                            }
                            Message_Read__c {
                                value
                            }
                        }
                    }
                }
            }
        }
    }
`;

export default class CaseMessages extends LightningElement {
    @api recordId;

    @track messages = [];
    @track searchTerm = '';
    @track newMessage = '';
    @track selectedMessage = null;
    @track replyToMessage = null;

    isLoading = true;
    isSaving = false;
    isRefreshing = false;
    shouldScrollToBottom = false;
    hasScrolledToLatest = false;
    showMessageModal = false;
    refreshMessagesQuery;
    caseMessagesQuery = CASE_MESSAGES_QUERY;
    richTextFormats = ALLOWED_RICH_TEXT_FORMATS;
    readInFlightIds = new Set();
    fadingMessageIds = new Set();

    get graphqlVariables() {
        return this.recordId ? { recordId: this.recordId } : undefined;
    }

    get hasSelectedMessage() {
        return this.selectedMessage != null;
    }

    get isReplying() {
        return this.replyToMessage != null;
    }

    @wire(graphql, {
        query: '$caseMessagesQuery',
        variables: '$graphqlVariables'
    })
    wiredCaseMessages(result) {
        if (typeof result.refresh === 'function') {
            this.refreshMessagesQuery = result.refresh;
        }

        if (!this.recordId) {
            this.isLoading = false;
            this.messages = [];
            return;
        }

        const { data, error } = result;

        if (data) {
            this.isLoading = false;
            const edges = data.uiapi?.query?.Case_Message__c?.edges || [];
            const nodes = edges.map(({ node }) => node);
            const plainTextById = new Map();
            nodes.forEach((node) => {
                plainTextById.set(node.Id, this.stripHtml(this.normalizeMessageHtml(node.Message_Body__c?.value || '')));
            });
            this.messages = nodes.map((node) => this.mapNode(node, plainTextById));

            if (this.shouldScrollToBottom || !this.hasScrolledToLatest) {
                this.shouldScrollToBottom = false;
                this.hasScrolledToLatest = true;
                this.scrollToLatestMessage();
            }
        } else if (error) {
            this.isLoading = false;
            console.error('Error fetching case messages:', error);
            this.messages = [];
            this.showToast('Error', 'Unable to load messages.', 'error');
        }
    }

    mapNode(node, plainTextById) {
        const rawMessageBody = node.Message_Body__c?.value || '';
        const messageBody = this.normalizeMessageHtml(rawMessageBody);
        const senderType = node.Sender_Type__c?.value;
        const createdDate = node.CreatedDate?.value;
        const senderName =
            node.Sender_User__r?.Name?.value ||
            node.Sender_Contact__r?.Name?.value ||
            'Unknown';
        const isInternal = senderType === 'Internal';
        const plainText = this.stripHtml(messageBody);
        const replyToMessageId = node.Reply_To_Message__c?.value || null;
        const replySnippet = replyToMessageId ? plainTextById.get(replyToMessageId) : null;
        const messageReadValue = node.Message_Read__c?.value || null;
        const isUnread = !isInternal && !messageReadValue;
        const isFading = this.fadingMessageIds.has(node.Id);

        let rowClass = isInternal ? 'message-row message-row-internal' : 'message-row message-row-external';
        if (isUnread) {
            rowClass += ' message-row-unread';
        } else if (isFading) {
            rowClass += ' message-row-fading';
        }

        return {
            id: node.Id,
            messageBody,
            searchableText: plainText,
            senderType,
            isInternal,
            typeLabel: isInternal ? 'Internal' : 'External',
            senderName,
            senderInitials: this.getInitials(senderName),
            rowClass,
            formattedDate: createdDate ? this.formatTimestamp(createdDate) : '',
            fullFormattedDate: createdDate ? this.formatFullTimestamp(createdDate) : '',
            replyToMessageId,
            hasReply: Boolean(replyToMessageId),
            replySnippet: replySnippet ? this.truncate(replySnippet, 80) : null,
            messageRead: messageReadValue,
            isUnread,
            readLabel: messageReadValue ? `Read ${this.formatFullTimestamp(messageReadValue)}` : null
        };
    }

    truncate(text, maxLength) {
        if (!text || text.length <= maxLength) {
            return text;
        }
        return `${text.slice(0, maxLength).trim()}…`;
    }

    getInitials(name) {
        if (!name) {
            return '?';
        }
        const parts = name.trim().split(/\s+/);
        if (parts.length === 1) {
            return parts[0].charAt(0).toUpperCase();
        }
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }

    formatTimestamp(value) {
        return new Date(value).toLocaleString('en-US', {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
    }

    formatFullTimestamp(value) {
        return new Date(value).toLocaleString('en-US', {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            year: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
    }

    get isSearching() {
        return (this.searchTerm || '').trim().length > 0;
    }

    get visibleMessages() {
        const messages = this.filteredMessages;
        if (this.isSearching || messages.length <= MAX_VISIBLE_MESSAGES) {
            return messages;
        }
        return messages.slice(-MAX_VISIBLE_MESSAGES);
    }

    get hasHiddenMessages() {
        return !this.isSearching && this.messages.length > MAX_VISIBLE_MESSAGES;
    }

    get hiddenMessageCount() {
        return Math.max(this.messages.length - MAX_VISIBLE_MESSAGES, 0);
    }

    get filteredMessages() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.messages;
        }

        return this.messages.filter((message) => {
            const sender = (message.senderName || '').toLowerCase();
            const body = (message.searchableText || '').toLowerCase();
            const type = (message.typeLabel || '').toLowerCase();
            return sender.includes(term) || body.includes(term) || type.includes(term);
        });
    }

    get noMessages() {
        return !this.isLoading && this.messages.length === 0;
    }

    get noSearchResults() {
        return !this.isLoading && this.messages.length > 0 && this.filteredMessages.length === 0;
    }

    get showLatestMessagesHint() {
        return this.hasHiddenMessages && !this.isSearching;
    }

    get latestMessagesHintText() {
        return `Showing the latest ${MAX_VISIBLE_MESSAGES} messages (${this.hiddenMessageCount} older hidden). Use search to find older messages.`;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleRefreshClick() {
        this.refreshMessages();
    }

    async refreshMessages() {
        if (!this.refreshMessagesQuery || this.isRefreshing) {
            if (!this.refreshMessagesQuery) {
                this.showToast('Error', 'Unable to refresh messages.', 'error');
            }
            return;
        }

        this.isRefreshing = true;
        try {
            await this.refreshMessagesQuery();
        } catch (error) {
            console.error('Error refreshing case messages:', error);
            this.showToast('Error', 'Unable to refresh messages.', 'error');
        } finally {
            this.isRefreshing = false;
        }
    }

    handleInputChange(event) {
        this.newMessage = this.normalizeMessageHtml(event.detail.value);
    }

    handleMessageClick(event) {
        const messageId = event.currentTarget.dataset.id;
        const message = this.messages.find((item) => item.id === messageId);
        if (!message) {
            return;
        }
        this.selectedMessage = message;
        this.showMessageModal = true;
        this.markMessageAsRead(message);
    }

    handleMessageKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleMessageClick(event);
        }
    }

    handleCloseMessageModal() {
        this.showMessageModal = false;
        this.selectedMessage = null;
    }

    handleReplyClick(event) {
        event.stopPropagation();
        const messageId = event.currentTarget.dataset.id;
        const message = this.messages.find((item) => item.id === messageId);
        if (!message) {
            return;
        }
        this.replyToMessage = message;
        this.template.querySelector('.message-input-rich-text')?.focus();
    }

    handleCancelReply() {
        this.replyToMessage = null;
    }

    markMessageAsRead(message) {
        if (!message || message.isInternal || message.messageRead || this.readInFlightIds.has(message.id)) {
            return;
        }

        this.readInFlightIds.add(message.id);
        markMessageRead({ messageId: message.id })
            .then(async () => {
                this.fadingMessageIds.add(message.id);
                if (this.refreshMessagesQuery) {
                    await this.refreshMessagesQuery();
                }
                setTimeout(() => {
                    this.fadingMessageIds.delete(message.id);
                    this.messages = this.messages.map((item) =>
                        item.id === message.id ? { ...item, rowClass: item.rowClass.replace(' message-row-fading', '') } : item
                    );
                }, 5000);
            })
            .catch((error) => {
                console.error('Error marking message read:', error);
            })
            .finally(() => {
                this.readInFlightIds.delete(message.id);
            });
    }

    handleComposerKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSendClick();
        }
    }

    handleSendClick() {
        if (!this.recordId) {
            this.showToast('Error', 'Case record is not available.', 'error');
            return;
        }

        const normalizedMessage = this.normalizeMessageHtml(this.newMessage);

        if (this.isBlankRichText(normalizedMessage)) {
            this.showToast('Error', 'Please enter a message before sending.', 'error');
            return;
        }

        this.isSaving = true;
        const replyToMessageId = this.replyToMessage?.id || null;
        saveCaseMessage({ caseId: this.recordId, messageBody: normalizedMessage, replyToMessageId })
            .then(async () => {
                this.showToast('Success', 'Message sent successfully!', 'success');
                this.newMessage = '';
                this.replyToMessage = null;
                this.shouldScrollToBottom = true;
                if (this.refreshMessagesQuery) {
                    await this.refreshMessagesQuery();
                }
                this.scrollToLatestMessage();
            })
            .catch((error) => {
                console.error(error);
                this.showToast('Error', this.reduceErrors(error), 'error');
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    reduceErrors(error) {
        if (!error) {
            return 'Error while saving message';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (typeof error.body?.message === 'string') {
            return error.body.message;
        }
        if (typeof error.message === 'string') {
            return error.message;
        }
        return 'Error while saving message';
    }

    scrollToLatestMessage() {
        requestAnimationFrame(() => {
            const container = this.template.querySelector('.messages-container');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        });
    }

    normalizeMessageHtml(value) {
        if (!value) {
            return '';
        }

        let result = value;
        result = result.replace(/<font[^>]*>/gi, '').replace(/<\/font>/gi, '');
        result = result.replace(/\sstyle="[^"]*(font-size|font-family)[^"]*"/gi, (match) => {
            const cleanedStyle = match
                .replace(/font-size\s*:\s*[^;"]+;?/gi, '')
                .replace(/font-family\s*:\s*[^;"]+;?/gi, '')
                .replace(/style="\s*"/gi, '');
            return cleanedStyle.includes('style=""') ? '' : cleanedStyle;
        });
        result = result.replace(/<(h1|h2|h3|h4|h5|h6)([^>]*)>/gi, '<p$2>').replace(/<\/(h1|h2|h3|h4|h5|h6)>/gi, '</p>');
        return result;
    }

    isBlankRichText(value) {
        if (!value) {
            return true;
        }
        return this.stripHtml(value).length === 0;
    }

    stripHtml(value) {
        if (!value) {
            return '';
        }
        return value
            .replace(/<[^>]+>/g, ' ')
            .replace(/&nbsp;/gi, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}