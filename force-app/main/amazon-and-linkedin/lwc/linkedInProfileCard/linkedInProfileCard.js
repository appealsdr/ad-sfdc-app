import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getProfileInfo from '@salesforce/apex/LinkedInProfileController.getProfileInfo';

const TYPE_LABELS = {
    company: 'Company',
    person: 'Person',
    school: 'School',
    showcase: 'Showcase Page'
};

export default class LinkedInProfileCard extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api urlField;
    @api fieldPath;
    @api cardTitle = 'LinkedIn';

    record;
    recordError;
    profile;
    profileError;
    wiredProfileResult;
    imageFailed = false;
    showFullDescription = false;

    get qualifiedField() {
        const path = (this.fieldPath || this.urlField || '').trim();
        if (!path || !this.objectApiName) {
            return undefined;
        }
        const prefix = `${this.objectApiName}.`;
        return path.startsWith(prefix) ? path : prefix + path;
    }

    get optionalFields() {
        return this.qualifiedField ? [this.qualifiedField] : undefined;
    }

    @wire(getRecord, { recordId: '$recordId', optionalFields: '$optionalFields' })
    wiredRecord({ data, error }) {
        this.record = data;
        this.recordError = error;
    }

    get linkedInUrl() {
        if (!this.record || !this.qualifiedField) {
            return undefined;
        }
        const value = getFieldValue(this.record, this.qualifiedField);
        return value ? String(value).trim() : undefined;
    }

    @wire(getProfileInfo, { linkedInUrl: '$linkedInUrl' })
    wiredProfile(result) {
        this.wiredProfileResult = result;
        this.profile = result.data;
        this.profileError = result.error;
        this.imageFailed = false;
        this.showFullDescription = false;
    }

    // ----- view state -----

    get notConfigured() {
        return !this.qualifiedField;
    }

    get isLoading() {
        if (this.notConfigured || this.recordError) {
            return false;
        }
        if (!this.record) {
            return true;
        }
        return Boolean(this.linkedInUrl) && !this.profile && !this.profileError;
    }

    get isEmpty() {
        return !this.notConfigured && Boolean(this.record) && !this.linkedInUrl;
    }

    get errorMessage() {
        const error = this.recordError || this.profileError;
        if (error) {
            return error.body?.message || error.message || 'Unknown error';
        }
        if (this.profile && !this.profile.isValid) {
            return this.profile.errorMessage;
        }
        return undefined;
    }

    get showProfile() {
        return Boolean(this.profile?.isValid) && !this.isLoading;
    }

    get showFallbackNotice() {
        return this.showProfile && !this.profile.fetched;
    }

    get fallbackNotice() {
        return this.isPerson
            ? 'LinkedIn only shows personal profiles to signed-in members. Open it on LinkedIn to see the full profile.'
            : "LinkedIn didn't share public details for this page right now. Open it on LinkedIn to see everything.";
    }

    get typeLabel() {
        return TYPE_LABELS[this.profile?.profileType] || 'LinkedIn';
    }

    get showImage() {
        return Boolean(this.profile?.imageUrl) && !this.imageFailed;
    }

    get initials() {
        const name = this.profile?.name || '';
        return name
            .split(/\s+/)
            .filter(Boolean)
            .slice(0, 2)
            .map((w) => w[0].toUpperCase())
            .join('');
    }

    get hasDetails() {
        const p = this.profile || {};
        return Boolean(p.currentCompany || p.connections || p.followers || p.employees || p.location || p.website);
    }

    get hasExperience() {
        return this.profile?.experience?.length > 0;
    }

    get hasEducation() {
        return this.profile?.education?.length > 0;
    }

    get languagesText() {
        return (this.profile?.languages || []).join(', ');
    }

    get awardsText() {
        return (this.profile?.awards || []).join(', ');
    }

    get isPerson() {
        return this.profile?.profileType === 'person';
    }

    get descriptionLabel() {
        return this.isPerson ? 'About' : 'Overview';
    }

    get descriptionClass() {
        return this.showFullDescription ? 'description' : 'description description_clamped';
    }

    get isLongDescription() {
        return (this.profile?.description || '').length > 220;
    }

    get descriptionToggleLabel() {
        return this.showFullDescription ? 'Show less' : 'Show more';
    }

    // ----- handlers -----

    handleImageError() {
        this.imageFailed = true;
    }

    toggleDescription() {
        this.showFullDescription = !this.showFullDescription;
    }

    openLinkedIn() {
        window.open(this.profile.url, '_blank', 'noopener');
    }

    handleRefresh() {
        if (this.wiredProfileResult) {
            refreshApex(this.wiredProfileResult);
        }
    }
}