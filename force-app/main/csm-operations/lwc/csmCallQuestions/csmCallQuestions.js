import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getAnswers from '@salesforce/apex/CSMCallQuestionsController.getAnswers';
import saveAnswers from '@salesforce/apex/CSMCallQuestionsController.saveAnswers';
import getFollowUpTaskDefaults from '@salesforce/apex/CSMCallQuestionsController.getFollowUpTaskDefaults';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import NewUpsellOpportunityModal from 'c/newUpsellOpportunityModal';

const MOOD_OPTIONS = [
    { label: 'Happy', value: 'Happy' },
    { label: 'Assistance Needed', value: 'Assistance Needed' },
    { label: 'High Risk', value: 'High Risk' }
];
const YES_NO_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];

// type: mood = dropdown, yesno = Yes/No + comment. Extra buttons: task (Q2, Q4, Q5), upsell (Q6).
const QUESTIONS = [
    { number: 1, type: 'mood', text: 'Overall, how are you feeling about the service and progress on your account?' },
    { number: 2, type: 'yesno', task: true, text: 'Is there anything currently happening with the account that you feel needs more attention?' },
    { number: 3, type: 'yesno', text: 'Are you satisfied with the communication and updates from your assigned tech?' },
    { number: 4, type: 'yesno', task: true, text: 'Are there any open issues you feel have been pending too long?' },
    { number: 5, type: 'yesno', task: true, text: 'Is there anything you expected us to handle that you feel has not been addressed?' },
    { number: 6, type: 'upsell', text: 'Is there anything new happening with your Amazon account that we should know about?' },
    { number: 7, type: 'yesno', text: 'Is there anything else we can help you with right now?' }
];

export default class CsmCallQuestions extends NavigationMixin(LightningElement) {
    @api recordId;
    @api pricebookName = 'Service';

    answers = {}; // number -> { response, comment }
    isLoading = true;
    isSaving = false;
    isOpeningTask = false;
    isDirty = false;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.isLoading = true;
        try {
            const rows = await getAnswers({ callId: this.recordId });
            const map = {};
            rows.forEach((r) => {
                map[r.questionNumber] = { response: r.response || '', comment: r.comment || '' };
            });
            this.answers = map;
            this.isDirty = false;
        } catch (e) {
            this.toast('Could not load answers', this.message(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get questions() {
        return QUESTIONS.map((q) => {
            const a = this.answers[q.number] || { response: '', comment: '' };
            return {
                ...q,
                label: `${q.number}. ${q.text}`,
                isMood: q.type === 'mood',
                isYesNo: q.type === 'yesno',
                isUpsell: q.type === 'upsell',
                hasResponse: q.type !== 'upsell',
                options: q.type === 'mood' ? MOOD_OPTIONS : YES_NO_OPTIONS,
                response: a.response,
                comment: a.comment,
                showTask: !!q.task
            };
        });
    }

    get saveDisabled() {
        return !this.isDirty || this.isSaving;
    }

    handleResponse(event) {
        this.update(Number(event.target.dataset.number), 'response', event.detail.value);
    }

    handleComment(event) {
        this.update(Number(event.target.dataset.number), 'comment', event.detail.value);
    }

    update(number, field, value) {
        const current = this.answers[number] || { response: '', comment: '' };
        this.answers = { ...this.answers, [number]: { ...current, [field]: value } };
        this.isDirty = true;
    }

    async handleSave() {
        this.isSaving = true;
        try {
            await saveAnswers({
                callId: this.recordId,
                answers: QUESTIONS.map((q) => {
                    const a = this.answers[q.number] || {};
                    return { questionNumber: q.number, response: a.response || null, comment: a.comment || null };
                }),
                questionTexts: QUESTIONS.map((q) => q.text)
            });
            this.isDirty = false;
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.toast('Saved', 'Opportunity questions saved.', 'success');
        } catch (e) {
            this.toast('Save failed', this.message(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleCreateTask(event) {
        if (this.isOpeningTask) return;
        const answer = this.answers[Number(event.currentTarget.dataset.number)] || {};
        this.isOpeningTask = true;
        try {
            const defaults = await getFollowUpTaskDefaults({ callId: this.recordId });
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Task', actionName: 'new' },
                state: {
                    nooverride: '1',
                    defaultFieldValues: encodeDefaultFieldValues({
                        ...defaults,
                        Subject: 'CSM follow-up: account needs more attention',
                        Description: answer.comment || ''
                    })
                }
            });
        } catch (e) {
            this.toast('Could not open task', this.message(e), 'error');
        } finally {
            this.isOpeningTask = false;
        }
    }

    async handleUpsell() {
        await NewUpsellOpportunityModal.open({
            size: 'large',
            label: 'New Opportunity',
            recordId: this.recordId,
            pricebookName: this.pricebookName
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    message(e) {
        return e?.body?.message || e?.message || 'Unknown error';
    }
}