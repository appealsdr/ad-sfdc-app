@IsTest
private class AmazonSellerControllerTest {

    private class AmazonMock implements HttpCalloutMock {
        private Integer status;
        private String body;
        public String lastEndpoint;

        AmazonMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            lastEndpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    // Trimmed copy of the real seller profile markup.
    private static final String SELLER_HTML =
        '<html><head><title>Amazon.com Seller Profile: Test Supplies</title></head><body>' +
        '<div id="seller-logo-column"><img alt="" src="https://m.media-amazon.com/images/I/logo.jpg" class="seller-logo-img" id="seller-logo-img"/></div>' +
        '<h1 id="seller-name">Test Supplies &amp; Co</h1>' +
        '<div id="seller-info-feedback-summary" class="a-row"><a href="#"><i class="a-icon a-star-4-5"><span class="a-icon-alt">4.5 out of 5 stars</span></i>' +
        '<b>91% positive</b> lifetime (6047 total ratings)</a></div>' +
        '<div id="seller-phone-number"><span>Customer Service Phone: </span><span id="seller-contact-phone" dir="ltr">718-369-0600</span></div>' +
        '<span id="effective-timeperiod-rating-thirty-description" class="ratings-reviews">0</span>' +
        '<div id="rating-thirty-num" class="a-row"><span class="ratings-reviews-count">0</span><span>ratings</span></div>' +
        '<span id="effective-timeperiod-rating-year-description" class="ratings-reviews">1</span>' +
        '<div id="rating-365d-num" class="a-row"><span class="ratings-reviews-count">2</span><span>ratings</span></div>' +
        '<span id="effective-timeperiod-rating-lifetime-description" class="ratings-reviews">4.6</span>' +
        '<div id="rating-lifetime-num" class="a-row"><span class="ratings-reviews-count">6,047</span><span>ratings</span></div>' +
        '<table id="ratingHistogram"><tr><td><span id="percentFiveStar">84% </span></td></tr>' +
        '<tr><td><span id="percentFourStar">8% </span></td></tr><tr><td><span id="percentOneStar">6% </span></td></tr></table>' +
        '<div id="page-section-about-seller"><h3>About Seller</h3>' +
        '<div class="a-row spp-expander-less-content"><p> Short about...</p></div>' +
        '<div class="a-row spp-expander-more-content hide-content"><p>Full about text.</p><p>Second paragraph.</p> </div></div>' +
        '<div id="page-section-detail-seller-info" class="a-row a-spacing-none"><div class="a-column a-span12 a-spacing-none">' +
        '<div class="a-box a-spacing-none a-color-base-background box-section"><div class="a-box-inner a-padding-medium">' +
        '<!-- Detailed Seller Information --> <h3>Detailed Seller Information</h3>' +
        '<div class="a-row a-spacing-none"><span class="a-text-bold">Business Name: </span><span>TEST SUPPLIES INC.</span></div>' +
        '<div class="a-row a-spacing-none"><span class="a-text-bold">Business Address: </span></div>' +
        '<div class="a-row a-spacing-none indent-left"><span>999 3RD AVE</span></div>' +
        '<div class="a-row a-spacing-none indent-left"><span>BROOKLYN</span></div>' +
        '<div class="a-row a-spacing-none indent-left"><span>US</span></div>' +
        '<!-- Detailed Seller Information --> </div>' +
        '<div id="feedback-table">' +
        '<!-- Each Individual Feedback Record --> <div class="feedback-row"><i class="a-icon a-star-1"><span class="a-icon-alt">1 out of 5 stars</span></i>' +
        '<div class="feedback-text"><span id="-text" class="a-text-quote">Late delivery</span></div>' +
        '<span class="a-size-small feedback-rater">By AG on April 7, 2026.</span></div>' +
        '<!-- Each Individual Feedback Record --> <div class="feedback-row"><i class="a-icon a-star-5"><span class="a-icon-alt">5 out of 5 stars</span></i>' +
        '<span class="expandable-text a-text-quote"><span id="-truncated" class="expandable-truncated-text">Great seller, fast...</span>' +
        '<span id="-expanded" class="expandable-expanded-text">Great seller, fast shipping.</span></span>' +
        '<span class="a-size-small feedback-rater">By Amazon Customer on February 12, 2026.</span></div>' +
        '</div></body></html>';

    @IsTest
    static void parsesSellerProfile() {
        AmazonMock mock = new AmazonMock(200, SELLER_HTML);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        AmazonSellerController.SellerInfo info =
            AmazonSellerController.getSellerInfo('https://www.amazon.com/sp?ie=UTF8&seller=A009584315LPZVWG8ZCM5&tab=feedback');
        Test.stopTest();

        Assert.areEqual('https://www.amazon.com/sp?seller=A009584315LPZVWG8ZCM5', mock.lastEndpoint);
        Assert.isTrue(info.fetched);
        Assert.areEqual('A009584315LPZVWG8ZCM5', info.sellerId);
        Assert.areEqual('https://www.amazon.com/s?me=A009584315LPZVWG8ZCM5', info.storefrontUrl);
        Assert.areEqual('Test Supplies & Co', info.name);
        Assert.areEqual('https://m.media-amazon.com/images/I/logo.jpg', info.logoUrl);
        Assert.areEqual('718-369-0600', info.phone);
        Assert.areEqual(91, info.positivePercent);
        Assert.areEqual('lifetime', info.positivePeriod);
        Assert.areEqual(4.6, info.rating);
        Assert.areEqual('6,047', info.ratingCount);
        Assert.areEqual(3, info.ratingPeriods.size());
        Assert.areEqual('12 months', info.ratingPeriods[1].label);
        Assert.areEqual('2', info.ratingPeriods[1].count);
        Assert.areEqual(3, info.histogram.size());
        Assert.areEqual(84, info.histogram[0].percent);
        Assert.areEqual('Full about text.\nSecond paragraph.', info.about);

        Assert.areEqual(2, info.details.size());
        Assert.areEqual('Business Name', info.details[0].label);
        Assert.areEqual('TEST SUPPLIES INC.', info.details[0].value);
        Assert.areEqual('Business Address', info.details[1].label);
        Assert.areEqual('999 3RD AVE\nBROOKLYN\nUS', info.details[1].value);

        Assert.areEqual(2, info.feedback.size());
        Assert.areEqual(1, info.feedback[0].stars);
        Assert.areEqual('Late delivery', info.feedback[0].text);
        Assert.areEqual('By AG on April 7, 2026.', info.feedback[0].byLine);
        Assert.areEqual('Great seller, fast shipping.', info.feedback[1].text);
    }

    @IsTest
    static void acceptsSellerIdAndStorefrontUrls() {
        AmazonSellerController.SellerInfo byId = AmazonSellerController.parseRef(' a009584315lpzvwg8zcm5 ');
        Assert.isTrue(byId.isValid);
        Assert.areEqual('https://www.amazon.com/sp?seller=A009584315LPZVWG8ZCM5', byId.sellerUrl);

        AmazonSellerController.SellerInfo sParam =
            AmazonSellerController.parseRef('https://www.amazon.com/sp?_encoding=UTF8&s=A24UXSYSGKROUQ');
        Assert.isTrue(sParam.isValid);
        Assert.areEqual('A24UXSYSGKROUQ', sParam.sellerId);
        Assert.areEqual('https://www.amazon.com/sp?seller=A24UXSYSGKROUQ', sParam.sellerUrl);

        AmazonSellerController.SellerInfo storefront =
            AmazonSellerController.parseRef('amazon.co.uk/s?ie=UTF8&marketplaceID=A1F83G8C2ARO7P&me=A1B2C3D4E5F6G7');
        Assert.isTrue(storefront.isValid);
        Assert.areEqual('www.amazon.co.uk', storefront.marketplaceHost);
        Assert.areEqual('A1B2C3D4E5F6G7', storefront.sellerId);
    }

    @IsTest
    static void rejectsOtherValues() {
        Assert.isFalse(AmazonSellerController.getSellerInfo(null).isValid);
        Assert.isFalse(AmazonSellerController.getSellerInfo('https://www.amazon.com/dp/B000123').isValid);
        Assert.isFalse(AmazonSellerController.getSellerInfo('McDonald Paper').isValid);
    }

    @IsTest
    static void reportsRobotCheck() {
        Test.setMock(HttpCalloutMock.class,
            new AmazonMock(200, '<html><form action="/errors/validateCaptcha"></form></html>'));

        AmazonSellerController.SellerInfo info = AmazonSellerController.getSellerInfo('A009584315LPZVWG8ZCM5');

        Assert.isTrue(info.isValid);
        Assert.isFalse(info.fetched);
        Assert.isTrue(info.errorMessage.contains('robot check'));
    }

    @IsTest
    static void reportsUnknownSeller() {
        Test.setMock(HttpCalloutMock.class, new AmazonMock(404, 'not found'));

        AmazonSellerController.SellerInfo info = AmazonSellerController.getSellerInfo('A009584315LPZVWG8ZCM5');

        Assert.isFalse(info.fetched);
        Assert.isTrue(info.errorMessage.contains('no seller profile'));
    }

    @IsTest
    static void picklistDefaultsToSellerPageField() {
        VisualEditor.DesignTimePageContext ctx = new VisualEditor.DesignTimePageContext();
        ctx.entityName = 'Lead';
        AmazonSellerFieldPicklist picklist = new AmazonSellerFieldPicklist(ctx);

        Assert.isTrue(picklist.getValues().size() > 0);
        Assert.areEqual('Amazon_Seller_Page__c', picklist.getDefaultValue().getValue());

        ctx.entityName = 'Store__c';
        Assert.areEqual('Seller_ID__c', new AmazonSellerFieldPicklist(ctx).getDefaultValue().getValue());
    }
}