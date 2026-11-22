/**
 * Central, rollback-safe trigger error logging.
 * Catch blocks call capture(), which publishes a Publish-Immediately platform event.
 * ApplicationErrorEventTrigger persists Application_Log__c in a separate transaction.
 * Callers must rethrow the original exception after calling capture().
 */
public without sharing class ApplicationErrorLogger {
  private static final String LOG_OBJECT = 'Application_Log__c';
  private static final String REDACTED = '[REDACTED]';
  private static final Integer MAX_IDS = 200;
  private static final Pattern SECRET_PATTERN = Pattern.compile(
    '(?i)(bearer|authorization|access[_-]?token|refresh[_-]?token|api[_-]?key|secret|password|cookie|session[_-]?id)(["\']?\\s*[:=]\\s*["\']?)[^\\s,;"\'}]+'
  );
  private static final Pattern EMAIL_PATTERN = Pattern.compile(
    '[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}'
  );
  private static final Pattern CARD_PATTERN = Pattern.compile(
    '\\b(?:\\d[ -]?){13,19}\\b'
  );

  private static Boolean isLogging = false;
  private static Set<String> publishedIds = new Set<String>();

  @TestVisible
  private static Boolean forcePublishFailure = false;
  @TestVisible
  private static List<Application_Error_Event__e> publishedEvents = new List<Application_Error_Event__e>();

  /** Capture from inside a trigger (reads Trigger.* context). Returns the correlation id. */
  public static String capture(Exception ex, String component) {
    List<SObject> records = Trigger.isExecuting
      ? (Trigger.isDelete ? Trigger.old : Trigger.new)
      : null;
    String objectName = null;
    if (records != null && !records.isEmpty()) {
      objectName = String.valueOf(records[0].getSObjectType());
    }
    String operation = Trigger.isExecuting ? String.valueOf(Trigger.operationType) : null;
    return capture(ex, component, objectName, operation, records);
  }

  public static String capture(
    Exception ex,
    String component,
    String objectName,
    String operation,
    List<SObject> records
  ) {
    String correlationId = null;
    try {
      if (ex == null || isLogging || LOG_OBJECT.equalsIgnoreCase(objectName)) {
        return null;
      }
      String requestId = Request.getCurrent().getRequestId();
      correlationId = buildCorrelationId(requestId, component, operation, ex);
      if (publishedIds.contains(correlationId)) {
        return correlationId; // one event per failed execution
      }
      publishedIds.add(correlationId);

      Application_Error_Event__e evt = new Application_Error_Event__e(
        Correlation_Id__c = correlationId,
        Component_Name__c = truncate(
          'Trigger:' + component,
          Application_Log__c.Component_Name__c.getDescribe().getLength()
        ),
        Error__c = truncate(
          sanitize(buildError(ex)),
          Application_Log__c.Error__c.getDescribe().getLength()
        ),
        Body__c = truncate(
          buildBody(correlationId, requestId, objectName, operation, records),
          Application_Log__c.Body__c.getDescribe().getLength()
        ),
        Response__c = truncate(
          'Status=Failed; OriginalTransaction=RolledBack; Email=Pending; Slack=Pending',
          Application_Log__c.Response__c.getDescribe().getLength()
        )
      );
      publish(evt);
    } catch (Exception loggingEx) {
      System.debug(
        LoggingLevel.ERROR,
        'ApplicationErrorLogger failure. CorrelationId=' +
        correlationId +
        '; Original=' +
        (ex == null ? null : ex.getTypeName() + ': ' + ex.getMessage()) +
        '; LoggingError=' +
        loggingEx.getMessage()
      );
    }
    return correlationId;
  }

  private static void publish(Application_Error_Event__e evt) {
    if (Test.isRunningTest()) {
      publishedEvents.add(evt);
    }
    Database.SaveResult result;
    if (forcePublishFailure) {
      throw new EventPublishException('Forced publish failure');
    }
    result = EventBus.publish(evt);
    if (!result.isSuccess()) {
      throw new EventPublishException(
        result.getErrors().isEmpty()
          ? 'Unknown publish error'
          : result.getErrors()[0].getMessage()
      );
    }
  }

  /** Subscriber side: runs in its own transaction. Creates one log per correlation id. */
  public static void persistEvents(List<Application_Error_Event__e> events) {
    if (isLogging)
      return;
    isLogging = true;
    try {
      Set<String> seen = new Set<String>();
      List<Application_Log__c> logs = new List<Application_Log__c>();
      for (Application_Error_Event__e e : events) {
        if (!seen.add(e.Correlation_Id__c))
          continue;
        logs.add(
          new Application_Log__c(
            Component_Name__c = e.Component_Name__c,
            Error__c = e.Error__c,
            Body__c = e.Body__c,
            Response__c = e.Response__c
          )
        );
      }
      if (!logs.isEmpty())
        insert logs;
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.ERROR,
        'ApplicationErrorLogger persist failure: ' + ex.getMessage()
      );
    } finally {
      isLogging = false;
    }
  }

  @TestVisible
  private static String buildCorrelationId(
    String requestId,
    String component,
    String operation,
    Exception ex
  ) {
    String seed = String.join(
      new List<String>{
        requestId,
        component,
        operation,
        ex.getTypeName(),
        ex.getMessage()
      },
      '|'
    );
    return 'ERR-' +
      EncodingUtil.convertToHex(
          Crypto.generateDigest('SHA-256', Blob.valueOf(seed))
        )
        .substring(0, 32)
        .toUpperCase();
  }

  private static String buildError(Exception ex) {
    String s =
      ex.getTypeName() +
      ': ' +
      ex.getMessage() +
      '\nLine: ' +
      ex.getLineNumber();
    if (ex.getCause() != null) {
      s += '\nCause: ' + ex.getCause().getTypeName() + ': ' + ex.getCause().getMessage();
    }
    return s + '\nStack:\n' + ex.getStackTraceString();
  }

  private static String buildBody(
    String correlationId,
    String requestId,
    String objectName,
    String operation,
    List<SObject> records
  ) {
    List<Id> ids = new List<Id>();
    Integer count = 0;
    if (records != null) {
      count = records.size();
      for (SObject r : records) {
        if (r.Id != null && ids.size() < MAX_IDS)
          ids.add(r.Id);
      }
    }
    Map<String, Object> ctx = new Map<String, Object>{
      'correlationId' => correlationId,
      'object' => objectName,
      'operation' => operation,
      'recordCount' => count,
      'recordIds' => ids,
      'recordIdsTruncated' => count > ids.size() && !ids.isEmpty(),
      'userId' => UserInfo.getUserId(),
      'requestId' => requestId,
      'quiddity' => String.valueOf(Request.getCurrent().getQuiddity())
    };
    return JSON.serialize(ctx);
  }

  @TestVisible
  private static String sanitize(String input) {
    if (input == null)
      return null;
    String out = SECRET_PATTERN.matcher(input).replaceAll('$1$2' + REDACTED);
    out = EMAIL_PATTERN.matcher(out).replaceAll(REDACTED);
    return CARD_PATTERN.matcher(out).replaceAll(REDACTED);
  }

  @TestVisible
  private static String truncate(String input, Integer maxLen) {
    if (input == null || input.length() <= maxLen)
      return input;
    String marker = '…[truncated]';
    return input.left(maxLen - marker.length()) + marker;
  }

  public class EventPublishException extends Exception {
  }
}
