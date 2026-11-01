/**
 * Backs the linkedInProfileCard LWC. Given a LinkedIn URL (company, person,
 * school or showcase page), fetches the PUBLIC page server-side and extracts
 * what LinkedIn exposes to anonymous visitors: OpenGraph meta tags and the
 * schema.org JSON-LD block (name, logo, description, employees, address, ...).
 *
 * Notes:
 *  - LinkedIn has no open API for this data (the official API needs Marketing
 *    Developer Platform partner approval). Anonymous fetches are best-effort:
 *    LinkedIn sometimes answers with HTTP 999 / an auth wall, in which case
 *    the result has fetched = false and the component falls back to a link card
 *    built from the URL itself.
 *  - Requires the "LinkedIn" Remote Site Setting (https://www.linkedin.com).
 */
public with sharing class LinkedInProfileController {

    private static final String BASE_URL = 'https://www.linkedin.com';
    private static final Pattern URL_PATTERN = Pattern.compile(
        '(?i)^(?:https?://)?(?:[a-z]{2,3}\\.)?(?:www\\.)?linkedin\\.com/(company|in|school|showcase)/([^/?#\\s]+).*$'
    );
    private static final Pattern FOLLOWERS_PATTERN = Pattern.compile('(?i)([\\d][\\d,\\.]*\\s?[KM]?)\\s+followers');
    private static final Pattern CONNECTIONS_PATTERN = Pattern.compile('(?i)([\\d][\\d,]*\\+?)\\s+connections');
    // Person og:description looks like "Experience: Acme · Education: MIT · Location: Boston · 500+ connections ..."
    private static final Pattern PERSON_SUMMARY_PATTERN = Pattern.compile('(?i)(Experience|Education|Location):\\s*([^\\u00B7|]+)');
    private static final Pattern PROFILE_BOILERPLATE_PATTERN = Pattern.compile('(?i)\\s*View [^.]*profile on LinkedIn[^.]*\\.?.*$');
    private static final Set<String> NON_PROFILE_TITLES = new Set<String>{ 'linkedin', 'sign up', 'log in', 'sign in', 'join linkedin' };
    private static final Integer MAX_REDIRECTS = 2;

    public class ProfileInfo {
        @AuraEnabled public String url;
        @AuraEnabled public String profileType;   // company | person | school | showcase
        @AuraEnabled public String slug;
        @AuraEnabled public Boolean isValid = false;
        @AuraEnabled public Boolean fetched = false;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String name;
        @AuraEnabled public String headline;      // company slogan or person job title
        @AuraEnabled public String description;   // company description or person "About"
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String followers;
        @AuraEnabled public String employees;
        @AuraEnabled public String location;
        @AuraEnabled public String website;
        // Person-only
        @AuraEnabled public String currentCompany;
        @AuraEnabled public String connections;
        @AuraEnabled public List<Position> experience = new List<Position>();
        @AuraEnabled public List<Position> education = new List<Position>();
        @AuraEnabled public List<String> languages = new List<String>();
        @AuraEnabled public List<String> awards = new List<String>();
    }

    /** One job (worksFor) or school (alumniOf) entry from a person profile. */
    public class Position {
        @AuraEnabled public String key;
        @AuraEnabled public String organization;
        @AuraEnabled public String url;
        @AuraEnabled public String title;
        @AuraEnabled public String dateRange;
        @AuraEnabled public String description;
    }

    @AuraEnabled(cacheable=true)
    public static ProfileInfo getProfileInfo(String linkedInUrl) {
        ProfileInfo info = parseUrl(linkedInUrl);
        if (!info.isValid) {
            return info;
        }
        try {
            HttpResponse res = fetch(info.url);
            if (res.getStatusCode() == 200) {
                applyHtml(info, res.getBody());
                if (String.isNotBlank(info.name) && NON_PROFILE_TITLES.contains(info.name.toLowerCase())) {
                    info.name = null; // served a sign-up / login page instead of the profile
                }
                info.fetched = String.isNotBlank(info.name);
                if (!info.fetched) {
                    info.errorMessage = 'LinkedIn did not return public details for this page.';
                }
            } else if (info.profileType == 'person') {
                info.errorMessage = 'LinkedIn only shows personal profiles to signed-in members (HTTP '
                    + res.getStatusCode() + ').';
            } else {
                info.errorMessage = 'LinkedIn returned HTTP ' + res.getStatusCode() + '.';
            }
        } catch (Exception e) {
            info.errorMessage = 'Could not reach LinkedIn: ' + e.getMessage();
        }
        if (String.isBlank(info.name)) {
            info.name = nameFromSlug(info.slug);
        }
        return info;
    }

    @TestVisible
    private static ProfileInfo parseUrl(String rawUrl) {
        ProfileInfo info = new ProfileInfo();
        if (String.isBlank(rawUrl)) {
            info.errorMessage = 'No LinkedIn URL on this record.';
            return info;
        }
        Matcher m = URL_PATTERN.matcher(rawUrl.trim());
        if (!m.matches()) {
            info.errorMessage = 'Not a LinkedIn company or profile URL: ' + rawUrl;
            return info;
        }
        String section = m.group(1).toLowerCase();
        info.slug = EncodingUtil.urlDecode(m.group(2), 'UTF-8');
        info.profileType = section == 'in' ? 'person' : section;
        info.url = BASE_URL + '/' + section + '/' + EncodingUtil.urlEncode(info.slug, 'UTF-8') + '/';
        info.isValid = true;
        return info;
    }

    private static HttpResponse fetch(String url) {
        HttpResponse res;
        String target = url;
        for (Integer i = 0; i <= MAX_REDIRECTS; i++) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(target);
            req.setMethod('GET');
            req.setTimeout(10000);
            req.setHeader('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36');
            req.setHeader('Accept', 'text/html,application/xhtml+xml');
            req.setHeader('Accept-Language', 'en-US,en;q=0.9');
            res = new Http().send(req);

            Integer status = res.getStatusCode();
            String location = res.getHeader('Location');
            if ((status == 301 || status == 302 || status == 303 || status == 307 || status == 308)
                    && String.isNotBlank(location)) {
                if (location.startsWith('/')) {
                    location = BASE_URL + location;
                }
                // Anything that isn't the public page itself (auth wall, login) is a dead end.
                if (!location.startsWith(BASE_URL) || location.containsIgnoreCase('authwall')
                        || location.containsIgnoreCase('/login')) {
                    return res;
                }
                target = location;
                continue;
            }
            return res;
        }
        return res;
    }

    @TestVisible
    private static void applyHtml(ProfileInfo info, String html) {
        if (String.isBlank(html)) {
            return;
        }
        Map<String, String> meta = readMetaTags(html);
        info.name = stripLinkedInSuffix(meta.get('og:title'));
        info.imageUrl = meta.get('og:image');
        String ogDescription = meta.get('og:description');
        if (String.isBlank(ogDescription)) {
            ogDescription = meta.get('description');
        }
        info.description = ogDescription;
        if (String.isNotBlank(ogDescription)) {
            Matcher fm = FOLLOWERS_PATTERN.matcher(ogDescription);
            if (fm.find()) {
                info.followers = fm.group(1).trim();
            }
            if (info.profileType == 'person') {
                applyPersonSummary(info, ogDescription);
            }
        }
        // Person og:title is "Name - Current Company"; keep just the name.
        if (info.profileType == 'person' && info.name != null && info.name.contains(' - ')) {
            if (String.isBlank(info.currentCompany)) {
                info.currentCompany = info.name.substringAfter(' - ').trim();
            }
            info.name = info.name.substringBefore(' - ').trim();
        }
        applyJsonLd(info, html);
    }

    /** Pulls headline facts out of a person page's meta description and strips LinkedIn's boilerplate. */
    private static void applyPersonSummary(ProfileInfo info, String summary) {
        Matcher cm = CONNECTIONS_PATTERN.matcher(summary);
        if (cm.find()) {
            info.connections = cm.group(1);
        }
        Matcher sm = PERSON_SUMMARY_PATTERN.matcher(summary);
        Integer firstFactAt = -1;
        while (sm.find()) {
            if (firstFactAt < 0) {
                firstFactAt = sm.start();
            }
            String label = sm.group(1).toLowerCase();
            String value = sm.group(2).trim();
            if (label == 'experience') {
                info.currentCompany = value;
            } else if (label == 'location') {
                info.location = value;
            }
        }
        // Whatever comes before the "Experience: ..." facts is the member's own About text.
        String about = firstFactAt >= 0 ? summary.left(firstFactAt) : summary;
        about = PROFILE_BOILERPLATE_PATTERN.matcher(about).replaceAll('');
        about = CONNECTIONS_PATTERN.matcher(about).find() ? null : about.trim().removeEnd('·').trim();
        info.description = String.isBlank(about) ? null : about;
    }

    /** Reads <meta property|name="..." content="..."> from the document head only (keeps regex work small). */
    private static Map<String, String> readMetaTags(String html) {
        Map<String, String> meta = new Map<String, String>();
        Integer headEnd = html.indexOfIgnoreCase('</head>');
        String head = headEnd > 0 ? html.substring(0, headEnd) : html.left(200000);

        Integer pos = 0;
        while (true) {
            Integer start = head.indexOfIgnoreCase('<meta', pos);
            if (start < 0) {
                break;
            }
            Integer finish = head.indexOf('>', start);
            if (finish < 0) {
                break;
            }
            String tag = head.substring(start, finish + 1);
            pos = finish + 1;

            String key = attr(tag, 'property');
            if (key == null) {
                key = attr(tag, 'name');
            }
            String content = attr(tag, 'content');
            if (key != null && content != null && !meta.containsKey(key.toLowerCase())) {
                // LinkedIn double-escapes entities in meta content (&amp;amp;).
                meta.put(key.toLowerCase(), content.unescapeHtml4().unescapeHtml4().trim());
            }
        }
        return meta;
    }

    private static String attr(String tag, String name) {
        Matcher m = Pattern.compile('(?i)\\s' + name + '\\s*=\\s*"([^"]*)"').matcher(tag);
        return m.find() ? m.group(1) : null;
    }

    /** LinkedIn embeds schema.org Organization / Person JSON-LD on public pages. */
    private static void applyJsonLd(ProfileInfo info, String html) {
        Integer pos = 0;
        while (true) {
            Integer marker = html.indexOfIgnoreCase('application/ld+json', pos);
            if (marker < 0) {
                return;
            }
            Integer start = html.indexOf('>', marker);
            Integer finish = start < 0 ? -1 : html.indexOfIgnoreCase('</script>', start);
            if (finish < 0) {
                return;
            }
            pos = finish;
            Object parsed;
            try {
                parsed = JSON.deserializeUntyped(html.substring(start + 1, finish).trim());
            } catch (Exception e) {
                continue;
            }
            Map<String, Object> node = findEntity(parsed, info.profileType == 'person');
            if (node != null) {
                applyEntity(info, node);
                return;
            }
        }
    }

    private static Map<String, Object> findEntity(Object parsed, Boolean wantPerson) {
        List<Object> candidates = new List<Object>();
        if (parsed instanceof List<Object>) {
            candidates.addAll((List<Object>) parsed);
        } else if (parsed instanceof Map<String, Object>) {
            Map<String, Object> root = (Map<String, Object>) parsed;
            if (root.get('@graph') instanceof List<Object>) {
                candidates.addAll((List<Object>) root.get('@graph'));
            } else {
                candidates.add(root);
            }
        }
        for (Object c : candidates) {
            if (c instanceof Map<String, Object>) {
                Map<String, Object> node = (Map<String, Object>) c;
                String type = String.valueOf(node.get('@type'));
                Boolean isPerson = type == 'Person';
                Boolean isOrg = type == 'Organization' || type == 'Corporation'
                    || type == 'EducationalOrganization' || type == 'CollegeOrUniversity';
                // Person pages also carry Organization nodes (employers, posts), so match the page type.
                if (wantPerson ? isPerson : isOrg) {
                    return node;
                }
            }
        }
        return null;
    }

    private static void applyEntity(ProfileInfo info, Map<String, Object> node) {
        applyOrganizationOrPersonBasics(info, node);
        if (info.profileType == 'person') {
            applyPersonDetails(info, node);
        }
    }

    private static void applyPersonDetails(ProfileInfo info, Map<String, Object> node) {
        info.experience = positions(node.get('worksFor'), 'exp');
        info.education = positions(node.get('alumniOf'), 'edu');
        if (!info.experience.isEmpty()) {
            for (Position p : info.experience) {
                if (p.dateRange != null && p.dateRange.endsWith('Present')) {
                    info.currentCompany = p.organization;
                    break;
                }
            }
            if (String.isBlank(info.currentCompany)) {
                info.currentCompany = info.experience[0].organization;
            }
        }
        info.languages = names(node.get('knowsLanguage'));
        info.awards = names(node.get('awards'));

        // Followers: interactionStatistic { name: "Follows", userInteractionCount: n }
        Object stats = node.get('interactionStatistic');
        List<Object> statList = stats instanceof List<Object> ? (List<Object>) stats : new List<Object>{ stats };
        for (Object s : statList) {
            if (s instanceof Map<String, Object>) {
                Map<String, Object> stat = (Map<String, Object>) s;
                if (String.valueOf(stat.get('name')).containsIgnoreCase('follow') && stat.get('userInteractionCount') != null) {
                    info.followers = String.valueOf(stat.get('userInteractionCount'));
                }
            }
        }
        String disambiguating = str(node.get('disambiguatingDescription'));
        if (String.isBlank(info.headline) && String.isNotBlank(disambiguating)) {
            info.headline = disambiguating;
        }
    }

    /** worksFor / alumniOf -> positions; each item may carry member: { OrganizationRole startDate/endDate/description/roleName }. */
    private static List<Position> positions(Object value, String keyPrefix) {
        List<Position> result = new List<Position>();
        if (value == null) {
            return result;
        }
        List<Object> items = value instanceof List<Object> ? (List<Object>) value : new List<Object>{ value };
        for (Object item : items) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> org = (Map<String, Object>) item;
            Position p = new Position();
            p.key = keyPrefix + result.size();
            p.organization = str(org.get('name'));
            p.url = str(org.get('url'));
            if (org.get('member') instanceof Map<String, Object>) {
                Map<String, Object> role = (Map<String, Object>) org.get('member');
                p.title = str(role.get('roleName'));
                p.description = str(role.get('description'));
                String startDate = str(role.get('startDate'));
                String endDate = str(role.get('endDate'));
                if (String.isNotBlank(startDate) || String.isNotBlank(endDate)) {
                    p.dateRange = (String.isNotBlank(startDate) ? startDate : '?') + ' – '
                        + (String.isNotBlank(endDate) ? endDate : 'Present');
                }
            }
            if (String.isNotBlank(p.organization)) {
                result.add(p);
            }
        }
        return result;
    }

    private static List<String> names(Object value) {
        List<String> result = new List<String>();
        if (value == null) {
            return result;
        }
        List<Object> items = value instanceof List<Object> ? (List<Object>) value : new List<Object>{ value };
        for (Object item : items) {
            String name = item instanceof Map<String, Object>
                ? str(((Map<String, Object>) item).get('name'))
                : str(item);
            if (String.isNotBlank(name)) {
                result.add(name);
            }
        }
        return result;
    }

    private static void applyOrganizationOrPersonBasics(ProfileInfo info, Map<String, Object> node) {
        String name = str(node.get('name'));
        if (String.isNotBlank(name)) {
            info.name = name;
        }
        String description = str(node.get('description'));
        if (String.isNotBlank(description)) {
            info.description = description;
        }
        String slogan = str(node.get('slogan'));
        String jobTitle = firstString(node.get('jobTitle'));
        info.headline = String.isNotBlank(slogan) ? slogan : jobTitle;

        String logo = imageUrl(node.get('logo'));
        if (String.isBlank(logo)) {
            logo = imageUrl(node.get('image'));
        }
        if (String.isNotBlank(logo)) {
            info.imageUrl = logo;
        }

        Object employees = node.get('numberOfEmployees');
        if (employees instanceof Map<String, Object>) {
            info.employees = str(((Map<String, Object>) employees).get('value'));
        } else if (employees != null) {
            info.employees = String.valueOf(employees);
        }

        String address = formatAddress(node.get('address'));
        if (String.isNotBlank(address)) {
            info.location = address;
        }
        String sameAs = firstString(node.get('sameAs'));
        if (String.isNotBlank(sameAs) && !sameAs.containsIgnoreCase('linkedin.com')) {
            info.website = sameAs;
        }
    }

    private static String formatAddress(Object address) {
        if (address instanceof List<Object> && !((List<Object>) address).isEmpty()) {
            address = ((List<Object>) address)[0];
        }
        if (!(address instanceof Map<String, Object>)) {
            return str(address);
        }
        Map<String, Object> a = (Map<String, Object>) address;
        List<String> parts = new List<String>();
        for (String key : new List<String>{ 'addressLocality', 'addressRegion', 'addressCountry' }) {
            String part = str(a.get(key));
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static String imageUrl(Object image) {
        if (image instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) image;
            String url = str(m.get('contentUrl'));
            return String.isNotBlank(url) ? url : str(m.get('url'));
        }
        return str(image);
    }

    private static String firstString(Object value) {
        if (value instanceof List<Object>) {
            List<Object> values = (List<Object>) value;
            return values.isEmpty() ? null : str(values[0]);
        }
        return str(value);
    }

    private static String str(Object value) {
        if (value == null || value instanceof Map<String, Object> || value instanceof List<Object>) {
            return null;
        }
        return String.valueOf(value).unescapeHtml4().trim();
    }

    private static String stripLinkedInSuffix(String title) {
        if (String.isBlank(title)) {
            return null;
        }
        return title.replaceAll('(?i)\\s*[|\\-]\\s*LinkedIn\\s*$', '').trim();
    }

    @TestVisible
    private static String nameFromSlug(String slug) {
        if (String.isBlank(slug)) {
            return null;
        }
        List<String> words = new List<String>();
        for (String w : slug.replaceAll('-[0-9a-f]{6,}$', '').split('[-_]')) {
            if (String.isNotBlank(w)) {
                words.add(w.capitalize());
            }
        }
        return String.join(words, ' ');
    }
}