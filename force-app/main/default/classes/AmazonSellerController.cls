/**
 * Backs the amazonSellerCard LWC. Accepts an Amazon seller profile URL
 * (https://www.amazon.com/sp?seller=A0... or /sp?_encoding=UTF8&s=A0...), a storefront URL (/s?me=A0...)
 * or a bare Seller ID, fetches the public seller profile page and extracts
 * name, logo, ratings, star histogram, About text, business details, phone
 * and the most recent feedback.
 *
 * Notes:
 *  - Amazon has no public API for seller profiles; this parses the public page
 *    and may break if Amazon changes its markup. When Amazon answers with a
 *    robot check (captcha / 503) the result has fetched = false and the
 *    component falls back to links built from the Seller ID.
 *  - Requires the "AmazonCom" Remote Site Setting (https://www.amazon.com).
 *    Other marketplaces (amazon.ca, amazon.co.uk, ...) need their own.
 */
public with sharing class AmazonSellerController {

    private static final String DEFAULT_HOST = 'www.amazon.com';
    private static final Pattern URL_PATTERN = Pattern.compile(
        '(?i)^(?:https?://)?((?:www\\.|smile\\.)?amazon\\.[a-z.]{2,6})/.*?[?&](?:seller|me|s)=([A-Z0-9]{8,24})\\b.*$'
    );
    private static final Pattern SELLER_ID_PATTERN = Pattern.compile('^A[A-Z0-9]{7,23}$');
    private static final Pattern POSITIVE_PATTERN = Pattern.compile(
        '(?i)(\\d{1,3})%\\s*positive</b>\\s*([a-z0-9 ]*?)\\s*\\(([\\d,]+)\\s+total ratings\\)'
    );
    private static final Pattern DETAIL_ROW_PATTERN = Pattern.compile(
        '(?i)<span class="a-text-bold">([^<]+)</span>(?:\\s*<span>([^<]*)</span>)?|indent-left"><span>([^<]*)</span>'
    );
    private static final Pattern FEEDBACK_STARS_PATTERN = Pattern.compile('(?i)a-icon-alt">([\\d.]+) out of 5 stars');
    private static final Pattern TAG_PATTERN = Pattern.compile('<[^>]+>');
    private static final Integer MAX_FEEDBACK = 10;

    public class SellerInfo {
        @AuraEnabled public Boolean isValid = false;
        @AuraEnabled public Boolean fetched = false;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String sellerId;
        @AuraEnabled public String marketplaceHost;
        @AuraEnabled public String sellerUrl;
        @AuraEnabled public String storefrontUrl;
        @AuraEnabled public String name;
        @AuraEnabled public String logoUrl;
        @AuraEnabled public Decimal rating;          // lifetime average, e.g. 4.6
        @AuraEnabled public String ratingCount;      // lifetime, e.g. "6,047"
        @AuraEnabled public Integer positivePercent; // e.g. 91
        @AuraEnabled public String positivePeriod;   // e.g. "lifetime"
        @AuraEnabled public String about;
        @AuraEnabled public String phone;
        @AuraEnabled public List<RatingPeriod> ratingPeriods = new List<RatingPeriod>();
        @AuraEnabled public List<HistogramBar> histogram = new List<HistogramBar>();
        @AuraEnabled public List<Detail> details = new List<Detail>();
        @AuraEnabled public List<Feedback> feedback = new List<Feedback>();
    }

    public class RatingPeriod {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal rating;
        @AuraEnabled public String count;
    }

    public class HistogramBar {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Integer percent;
    }

    public class Detail {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class Feedback {
        @AuraEnabled public String key;
        @AuraEnabled public Decimal stars;
        @AuraEnabled public String text;
        @AuraEnabled public String byLine;
    }

    @AuraEnabled(cacheable=true)
    public static SellerInfo getSellerInfo(String sellerRef) {
        SellerInfo info = parseRef(sellerRef);
        if (!info.isValid) {
            return info;
        }
        try {
            HttpResponse res = fetch(info.sellerUrl);
            String body = res.getBody();
            if (res.getStatusCode() == 200 && !isRobotCheck(body)) {
                applyHtml(info, body);
                info.fetched = String.isNotBlank(info.name);
                if (!info.fetched) {
                    info.errorMessage = 'Amazon did not return a seller profile for ' + info.sellerId + '.';
                }
            } else if (res.getStatusCode() == 404) {
                info.errorMessage = 'Amazon has no seller profile for ' + info.sellerId + '.';
            } else {
                info.errorMessage = 'Amazon asked for a robot check (HTTP ' + res.getStatusCode()
                    + '). Try refreshing later.';
            }
        } catch (Exception e) {
            info.errorMessage = 'Could not reach Amazon: ' + e.getMessage();
        }
        return info;
    }

    @TestVisible
    private static SellerInfo parseRef(String rawRef) {
        SellerInfo info = new SellerInfo();
        if (String.isBlank(rawRef)) {
            info.errorMessage = 'No Amazon seller on this record.';
            return info;
        }
        String ref = rawRef.trim();
        String host = DEFAULT_HOST;
        String sellerId;

        Matcher m = URL_PATTERN.matcher(ref);
        if (m.matches()) {
            host = m.group(1).toLowerCase();
            if (!host.startsWith('www.')) {
                host = 'www.' + host.removeStart('smile.');
            }
            sellerId = m.group(2).toUpperCase();
        } else if (SELLER_ID_PATTERN.matcher(ref.toUpperCase()).matches()) {
            sellerId = ref.toUpperCase();
        } else {
            info.errorMessage = 'Not an Amazon seller URL or Seller ID: ' + rawRef;
            return info;
        }

        info.sellerId = sellerId;
        info.marketplaceHost = host;
        info.sellerUrl = 'https://' + host + '/sp?seller=' + sellerId;
        info.storefrontUrl = 'https://' + host + '/s?me=' + sellerId;
        info.isValid = true;
        return info;
    }

    private static HttpResponse fetch(String url) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(15000);
        req.setHeader('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36');
        req.setHeader('Accept', 'text/html,application/xhtml+xml');
        req.setHeader('Accept-Language', 'en-US,en;q=0.9');
        return new Http().send(req);
    }

    private static Boolean isRobotCheck(String body) {
        return String.isBlank(body)
            || body.containsIgnoreCase('validateCaptcha')
            || body.containsIgnoreCase('api-services-support@amazon.com');
    }

    @TestVisible
    private static void applyHtml(SellerInfo info, String html) {
        info.name = textById(html, 'seller-name');
        info.logoUrl = attrById(html, 'seller-logo-img', 'src');
        info.phone = textById(html, 'seller-contact-phone');

        String summary = section(html, 'id="seller-info-feedback-summary"', 1500);
        if (summary != null) {
            Matcher pm = POSITIVE_PATTERN.matcher(summary);
            if (pm.find()) {
                info.positivePercent = Integer.valueOf(pm.group(1));
                info.positivePeriod = String.isBlank(pm.group(2)) ? null : pm.group(2).trim();
            }
        }

        applyRatingPeriods(info, html);
        applyHistogram(info, html);
        info.about = readAbout(html);
        applyDetails(info, html);
        applyFeedback(info, html);
    }

    private static void applyRatingPeriods(SellerInfo info, String html) {
        // description id suffix, count id, label
        List<List<String>> periods = new List<List<String>>{
            new List<String>{ 'thirty', 'rating-thirty-num', '30 days' },
            new List<String>{ 'ninety', 'rating-90-num', '90 days' },
            new List<String>{ 'year', 'rating-365d-num', '12 months' },
            new List<String>{ 'lifetime', 'rating-lifetime-num', 'Lifetime' }
        };
        for (List<String> p : periods) {
            String ratingText = textById(html, 'effective-timeperiod-rating-' + p[0] + '-description');
            String countSection = section(html, 'id="' + p[1] + '"', 400);
            String count = countSection == null ? null : textAfter(countSection, 'ratings-reviews-count">');
            if (ratingText == null && count == null) {
                continue;
            }
            RatingPeriod rp = new RatingPeriod();
            rp.key = p[0];
            rp.label = p[2];
            rp.rating = toDecimal(ratingText);
            rp.count = count;
            info.ratingPeriods.add(rp);
            if (p[0] == 'lifetime') {
                info.rating = rp.rating;
                info.ratingCount = rp.count;
            }
        }
    }

    private static void applyHistogram(SellerInfo info, String html) {
        List<String> words = new List<String>{ 'Five', 'Four', 'Three', 'Two', 'One' };
        for (Integer i = 0; i < words.size(); i++) {
            String pct = textById(html, 'percent' + words[i] + 'Star');
            if (pct == null) {
                continue;
            }
            HistogramBar bar = new HistogramBar();
            bar.key = 'star' + (5 - i);
            bar.label = (5 - i) + ' star';
            bar.percent = Integer.valueOf(pct.replaceAll('[^0-9]', '').left(3).leftPad(1, '0'));
            info.histogram.add(bar);
        }
    }

    private static String readAbout(String html) {
        String about = section(html, 'id="page-section-about-seller"', 20000);
        if (about == null) {
            return null;
        }
        for (String marker : new List<String>{ 'spp-expander-more-content', 'spp-expander-less-content' }) {
            Integer at = about.indexOf(marker);
            if (at < 0) {
                continue;
            }
            Integer start = about.indexOf('>', at);
            Integer finish = about.indexOf('</div>', start);
            if (start > 0 && finish > start) {
                String text = cleanText(about.substring(start + 1, finish).replace('</p>', '\n'));
                if (String.isNotBlank(text)) {
                    return text;
                }
            }
        }
        return null;
    }

    /** "Detailed Seller Information": label rows plus indented continuation lines (address). */
    private static void applyDetails(SellerInfo info, String html) {
        String block = section(html, 'id="page-section-detail-seller-info"', 8000);
        if (block == null) {
            return;
        }
        // The section is wrapped in a pair of identical comments; cut at the closing one.
        String marker = '<!-- Detailed Seller Information -->';
        Integer opening = block.indexOf(marker);
        Integer blockEnd = opening < 0 ? -1 : block.indexOf(marker, opening + marker.length());
        if (blockEnd > 0) {
            block = block.left(blockEnd);
        }
        Matcher m = DETAIL_ROW_PATTERN.matcher(block);
        Detail current;
        while (m.find()) {
            if (m.group(1) != null) {
                current = new Detail();
                current.key = 'd' + info.details.size();
                current.label = cleanText(m.group(1)).removeEnd(':').trim();
                current.value = m.group(2) == null ? '' : cleanText(m.group(2));
                info.details.add(current);
            } else if (current != null && String.isNotBlank(m.group(3))) {
                String line = cleanText(m.group(3));
                current.value = String.isBlank(current.value) ? line : current.value + '\n' + line;
            }
        }
    }

    private static void applyFeedback(SellerInfo info, String html) {
        String table = section(html, 'id="feedback-table"', 60000);
        if (table == null) {
            return;
        }
        List<String> rows = table.split('<!-- Each Individual Feedback Record -->');
        for (Integer i = 1; i < rows.size() && info.feedback.size() < MAX_FEEDBACK; i++) {
            String row = rows[i];
            Feedback fb = new Feedback();
            fb.key = 'f' + info.feedback.size();
            Matcher sm = FEEDBACK_STARS_PATTERN.matcher(row);
            if (sm.find()) {
                fb.stars = toDecimal(sm.group(1));
            }
            String expanded = textAfter(row, 'expandable-expanded-text">');
            fb.text = expanded != null ? expanded : textAfter(row, 'a-text-quote">');
            fb.byLine = textAfter(row, 'feedback-rater">');
            if (fb.stars != null || String.isNotBlank(fb.text)) {
                info.feedback.add(fb);
            }
        }
    }

    // ----- small HTML helpers (indexOf-based to keep regex work off the 350 KB page) -----

    private static String section(String html, String marker, Integer length) {
        Integer at = html.indexOf(marker);
        return at < 0 ? null : html.substring(at, Math.min(html.length(), at + length));
    }

    /** Text content right after the opening tag carrying id="..." (up to the next tag). */
    private static String textById(String html, String id) {
        Integer at = html.indexOf('id="' + id + '"');
        if (at < 0) {
            return null;
        }
        Integer start = html.indexOf('>', at);
        Integer finish = start < 0 ? -1 : html.indexOf('<', start);
        if (finish < 0) {
            return null;
        }
        String text = cleanText(html.substring(start + 1, finish));
        return String.isBlank(text) ? null : text;
    }

    private static String textAfter(String html, String marker) {
        Integer at = html.indexOf(marker);
        if (at < 0) {
            return null;
        }
        Integer start = at + marker.length();
        Integer finish = html.indexOf('</span>', start);
        if (finish < 0) {
            return null;
        }
        String text = cleanText(html.substring(start, finish));
        return String.isBlank(text) ? null : text;
    }

    private static String attrById(String html, String id, String attrName) {
        Integer at = html.indexOf('id="' + id + '"');
        if (at < 0) {
            return null;
        }
        Integer tagStart = html.lastIndexOf('<', at);
        Integer tagEnd = html.indexOf('>', at);
        if (tagStart < 0 || tagEnd < 0) {
            return null;
        }
        String tag = html.substring(tagStart, tagEnd);
        Integer a = tag.indexOf(attrName + '="');
        if (a < 0) {
            return null;
        }
        Integer vStart = a + attrName.length() + 2;
        Integer vEnd = tag.indexOf('"', vStart);
        return vEnd < 0 ? null : tag.substring(vStart, vEnd).unescapeHtml4();
    }

    private static String cleanText(String fragment) {
        if (fragment == null) {
            return null;
        }
        String text = TAG_PATTERN.matcher(fragment).replaceAll('').unescapeHtml4();
        List<String> lines = new List<String>();
        for (String line : text.split('\n')) {
            String t = line.normalizeSpace();
            if (String.isNotBlank(t)) {
                lines.add(t);
            }
        }
        return String.join(lines, '\n');
    }

    private static Decimal toDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String cleaned = value.replaceAll('[^0-9.]', '');
        return String.isBlank(cleaned) ? null : Decimal.valueOf(cleaned);
    }
}