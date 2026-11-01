public with sharing class S3AwsPresignService {

    private static final Integer DEFAULT_EXPIRY_SECONDS = 3600;

    public static S3DocumentUrlService.PresignResponse createPutObjectPresignedUrl(
        String bucket,
        String key,
        String region,
        String contentType,
        String accessKeyId,
        String secretAccessKey
    ) {
        String normalizedContentType = String.isNotBlank(contentType)
            ? contentType
            : 'application/octet-stream';

        Map<String, String> signedHeaders = new Map<String, String>{
            'content-type' => normalizedContentType,
            'host' => buildHost(bucket, region)
        };

        return signRequest('PUT', bucket, key, region, accessKeyId, secretAccessKey, signedHeaders, null);
    }

    public static S3DocumentUrlService.PresignResponse createGetObjectPresignedUrl(
        String bucket,
        String key,
        String region,
        String accessKeyId,
        String secretAccessKey,
        String fileName,
        Boolean asDownload
    ) {
        Map<String, String> signedHeaders = new Map<String, String>{
            'host' => buildHost(bucket, region)
        };
        Map<String, String> extraQueryParams = new Map<String, String>();

        if (asDownload == true && String.isNotBlank(fileName)) {
            extraQueryParams.put(
                'response-content-disposition',
                'attachment; filename="' + sanitizeDispositionFileName(fileName) + '"'
            );
        }

        return signRequest('GET', bucket, key, region, accessKeyId, secretAccessKey, signedHeaders, extraQueryParams);
    }

    public static Boolean hasAwsCredentials(Appeals_Dr_Setting__c settings) {
        return settings != null
            && String.isNotBlank(settings.AWS_Access_Key_Id__c)
            && String.isNotBlank(settings.AWS_Secret_Access_Key__c);
    }

    public static String resolveRegion(Appeals_Dr_Setting__c settings, String documentRegion) {
        if (String.isNotBlank(documentRegion)) {
            return documentRegion;
        }
        if (settings != null && String.isNotBlank(settings.AWS_Region__c)) {
            return settings.AWS_Region__c;
        }
        return 'us-east-2';
    }

    public static Appeals_Dr_Setting__c resolveSettings() {
        Appeals_Dr_Setting__c settings = Appeals_Dr_Setting__c.getInstance();
        if (hasAwsCredentials(settings)) {
            return settings;
        }

        Appeals_Dr_Setting__c orgDefaults = Appeals_Dr_Setting__c.getOrgDefaults();
        if (orgDefaults != null && orgDefaults.Id != null) {
            return orgDefaults;
        }

        return settings;
    }

    @TestVisible
    private static S3DocumentUrlService.PresignResponse signRequest(
        String httpMethod,
        String bucket,
        String key,
        String region,
        String accessKeyId,
        String secretAccessKey,
        Map<String, String> signedHeaders,
        Map<String, String> extraQueryParams
    ) {
        if (String.isBlank(bucket) || String.isBlank(key) || String.isBlank(region)) {
            return null;
        }
        if (String.isBlank(accessKeyId) || String.isBlank(secretAccessKey)) {
            return null;
        }

        Datetime now = Datetime.now();
        String amzDate = now.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
        String dateStamp = now.formatGmt('yyyyMMdd');
        String credentialScope = dateStamp + '/' + region + '/s3/aws4_request';
        String host = buildHost(bucket, region);
        String encodedKey = encodeS3Key(key);

        Map<String, String> queryParams = new Map<String, String>();
        if (extraQueryParams != null) {
            queryParams.putAll(extraQueryParams);
        }
        queryParams.put('X-Amz-Algorithm', 'AWS4-HMAC-SHA256');
        queryParams.put('X-Amz-Credential', accessKeyId + '/' + credentialScope);
        queryParams.put('X-Amz-Date', amzDate);
        queryParams.put('X-Amz-Expires', String.valueOf(DEFAULT_EXPIRY_SECONDS));
        queryParams.put('X-Amz-SignedHeaders', buildSignedHeaderNames(signedHeaders));

        String canonicalQueryString = buildCanonicalQueryString(queryParams);
        String canonicalHeaders = buildCanonicalHeaders(signedHeaders);
        String signedHeaderNames = buildSignedHeaderNames(signedHeaders);

        String canonicalRequest = httpMethod + '\n'
            + '/' + encodedKey + '\n'
            + canonicalQueryString + '\n'
            + canonicalHeaders + '\n'
            + signedHeaderNames + '\n'
            + 'UNSIGNED-PAYLOAD';

        String stringToSign = 'AWS4-HMAC-SHA256\n'
            + amzDate + '\n'
            + credentialScope + '\n'
            + hashHex(canonicalRequest);

        Blob signingKey = getSigningKey(secretAccessKey, dateStamp, region, 's3');
        String signature = EncodingUtil.convertToHex(
            Crypto.generateMac('HmacSHA256', Blob.valueOf(stringToSign), signingKey)
        ).toLowerCase();

        S3DocumentUrlService.PresignResponse response = new S3DocumentUrlService.PresignResponse();
        response.url = 'https://' + host + '/' + encodedKey + '?' + canonicalQueryString + '&X-Amz-Signature=' + signature;
        response.expiresAt = now.addSeconds(DEFAULT_EXPIRY_SECONDS)
            .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        return response;
    }

    private static String buildHost(String bucket, String region) {
        return bucket + '.s3.' + region + '.amazonaws.com';
    }

    private static String buildSignedHeaderNames(Map<String, String> signedHeaders) {
        List<String> headerNames = new List<String>(signedHeaders.keySet());
        headerNames.sort();
        return String.join(headerNames, ';');
    }

    private static String buildCanonicalHeaders(Map<String, String> signedHeaders) {
        List<String> headerNames = new List<String>(signedHeaders.keySet());
        headerNames.sort();

        List<String> lines = new List<String>();
        for (String headerName : headerNames) {
            lines.add(headerName + ':' + signedHeaders.get(headerName).trim());
        }
        return String.join(lines, '\n') + '\n';
    }

    private static String buildCanonicalQueryString(Map<String, String> queryParams) {
        List<String> paramNames = new List<String>(queryParams.keySet());
        paramNames.sort();

        List<String> encodedPairs = new List<String>();
        for (String paramName : paramNames) {
            encodedPairs.add(urlEncode(paramName) + '=' + urlEncode(queryParams.get(paramName)));
        }
        return String.join(encodedPairs, '&');
    }

    private static String sanitizeDispositionFileName(String fileName) {
        return fileName.replace('"', '').replace('\n', '').replace('\r', '');
    }

    private static Blob getSigningKey(String secretKey, String dateStamp, String region, String service) {
        Blob kDate = Crypto.generateMac('HmacSHA256', Blob.valueOf(dateStamp), Blob.valueOf('AWS4' + secretKey));
        Blob kRegion = Crypto.generateMac('HmacSHA256', Blob.valueOf(region), kDate);
        Blob kService = Crypto.generateMac('HmacSHA256', Blob.valueOf(service), kRegion);
        return Crypto.generateMac('HmacSHA256', Blob.valueOf('aws4_request'), kService);
    }

    private static String hashHex(String value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(value))).toLowerCase();
    }

    private static String encodeS3Key(String key) {
        List<String> encodedSegments = new List<String>();
        for (String segment : key.split('/')) {
            encodedSegments.add(urlEncode(segment));
        }
        return String.join(encodedSegments, '/');
    }

    private static String urlEncode(String value) {
        return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
    }
}