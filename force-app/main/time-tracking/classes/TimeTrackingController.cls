public with sharing class TimeTrackingController {

    public static final String STATUS_IN_PROGRESS = TimeTrackingConstants.STATUS_IN_PROGRESS;
    public static final String STATUS_COMPLETED = TimeTrackingConstants.STATUS_COMPLETED;
    public static final String ADMIN_PERMISSION_SET_NAME = TimeTrackingConstants.ADMIN_PERMISSION_SET_NAME;
    public static final Long MAX_ENTRY_DURATION_MS = 24L * 60 * 60 * 1000;

    private static final Set<String> SUPPORTED_CLIENT_OBJECTS = new Set<String>{ 'Case', 'Store__c', 'Account' };

    public class TimeTrackingWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String assigneeName { get; set; }
        @AuraEnabled public Datetime startTime { get; set; }
        @AuraEnabled public Datetime endTime { get; set; }
        @AuraEnabled public Decimal durationMinutes { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String comments { get; set; }
        @AuraEnabled public Id relatedRecordId { get; set; }
        @AuraEnabled public String relatedRecordName { get; set; }
        @AuraEnabled public Datetime pauseStartedAt { get; set; }
        @AuraEnabled public Decimal pausedDurationMinutes { get; set; }
        @AuraEnabled public Datetime lastHeartbeat { get; set; }
        @AuraEnabled public String timerInstanceId { get; set; }
        @AuraEnabled public Boolean isManualEntry { get; set; }
    }

    public class TimeTrackingData {
        @AuraEnabled public List<TimeTrackingWrapper> records { get; set; }
        @AuraEnabled public TimeTrackingWrapper activeTimer { get; set; }
        @AuraEnabled public TimeTrackingWrapper blockingTimer { get; set; }
        @AuraEnabled public Decimal totalMinutes { get; set; }
        @AuraEnabled public String objectType { get; set; }
        @AuraEnabled public Boolean isAdmin { get; set; }
    }

    public class StartTimerResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Id timeTrackingId { get; set; }
        @AuraEnabled public TimeTrackingWrapper blockingTimer { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static TimeTrackingData getTimeTrackingData(Id recordId) {
        try {
            String objectType = recordId != null ? resolveClientObjectType(recordId) : null;

            List<Time_Tracking__c> records = queryRelatedRecords(recordId, objectType);

            Id currentUserId = UserInfo.getUserId();
            TimeTrackingData data = new TimeTrackingData();
            data.objectType = objectType;
            data.records = new List<TimeTrackingWrapper>();
            data.totalMinutes = 0;
            data.isAdmin = hasAdminAccess();

            for (Time_Tracking__c record : records) {
                TimeTrackingWrapper wrapper = toWrapper(record);
                data.records.add(wrapper);
                data.totalMinutes += wrapper.durationMinutes;
            }

            Time_Tracking__c currentActive = queryCurrentUserActiveRecord(currentUserId);
            if (currentActive != null) {
                if (isSameContext(currentActive, recordId, objectType)) {
                    data.activeTimer = toWrapper(currentActive);
                } else {
                    data.blockingTimer = toWrapper(currentActive);
                }
            }

            return data;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error loading time tracking data: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static StartTimerResult startTimer(Id recordId, String type, String instanceId) {
        try {
            String objectType = recordId != null ? resolveClientObjectType(recordId) : null;
            String resolvedType = resolveType(recordId, type);

            Id currentUserId = UserInfo.getUserId();
            StartTimerResult result = new StartTimerResult();
            result.success = false;

            Time_Tracking__c existing = queryCurrentUserActiveRecord(currentUserId);
            if (existing != null) {
                Boolean sameInstance = instanceId == existing.Timer_Instance_Id__c;
                Boolean sameContext = isSameContext(existing, recordId, objectType);
                if (existing.Status__c == STATUS_IN_PROGRESS && sameInstance && sameContext) {
                    result.success = true;
                    result.timeTrackingId = existing.Id;
                    return result;
                }
                result.blockingTimer = toWrapper(existing);
                return result;
            }

            Time_Tracking__c newRecord = new Time_Tracking__c(
                Assignee__c = currentUserId,
                Start_Time__c = System.now(),
                Status__c = STATUS_IN_PROGRESS,
                Type__c = resolvedType,
                Timer_Instance_Id__c = instanceId,
                Last_Heartbeat__c = System.now(),
                Paused_Duration_Minutes__c = 0
            );
            if (recordId != null) {
                setRelatedRecord(newRecord, recordId, objectType);
            }

            try {
                insert newRecord;
            } catch (DmlException dmlEx) {
                if (dmlEx.getMessage().contains('DUPLICATE_VALUE')) {
                    Time_Tracking__c blockingRecord = queryCurrentUserActiveRecord(currentUserId);
                    result.blockingTimer = blockingRecord != null ? toWrapper(blockingRecord) : null;
                    return result;
                }
                throw dmlEx;
            }

            result.success = true;
            result.timeTrackingId = newRecord.Id;
            publishUpdateEvent(currentUserId, newRecord.Id, STATUS_IN_PROGRESS, instanceId);
            return result;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error starting timer: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static TimeTrackingWrapper pauseTimer(Id timeTrackingId, String pauseStatus, String instanceId) {
        if (timeTrackingId == null) {
            throw new AuraHandledException('Time Tracking Id is required.');
        }
        if (!TimeTrackingConstants.PAUSED_STATUSES.contains(pauseStatus)) {
            throw new AuraHandledException('Invalid pause status.');
        }
        try {
            Time_Tracking__c record = queryFullRecordById(timeTrackingId);
            if (record.Assignee__c != UserInfo.getUserId()) {
                throw new AuraHandledException('You can only pause your own timer.');
            }
            if (record.Status__c != STATUS_IN_PROGRESS) {
                throw new AuraHandledException('Only a running timer can be paused.');
            }

            record.Status__c = pauseStatus;
            record.Pause_Started_At__c = System.now();
            update record;
            publishUpdateEvent(record.Assignee__c, record.Id, pauseStatus, instanceId);
            return toWrapper([SELECT Id, Assignee__c, Account__c, Case__c, Store__c, Start_Time__c, End_Time__c,
                                      Duration__c, Status__c, Type__c, Comments__c, Pause_Started_At__c,
                                      Paused_Duration_Minutes__c, Last_Heartbeat__c, Timer_Instance_Id__c, Is_Manual_Entry__c,
                                      Assignee__r.Name, Case__r.CaseNumber, Store__r.Name, Account__r.Name
                               FROM Time_Tracking__c WHERE Id = :record.Id]);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error pausing timer: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static TimeTrackingWrapper resumeTimer(Id timeTrackingId, String instanceId, Boolean takeOver) {
        if (timeTrackingId == null) {
            throw new AuraHandledException('Time Tracking Id is required.');
        }
        try {
            Time_Tracking__c record = queryFullRecordById(timeTrackingId);
            if (record.Assignee__c != UserInfo.getUserId()) {
                throw new AuraHandledException('You can only resume your own timer.');
            }
            if (!TimeTrackingConstants.PAUSED_STATUSES.contains(record.Status__c)) {
                throw new AuraHandledException('Only a paused timer can be resumed.');
            }

            Decimal pauseMinutes = minutesBetween(record.Pause_Started_At__c, System.now());
            record.Paused_Duration_Minutes__c = (record.Paused_Duration_Minutes__c == null ? 0 : record.Paused_Duration_Minutes__c) + pauseMinutes;
            record.Pause_Started_At__c = null;
            record.Status__c = STATUS_IN_PROGRESS;
            record.Timer_Instance_Id__c = instanceId;
            record.Last_Heartbeat__c = System.now();
            update record;
            publishUpdateEvent(record.Assignee__c, record.Id, STATUS_IN_PROGRESS, instanceId);
            return toWrapper(queryFullRecordById(record.Id));
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error resuming timer: ' + ex.getMessage());
        }
    }

    /**
     * Keeps a running timer alive while at least one browser tab that owns it
     * (same Timer_Instance_Id__c) is open. Returns the timer's status after
     * the call so the tab can refresh if the timer is no longer running.
     *
     * If the previous heartbeat is older than the stale threshold - the tab
     * was asleep, frozen, offline, or every tab was closed and this is a late
     * beat - the gap is NOT papered over: the timer is paused as
     * "Paused - Offline" at the last heartbeat instead, so unobserved time is
     * excluded and the user decides whether to resume.
     */
    @AuraEnabled
    public static String heartbeat(Id timeTrackingId, String instanceId) {
        if (timeTrackingId == null) {
            return null;
        }
        try {
            List<Time_Tracking__c> records = [
                SELECT Id, Assignee__c, Status__c, Timer_Instance_Id__c, Start_Time__c, Last_Heartbeat__c
                FROM Time_Tracking__c
                WHERE Id = :timeTrackingId
                LIMIT 1
            ];
            if (records.isEmpty()) {
                return null;
            }
            Time_Tracking__c record = records[0];
            Boolean ownedByCurrentUser = record.Assignee__c == UserInfo.getUserId();
            Boolean instanceMatches = instanceId != null && instanceId == record.Timer_Instance_Id__c;
            if (ownedByCurrentUser && instanceMatches && record.Status__c == STATUS_IN_PROGRESS) {
                if (isHeartbeatStale(record, System.now())) {
                    pauseOffline(record, heartbeatPausePoint(record));
                    return TimeTrackingConstants.STATUS_PAUSED_OFFLINE;
                }
                update new Time_Tracking__c(Id = record.Id, Last_Heartbeat__c = System.now());
            }
            return record.Status__c;
        } catch (Exception ex) {
            // Heartbeats are best-effort; swallow failures rather than surfacing errors to the user.
            return null;
        }
    }

    /**
     * Called by a Time Tracking component when it loads, when its tab becomes
     * visible again, and when the browser comes back online - before it
     * starts sending heartbeats. Auto-pauses the current user's running timer
     * as "Paused - Offline" when:
     *  1. the browser reports that the last open tab owning this timer was
     *     closed (closedTimerId / secondsSinceTabClosed, measured by the
     *     client so clock skew does not matter) and no tab heartbeated after
     *     that moment; or
     *  2. no tab has heartbeated for longer than the stale threshold.
     * Returns true when the timer was paused.
     */
    @AuraEnabled
    public static Boolean reconcileTimer(String instanceId, Id closedTimerId, Integer secondsSinceTabClosed) {
        try {
            Time_Tracking__c record = queryCurrentUserActiveRecord(UserInfo.getUserId());
            if (record == null || record.Status__c != STATUS_IN_PROGRESS) {
                return false;
            }
            Datetime now = System.now();

            Boolean tabCloseReported = closedTimerId != null
                && closedTimerId == record.Id
                && secondsSinceTabClosed != null
                && secondsSinceTabClosed >= 0
                && instanceId != null
                && instanceId == record.Timer_Instance_Id__c;
            if (tabCloseReported) {
                Datetime closedAt = now.addSeconds(-secondsSinceTabClosed);
                Boolean noHeartbeatSinceClose = record.Last_Heartbeat__c == null
                    || record.Last_Heartbeat__c <= closedAt.addSeconds(TimeTrackingConstants.TAB_CLOSE_TOLERANCE_SECONDS);
                if (noHeartbeatSinceClose) {
                    Datetime pausePoint = closedAt < record.Start_Time__c ? record.Start_Time__c : closedAt;
                    pauseOffline(record, pausePoint);
                    return true;
                }
            }

            if (isHeartbeatStale(record, now)) {
                pauseOffline(record, heartbeatPausePoint(record));
                return true;
            }
            return false;
        } catch (Exception ex) {
            throw new AuraHandledException('Error checking timer state: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static Id createManualEntry(Id recordId, String type, Datetime startTime, Datetime endTime, String comments) {
        if (startTime == null || endTime == null) {
            throw new AuraHandledException('Start time and end time are required.');
        }
        if (endTime <= startTime) {
            throw new AuraHandledException('End time must be after start time.');
        }
        if (endTime.getTime() - startTime.getTime() > MAX_ENTRY_DURATION_MS) {
            throw new AuraHandledException('A single time entry cannot exceed 24 hours.');
        }
        try {
            String objectType = recordId != null ? resolveClientObjectType(recordId) : null;
            String resolvedType = resolveType(recordId, type);
            if (!Schema.sObjectType.Time_Tracking__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create time tracking records.');
            }

            Time_Tracking__c newRecord = new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Start_Time__c = startTime,
                End_Time__c = endTime,
                Status__c = STATUS_COMPLETED,
                Type__c = resolvedType,
                Paused_Duration_Minutes__c = 0,
                Is_Manual_Entry__c = true,
                Comments__c = String.isBlank(comments) ? null : comments.trim()
            );
            if (recordId != null) {
                setRelatedRecord(newRecord, recordId, objectType);
            }
            insert newRecord;
            publishUpdateEvent(newRecord.Assignee__c, newRecord.Id, STATUS_COMPLETED, null);
            return newRecord.Id;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error creating time tracking record: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void updateTimeTracking(Id timeTrackingId, Datetime startTime, Datetime endTime, String comments) {
        if (timeTrackingId == null) {
            throw new AuraHandledException('Time Tracking Id is required.');
        }
        if (startTime == null || endTime == null) {
            throw new AuraHandledException('Start time and end time are required.');
        }
        if (endTime <= startTime) {
            throw new AuraHandledException('End time must be after start time.');
        }
        if (endTime.getTime() - startTime.getTime() > MAX_ENTRY_DURATION_MS) {
            throw new AuraHandledException('A single time entry cannot exceed 24 hours.');
        }
        try {
            if (!hasAdminAccess()) {
                throw new AuraHandledException('You do not have permission to edit time tracking records.');
            }
            if (!Schema.sObjectType.Time_Tracking__c.isUpdateable()) {
                throw new AuraHandledException('You do not have permission to edit time tracking records.');
            }

            List<Time_Tracking__c> matches = [
                SELECT Id, Assignee__c, Status__c, Paused_Duration_Minutes__c, Timer_Instance_Id__c
                FROM Time_Tracking__c
                WHERE Id = :timeTrackingId
                LIMIT 1
            ];
            if (matches.isEmpty()) {
                throw new AuraHandledException('This time tracking record no longer exists.');
            }
            Time_Tracking__c record = matches[0];

            // Keep previously recorded paused minutes, but never more than the
            // edited range, so the edited duration cannot go negative.
            Decimal rangeMinutes = (endTime.getTime() - startTime.getTime()) / 60000.0;
            Decimal pausedMinutes = record.Paused_Duration_Minutes__c == null ? 0 : record.Paused_Duration_Minutes__c;
            record.Paused_Duration_Minutes__c = pausedMinutes > rangeMinutes ? 0 : pausedMinutes;
            record.Start_Time__c = startTime;
            record.End_Time__c = endTime;
            record.Status__c = STATUS_COMPLETED;
            record.Pause_Started_At__c = null;
            record.Comments__c = String.isBlank(comments) ? null : comments.trim();
            update record;
            publishUpdateEvent(record.Assignee__c, record.Id, STATUS_COMPLETED, record.Timer_Instance_Id__c);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error updating time tracking record: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void completeTimer(Id timeTrackingId, String comments) {
        if (timeTrackingId == null) {
            throw new AuraHandledException('Time Tracking Id is required.');
        }
        try {
            Time_Tracking__c record = queryFullRecordById(timeTrackingId);

            if (record.Assignee__c != UserInfo.getUserId()) {
                throw new AuraHandledException('You can only complete your own time tracking records.');
            }
            if (record.Status__c == STATUS_COMPLETED) {
                throw new AuraHandledException('This timer is already completed.');
            }

            if (TimeTrackingConstants.PAUSED_STATUSES.contains(record.Status__c)) {
                Decimal pauseMinutes = minutesBetween(record.Pause_Started_At__c, System.now());
                record.Paused_Duration_Minutes__c = (record.Paused_Duration_Minutes__c == null ? 0 : record.Paused_Duration_Minutes__c) + pauseMinutes;
                record.Pause_Started_At__c = null;
            }

            record.Status__c = STATUS_COMPLETED;
            record.End_Time__c = System.now();
            record.Comments__c = String.isBlank(comments) ? null : comments.trim();
            update record;
            publishUpdateEvent(record.Assignee__c, record.Id, STATUS_COMPLETED, record.Timer_Instance_Id__c);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error completing timer: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteTimeTracking(Id timeTrackingId, String comments) {
        if (timeTrackingId == null) {
            throw new AuraHandledException('Time Tracking Id is required.');
        }
        try {
            if (!hasAdminAccess()) {
                throw new AuraHandledException('You do not have permission to delete time tracking records.');
            }
            if (!Schema.sObjectType.Time_Tracking__c.isDeletable()) {
                throw new AuraHandledException('You do not have permission to delete time tracking records.');
            }

            List<Time_Tracking__c> matches = [
                SELECT Id, Assignee__c, Comments__c, Timer_Instance_Id__c
                FROM Time_Tracking__c
                WHERE Id = :timeTrackingId
                LIMIT 1
            ];
            if (matches.isEmpty()) {
                throw new AuraHandledException('This time tracking record no longer exists.');
            }
            Time_Tracking__c record = matches[0];

            if (!String.isBlank(comments)) {
                record.Comments__c = comments.trim();
                update record;
            }
            delete record;
            publishUpdateEvent(record.Assignee__c, record.Id, STATUS_COMPLETED, record.Timer_Instance_Id__c);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error deleting time tracking record: ' + ex.getMessage());
        }
    }

    /**
     * Publishes a platform event so every open Time Tracking component for
     * this user - across browser tabs and windows, not just this one -
     * refreshes immediately when a timer starts, pauses, resumes, or
     * completes. empApi push notifies all of them without polling.
     */
    private static void publishUpdateEvent(Id assigneeId, Id timerId, String status, String instanceId) {
        EventBus.publish(new TimeTracking_Update__e(
            Assignee_Id__c = String.valueOf(assigneeId),
            Timer_Id__c = String.valueOf(timerId),
            Status__c = status,
            Originating_Instance_Id__c = instanceId
        ));
    }

    /**
     * Admin edit/delete is granted by the Time_Tracking_Admin_Access custom
     * permission (included in the Time Tracking Admin permission set). Using
     * the custom permission also works when the permission set is granted
     * through a Permission Set Group or a profile. A direct assignment of the
     * Time Tracking Admin permission set is still honored as a fallback.
     */
    @TestVisible
    private static Boolean hasAdminAccess() {
        if (FeatureManagement.checkPermission(TimeTrackingConstants.ADMIN_CUSTOM_PERMISSION)) {
            return true;
        }
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = :ADMIN_PERMISSION_SET_NAME
        ] > 0;
    }

    private static Boolean isHeartbeatStale(Time_Tracking__c record, Datetime now) {
        Datetime staleCutoff = now.addMinutes(-TimeTrackingConstants.DEFAULT_STALE_THRESHOLD_MINUTES);
        Datetime lastSeen = record.Last_Heartbeat__c != null ? record.Last_Heartbeat__c : record.Start_Time__c;
        return lastSeen != null && lastSeen < staleCutoff;
    }

    private static Datetime heartbeatPausePoint(Time_Tracking__c record) {
        return record.Last_Heartbeat__c != null ? record.Last_Heartbeat__c : record.Start_Time__c;
    }

    private static void pauseOffline(Time_Tracking__c record, Datetime pausePoint) {
        update new Time_Tracking__c(
            Id = record.Id,
            Status__c = TimeTrackingConstants.STATUS_PAUSED_OFFLINE,
            Pause_Started_At__c = pausePoint
        );
        publishUpdateEvent(record.Assignee__c, record.Id, TimeTrackingConstants.STATUS_PAUSED_OFFLINE, record.Timer_Instance_Id__c);
    }

    private static String resolveClientObjectType(Id recordId) {
        String objectType = recordId.getSObjectType().getDescribe().getName();
        if (!SUPPORTED_CLIENT_OBJECTS.contains(objectType)) {
            throw new AuraHandledException('Time tracking is only supported on Case, Account, and Store records.');
        }
        return objectType;
    }

    private static String resolveType(Id recordId, String requestedType) {
        if (recordId != null) {
            return TimeTrackingConstants.TYPE_CLIENT;
        }
        if (!TimeTrackingConstants.INTERNAL_TYPES.contains(requestedType)) {
            throw new AuraHandledException('Internal time entries must be Internal Meeting or Internal Task.');
        }
        return requestedType;
    }

    private static Decimal minutesBetween(Datetime pauseStart, Datetime pauseEnd) {
        if (pauseStart == null) {
            return 0;
        }
        return ((pauseEnd.getTime() - pauseStart.getTime()) / 60000.0);
    }

    private static Time_Tracking__c queryFullRecordById(Id timeTrackingId) {
        return [
            SELECT Id, Assignee__c, Account__c, Case__c, Store__c, Start_Time__c, End_Time__c,
                   Duration__c, Status__c, Type__c, Comments__c, Pause_Started_At__c,
                   Paused_Duration_Minutes__c, Last_Heartbeat__c, Timer_Instance_Id__c, Is_Manual_Entry__c,
                   Assignee__r.Name, Case__r.CaseNumber, Store__r.Name, Account__r.Name
            FROM Time_Tracking__c
            WHERE Id = :timeTrackingId
            LIMIT 1
        ];
    }

    private static Time_Tracking__c queryCurrentUserActiveRecord(Id currentUserId) {
        List<Time_Tracking__c> records = [
            SELECT Id, Assignee__c, Account__c, Case__c, Store__c, Start_Time__c, End_Time__c,
                   Duration__c, Status__c, Type__c, Comments__c, Pause_Started_At__c,
                   Paused_Duration_Minutes__c, Last_Heartbeat__c, Timer_Instance_Id__c, Is_Manual_Entry__c,
                   Assignee__r.Name, Case__r.CaseNumber, Store__r.Name, Account__r.Name
            FROM Time_Tracking__c
            WHERE Assignee__c = :currentUserId
              AND Status__c IN :TimeTrackingConstants.ACTIVE_OR_PAUSED_STATUSES
            ORDER BY Start_Time__c DESC
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    private static List<Time_Tracking__c> queryRelatedRecords(Id recordId, String objectType) {
        if (recordId == null) {
            return [
                SELECT Id, Assignee__c, Account__c, Case__c, Store__c, Start_Time__c, End_Time__c, Duration__c,
                       Status__c, Type__c, Comments__c, Pause_Started_At__c, Paused_Duration_Minutes__c,
                       Last_Heartbeat__c, Timer_Instance_Id__c, Is_Manual_Entry__c, Assignee__r.Name, Case__r.CaseNumber, Store__r.Name, Account__r.Name
                FROM Time_Tracking__c
                WHERE Assignee__c = :UserInfo.getUserId()
                  AND Type__c IN :TimeTrackingConstants.INTERNAL_TYPES
                ORDER BY Start_Time__c DESC
                LIMIT 200
            ];
        }
        if (objectType == 'Case') {
            return [
                SELECT Id, Assignee__c, Account__c, Case__c, Store__c, Start_Time__c, End_Time__c, Duration__c,
                       Status__c, Type__c, Comments__c, Pause_Started_At__c, Paused_Duration_Minutes__c,
                       Last_Heartbeat__c, Timer_Instance_Id__c, Is_Manual_Entry__c, Assignee__r.Name, Case__r.CaseNumber, Store__r.Name, Account__r.Name
                FROM Time_Tracking__c
                WHERE Case__c = :recordId
                ORDER BY Start_Time__c DESC
            ];
        }
        if (objectType == 'Account') {
            return [
                SELECT Id, Assignee__c, Account__c, Case__c, Store__c, Start_Time__c, End_Time__c, Duration__c,
                       Status__c, Type__c, Comments__c, Pause_Started_At__c, Paused_Duration_Minutes__c,
                       Last_Heartbeat__c, Timer_Instance_Id__c, Is_Manual_Entry__c, Assignee__r.Name, Case__r.CaseNumber, Store__r.Name, Account__r.Name
                FROM Time_Tracking__c
                WHERE Account__c = :recordId
                ORDER BY Start_Time__c DESC
            ];
        }

        return [
            SELECT Id, Assignee__c, Account__c, Case__c, Store__c, Start_Time__c, End_Time__c, Duration__c,
                   Status__c, Type__c, Comments__c, Pause_Started_At__c, Paused_Duration_Minutes__c,
                   Last_Heartbeat__c, Timer_Instance_Id__c, Is_Manual_Entry__c, Assignee__r.Name, Case__r.CaseNumber, Store__r.Name, Account__r.Name
            FROM Time_Tracking__c
            WHERE Store__c = :recordId
              AND Case__c = null
            ORDER BY Start_Time__c DESC
        ];
    }

    private static TimeTrackingWrapper toWrapper(Time_Tracking__c record) {
        TimeTrackingWrapper wrapper = new TimeTrackingWrapper();
        wrapper.id = record.Id;
        wrapper.assigneeName = record.Assignee__r != null ? record.Assignee__r.Name : '';
        wrapper.startTime = record.Start_Time__c;
        wrapper.endTime = record.End_Time__c;
        wrapper.durationMinutes = record.Duration__c == null ? 0 : record.Duration__c;
        wrapper.status = record.Status__c;
        wrapper.type = record.Type__c;
        wrapper.comments = record.Comments__c;
        wrapper.relatedRecordId = getRelatedRecordId(record);
        wrapper.relatedRecordName = getRelatedRecordName(record);
        wrapper.pauseStartedAt = record.Pause_Started_At__c;
        wrapper.pausedDurationMinutes = record.Paused_Duration_Minutes__c;
        wrapper.lastHeartbeat = record.Last_Heartbeat__c;
        wrapper.timerInstanceId = record.Timer_Instance_Id__c;
        wrapper.isManualEntry = record.Is_Manual_Entry__c == true;
        return wrapper;
    }

    private static Id getRelatedRecordId(Time_Tracking__c record) {
        if (record.Case__c != null) {
            return record.Case__c;
        }
        if (record.Store__c != null) {
            return record.Store__c;
        }
        return record.Account__c;
    }

    private static String getRelatedRecordName(Time_Tracking__c record) {
        if (record.Case__c != null && record.Case__r != null) {
            return record.Case__r.CaseNumber;
        }
        if (record.Store__c != null && record.Store__r != null) {
            return record.Store__r.Name;
        }
        if (record.Account__c != null && record.Account__r != null) {
            return record.Account__r.Name;
        }
        return '';
    }

    private static Boolean isSameContext(Time_Tracking__c record, Id recordId, String objectType) {
        if (recordId == null) {
            return record.Case__c == null && record.Store__c == null && record.Account__c == null
                && TimeTrackingConstants.INTERNAL_TYPES.contains(record.Type__c);
        }
        if (objectType == 'Case') {
            return record.Case__c == recordId;
        }
        if (objectType == 'Account') {
            return record.Account__c == recordId;
        }
        return record.Store__c == recordId && record.Case__c == null;
    }

    private static void setRelatedRecord(Time_Tracking__c record, Id recordId, String objectType) {
        if (objectType == 'Case') {
            record.Case__c = recordId;
            record.Store__c = [SELECT Store__c FROM Case WHERE Id = :recordId].Store__c;
        } else if (objectType == 'Account') {
            record.Account__c = recordId;
        } else {
            record.Store__c = recordId;
        }
    }
}
