@IsTest
private class LinkedInProfileControllerTest {

    private class LinkedInMock implements HttpCalloutMock {
        private Integer status;
        private String body;
        private String location;

        LinkedInMock(Integer status, String body, String location) {
            this.status = status;
            this.body = body;
            this.location = location;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            if (body != null) {
                res.setBody(body);
            }
            if (location != null) {
                res.setHeader('Location', location);
            }
            return res;
        }
    }

    private static final String COMPANY_HTML =
        '<html><head>' +
        '<meta property="og:title" content="EWC Group Inc. | LinkedIn">' +
        '<meta content="https://media.licdn.com/og.png" property="og:image">' +
        '<meta property="og:description" content="EWC Group Inc. | 1,234 followers on LinkedIn. We build things &amp; more.">' +
        '</head><body>' +
        '<script type="application/ld+json">{"@context":"http://schema.org","@graph":[' +
        '{"@type":"Organization","name":"EWC Group Inc.","description":"Full description","slogan":"Building better",' +
        '"logo":{"@type":"ImageObject","contentUrl":"https://media.licdn.com/logo.png"},' +
        '"numberOfEmployees":{"value":42},"sameAs":"https://ewcgroup.com",' +
        '"address":{"addressLocality":"Miami","addressRegion":"FL","addressCountry":"US"}}]}</script>' +
        '</body></html>';

    @IsTest
    static void parsesCompanyPage() {
        Test.setMock(HttpCalloutMock.class, new LinkedInMock(200, COMPANY_HTML, null));

        Test.startTest();
        LinkedInProfileController.ProfileInfo info =
            LinkedInProfileController.getProfileInfo('linkedin.com/company/ewc-group-inc?trk=abc');
        Test.stopTest();

        Assert.isTrue(info.isValid);
        Assert.isTrue(info.fetched);
        Assert.areEqual('company', info.profileType);
        Assert.areEqual('https://www.linkedin.com/company/ewc-group-inc/', info.url);
        Assert.areEqual('EWC Group Inc.', info.name);
        Assert.areEqual('Building better', info.headline);
        Assert.areEqual('Full description', info.description);
        Assert.areEqual('https://media.licdn.com/logo.png', info.imageUrl);
        Assert.areEqual('1,234', info.followers);
        Assert.areEqual('42', info.employees);
        Assert.areEqual('Miami, FL, US', info.location);
        Assert.areEqual('https://ewcgroup.com', info.website);
    }

    private static final String PERSON_HTML =
        '<html><head>' +
        '<meta property="og:title" content="Marshall Lane - Acme Corp | LinkedIn">' +
        '<meta property="og:image" content="https://media.licdn.com/og-person.png">' +
        '<meta property="og:description" content="Builder of things. · Experience: Acme Corp · Education: State University · Location: Denver · 500+ connections on LinkedIn. View Marshall Lane&#39;s profile on LinkedIn, a professional community of 1 billion members.">' +
        '</head><body>' +
        '<script type="application/ld+json">{"@context":"http://schema.org","@graph":[' +
        '{"@type":"Organization","name":"Acme Corp"},' +
        '{"@type":"Person","name":"Marshall Lane","jobTitle":["VP Sales"],' +
        '"description":"Twenty years in sales.","image":{"contentUrl":"https://media.licdn.com/person.png"},' +
        '"address":{"addressLocality":"Denver, Colorado","addressCountry":"US"},' +
        '"worksFor":[{"@type":"Organization","name":"Old Co","member":{"startDate":2010,"endDate":2015}},' +
        '{"@type":"Organization","name":"Acme Corp","url":"https://www.linkedin.com/company/acme","member":{"startDate":"2015","description":"Leads sales"}}],' +
        '"alumniOf":[{"@type":"EducationalOrganization","name":"State University","member":{"startDate":2000,"endDate":2004}}],' +
        '"knowsLanguage":[{"@type":"Language","name":"English"},{"@type":"Language","name":"Spanish"}],' +
        '"awards":["Top Seller 2020"],' +
        '"interactionStatistic":{"@type":"InteractionCounter","name":"Follows","userInteractionCount":812}}]}</script>' +
        '</body></html>';

    @IsTest
    static void parsesPersonPage() {
        Test.setMock(HttpCalloutMock.class, new LinkedInMock(200, PERSON_HTML, null));

        LinkedInProfileController.ProfileInfo info =
            LinkedInProfileController.getProfileInfo('https://www.linkedin.com/in/marshall-lane-1332287');

        Assert.isTrue(info.fetched);
        Assert.areEqual('person', info.profileType);
        Assert.areEqual('Marshall Lane', info.name);
        Assert.areEqual('VP Sales', info.headline);
        Assert.areEqual('Twenty years in sales.', info.description);
        Assert.areEqual('https://media.licdn.com/person.png', info.imageUrl);
        Assert.areEqual('Denver, Colorado, US', info.location);
        Assert.areEqual('500+', info.connections);
        Assert.areEqual('812', info.followers);
        Assert.areEqual('Acme Corp', info.currentCompany);
        Assert.areEqual(2, info.experience.size());
        Assert.areEqual('2015 – Present', info.experience[1].dateRange);
        Assert.areEqual('Leads sales', info.experience[1].description);
        Assert.areEqual('2010 – 2015', info.experience[0].dateRange);
        Assert.areEqual(1, info.education.size());
        Assert.areEqual('State University', info.education[0].organization);
        Assert.areEqual(new List<String>{ 'English', 'Spanish' }, info.languages);
        Assert.areEqual(new List<String>{ 'Top Seller 2020' }, info.awards);
    }

    @IsTest
    static void parsesPersonMetaOnly() {
        String html = '<html><head>' +
            '<meta property="og:title" content="Marshall Lane | LinkedIn">' +
            '<meta property="og:description" content="Builder of things. · Experience: Acme Corp · Location: Denver · 500+ connections on LinkedIn. View Marshall Lane&#39;s profile on LinkedIn.">' +
            '</head></html>';
        Test.setMock(HttpCalloutMock.class, new LinkedInMock(200, html, null));

        LinkedInProfileController.ProfileInfo info =
            LinkedInProfileController.getProfileInfo('https://www.linkedin.com/in/marshall-lane-1332287');

        Assert.isTrue(info.fetched);
        Assert.areEqual('Acme Corp', info.currentCompany);
        Assert.areEqual('Denver', info.location);
        Assert.areEqual('500+', info.connections);
        Assert.areEqual('Builder of things.', info.description);
    }

    @IsTest
    static void personBlockedFallsBackToSlugName() {
        Test.setMock(HttpCalloutMock.class, new LinkedInMock(999, '', null));

        LinkedInProfileController.ProfileInfo info =
            LinkedInProfileController.getProfileInfo('https://www.linkedin.com/in/marshall-lane-1332287');

        Assert.isFalse(info.fetched);
        Assert.areEqual('Marshall Lane', info.name);
        Assert.isTrue(info.errorMessage.contains('signed-in members'));
    }

    @IsTest
    static void ignoresSignUpPage() {
        String html = '<html><head><meta property="og:title" content="Sign Up | LinkedIn"></head></html>';
        Test.setMock(HttpCalloutMock.class, new LinkedInMock(200, html, null));

        LinkedInProfileController.ProfileInfo info =
            LinkedInProfileController.getProfileInfo('https://www.linkedin.com/in/marshall-lane-1332287');

        Assert.isFalse(info.fetched);
        Assert.areEqual('Marshall Lane', info.name);
    }

    @IsTest
    static void usesMetaTagsWhenNoJsonLd() {
        String html = '<html><head><meta property="og:title" content="Jane Doe - LinkedIn">' +
            '<meta name="description" content="Jane&#39;s profile"></head></html>';
        Test.setMock(HttpCalloutMock.class, new LinkedInMock(200, html, null));

        LinkedInProfileController.ProfileInfo info =
            LinkedInProfileController.getProfileInfo('https://uk.linkedin.com/in/jane-doe-1a2b3c4d/');

        Assert.areEqual('person', info.profileType);
        Assert.isTrue(info.fetched);
        Assert.areEqual('Jane Doe', info.name);
        Assert.areEqual('Jane\'s profile', info.description);
    }

    @IsTest
    static void fallsBackWhenLinkedInBlocks() {
        Test.setMock(HttpCalloutMock.class, new LinkedInMock(999, '', null));

        LinkedInProfileController.ProfileInfo info =
            LinkedInProfileController.getProfileInfo('https://www.linkedin.com/company/ewc-group-inc/');

        Assert.isTrue(info.isValid);
        Assert.isFalse(info.fetched);
        Assert.areEqual('Ewc Group Inc', info.name);
        Assert.isTrue(info.errorMessage.contains('999'));
    }

    @IsTest
    static void stopsAtAuthWallRedirect() {
        Test.setMock(HttpCalloutMock.class,
            new LinkedInMock(302, null, 'https://www.linkedin.com/authwall?trk=x'));

        LinkedInProfileController.ProfileInfo info =
            LinkedInProfileController.getProfileInfo('https://www.linkedin.com/school/some-university/');

        Assert.areEqual('school', info.profileType);
        Assert.isFalse(info.fetched);
        Assert.areEqual('Some University', info.name);
    }

    @IsTest
    static void rejectsNonLinkedInUrls() {
        Assert.isFalse(LinkedInProfileController.getProfileInfo(null).isValid);
        Assert.isFalse(LinkedInProfileController.getProfileInfo('https://example.com/company/x').isValid);
        Assert.isFalse(LinkedInProfileController.getProfileInfo('https://www.linkedin.com/feed/').isValid);
    }

    @IsTest
    static void picklistListsFieldsAndDefaultsToLinkedIn() {
        VisualEditor.DesignTimePageContext ctx = new VisualEditor.DesignTimePageContext();
        ctx.entityName = 'Lead';
        LinkedInUrlFieldPicklist picklist = new LinkedInUrlFieldPicklist(ctx);

        VisualEditor.DynamicPickListRows rows = picklist.getValues();
        Assert.isTrue(rows.size() > 0);
        Assert.areEqual('LinkedIn_URL__c', picklist.getDefaultValue().getValue());

        Assert.areEqual(0, new LinkedInUrlFieldPicklist(new VisualEditor.DesignTimePageContext()).getValues().size());
    }
}