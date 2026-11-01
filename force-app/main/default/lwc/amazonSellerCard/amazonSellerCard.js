import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getSellerInfo from '@salesforce/apex/AmazonSellerController.getSellerInfo';

export default class AmazonSellerCard extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api sellerField;
    @api fieldPath;
    @api cardTitle = 'Amazon Seller';
    @api showFeedback = false;
    @api feedbackCount = 5;

    record;
    recordError;
    seller;
    sellerError;
    wiredSellerResult;
    logoFailed = false;
    showFullAbout = false;

    get qualifiedField() {
        const path = (this.fieldPath || this.sellerField || '').trim();
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

    get sellerRef() {
        if (!this.record || !this.qualifiedField) {
            return undefined;
        }
        const value = getFieldValue(this.record, this.qualifiedField);
        return value ? String(value).trim() : undefined;
    }

    @wire(getSellerInfo, { sellerRef: '$sellerRef' })
    wiredSeller(result) {
        this.wiredSellerResult = result;
        this.seller = result.data;
        this.sellerError = result.error;
        this.logoFailed = false;
        this.showFullAbout = false;
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
        return Boolean(this.sellerRef) && !this.seller && !this.sellerError;
    }

    get isEmpty() {
        return !this.notConfigured && Boolean(this.record) && !this.sellerRef;
    }

    get errorMessage() {
        const error = this.recordError || this.sellerError;
        if (error) {
            return error.body?.message || error.message || 'Unknown error';
        }
        if (this.seller && !this.seller.isValid) {
            return this.seller.errorMessage;
        }
        return undefined;
    }

    get showSeller() {
        return Boolean(this.seller?.isValid) && !this.isLoading;
    }

    get showFallbackNotice() {
        return this.showSeller && !this.seller.fetched;
    }

    get displayName() {
        return this.seller?.name || `Seller ${this.seller?.sellerId}`;
    }

    get showLogo() {
        return Boolean(this.seller?.logoUrl) && !this.logoFailed;
    }

    get hasRating() {
        return this.seller?.rating !== undefined && this.seller?.rating !== null;
    }

    get starStyle() {
        const pct = Math.max(0, Math.min(100, ((this.seller?.rating || 0) / 5) * 100));
        return `width: ${pct}%`;
    }

    get positiveText() {
        const s = this.seller;
        if (!s?.positivePercent && s?.positivePercent !== 0) {
            return undefined;
        }
        return `${s.positivePercent}% positive${s.positivePeriod ? ' ' + s.positivePeriod : ''}`;
    }

    get ratingPeriods() {
        return (this.seller?.ratingPeriods || []).map((p) => ({
            ...p,
            ratingText: p.count === '0' ? '—' : `${p.rating} ★`
        }));
    }

    get hasRatingPeriods() {
        return this.ratingPeriods.length > 0;
    }

    get histogram() {
        return (this.seller?.histogram || []).map((bar) => ({
            ...bar,
            barStyle: `width: ${bar.percent}%`
        }));
    }

    get hasHistogram() {
        return this.histogram.length > 0;
    }

    get hasDetails() {
        return (this.seller?.details || []).length > 0 || Boolean(this.seller?.phone);
    }

    get aboutClass() {
        return this.showFullAbout ? 'about' : 'about about_clamped';
    }

    get isLongAbout() {
        return (this.seller?.about || '').length > 260;
    }

    get aboutToggleLabel() {
        return this.showFullAbout ? 'Show less' : 'Show more';
    }

    get feedback() {
        const limit = Number(this.feedbackCount) || 5;
        return (this.seller?.feedback || []).slice(0, limit).map((f) => ({
            ...f,
            starsText: f.stars ? '★'.repeat(Math.round(f.stars)) + '☆'.repeat(5 - Math.round(f.stars)) : '',
            starsClass: f.stars >= 4 ? 'fb-stars fb-stars_good' : f.stars <= 2 ? 'fb-stars fb-stars_bad' : 'fb-stars'
        }));
    }

    get hasFeedback() {
        return this.showFeedback && this.feedback.length > 0;
    }

    // ----- handlers -----

    handleLogoError() {
        this.logoFailed = true;
    }

    toggleAbout() {
        this.showFullAbout = !this.showFullAbout;
    }

    openUrl(event) {
        window.open(event.currentTarget.dataset.url, '_blank', 'noopener');
    }

    handleRefresh() {
        if (this.wiredSellerResult) {
            refreshApex(this.wiredSellerResult);
        }
    }
}