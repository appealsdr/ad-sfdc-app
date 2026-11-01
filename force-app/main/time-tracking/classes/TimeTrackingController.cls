public with sharing class TimeTrackingController {

    public static final String STATUS_IN_PROGRESS = 'In progress';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String ADMIN_PERMISSION_SET_NAME = 'Time_Tracking_Admin';
    public static final Long MAX_ENTRY_DURATION_MS = 24L * 60 * 60 * 1000;

    public class TimeTrackingWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String assigneeName { get; set; }
        @AuraEnabled public Datetime startTime { get; set; }
        @AuraEnabled public Datetime endTime { get; set; }
        @AuraEnabled public Decimal durationMinutes { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String comments { get; set; }
        @AuraEnabled public String relatedRecordName { get; set; }
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
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        try {
            String objectType = recordId.getSObjectType().getDescribe().getName();
            if (objectType != 'Case' && objectType != 'Store__c') {
                throw new AuraHandledException('Time tracking is only supported on Case and Store records.');
            }

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
                data.totalMinutes += getDurationMinutes(record);

                if (record.Status__c == STATUS_IN_PROGRESS && record.Assignee__c == currentUserId) {
                    if (isSameRelatedRecord(record, recordId, objectType)) {
                        data.activeTimer = wrapper;
                    } else if (data.blockingTimer == null) {
                        data.blockingTimer = wrapper;
                    }
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
    public static StartTimerResult startTimer(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        try {
            String objectType = recordId.getSObjectType().getDescribe().getName();
            if (objectType != 'Case' && objectType != 'Store__c') {
                throw new AuraHandledException('Time tracking is only supported on Case and Store records.');
            }

            Id currentUserId = UserInfo.getUserId();
            List<Time_Tracking__c> inProgressRecords = [
                SELECT Id, Assignee__c, Case__c, Store__c, Start_Time__c, End_Time__c,
                       Duration__c, Status__c, Comments__c,
                       Assignee__r.Name, Case__r.CaseNumber, Store__r.Name
                FROM Time_Tracking__c
                WHERE Assignee__c = :currentUserId
                  AND Status__c = :STATUS_IN_PROGRESS
                ORDER BY Start_Time__c DESC
                LIMIT 1
            ];

            StartTimerResult result = new StartTimerResult();
            result.success = false;

            if (!inProgressRecords.isEmpty()) {
                Time_Tracking__c blockingRecord = inProgressRecords[0];
                if (!isSameRelatedRecord(blockingRecord, recordId, objectType)) {
                    result.blockingTimer = toWrapper(blockingRecord);
                    return result;
                }

                result.timeTrackingId = blockingRecord.Id;
                result.success = true;
                return result;
            }

            Time_Tracking__c newRecord = new Time_Tracking__c(
                Assignee__c = currentUserId,
                Start_Time__c = System.now(),
                Status__c = STATUS_IN_PROGRESS
            );
            setRelatedRecord(newRecord, recordId, objectType);
            insert newRecord;

            result.success = true;
            result.timeTrackingId = newRecord.Id;
            return result;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error starting timer: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static Id createManualEntry(Id recordId, Datetime startTime, Datetime endTime, String comments) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
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
        if (String.isBlank(comments)) {
            throw new AuraHandledException('Comments are required.');
        }

        try {
            String objectType = recordId.getSObjectType().getDescribe().getName();
            if (objectType != 'Case' && objectType != 'Store__c') {
                throw new AuraHandledException('Time tracking is only supported on Case and Store records.');
            }
            if (!Schema.sObjectType.Time_Tracking__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create time tracking records.');
            }

            Time_Tracking__c newRecord = new Time_Tracking__c(
                Assignee__c = UserInfo.getUserId(),
                Start_Time__c = startTime,
                End_Time__c = endTime,
                Status__c = STATUS_COMPLETED,
                Comments__c = comments.trim()
            );
            setRelatedRecord(newRecord, recordId, objectType);
            insert newRecord;
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
        if (String.isBlank(comments)) {
            throw new AuraHandledException('Comments are required.');
        }

        try {
            if (!hasAdminAccess()) {
                throw new AuraHandledException('You do not have permission to edit time tracking records.');
            }
            if (!Schema.sObjectType.Time_Tracking__c.isUpdateable()) {
                throw new AuraHandledException('You do not have permission to edit time tracking records.');
            }

            Time_Tracking__c record = [
                SELECT Id, Status__c
                FROM Time_Tracking__c
                WHERE Id = :timeTrackingId
                LIMIT 1
            ];

            record.Start_Time__c = startTime;
            record.End_Time__c = endTime;
            record.Status__c = STATUS_COMPLETED;
            record.Comments__c = comments.trim();
            update record;
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
        if (String.isBlank(comments)) {
            throw new AuraHandledException('Comments are required to complete the timer.');
        }

        try {
            Time_Tracking__c record = [
                SELECT Id, Status__c, Assignee__c
                FROM Time_Tracking__c
                WHERE Id = :timeTrackingId
                LIMIT 1
            ];

            if (record.Assignee__c != UserInfo.getUserId()) {
                throw new AuraHandledException('You can only complete your own time tracking records.');
            }
            if (record.Status__c == STATUS_COMPLETED) {
                throw new AuraHandledException('This timer is already completed.');
            }

            record.Status__c = STATUS_COMPLETED;
            record.End_Time__c = System.now();
            record.Comments__c = comments.trim();
            update record;
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
        if (String.isBlank(comments)) {
            throw new AuraHandledException('Comments are required to delete the time tracking record.');
        }

        try {
            if (!hasAdminAccess()) {
                throw new AuraHandledException('You do not have permission to delete time tracking records.');
            }
            if (!Schema.sObjectType.Time_Tracking__c.isDeletable()) {
                throw new AuraHandledException('You do not have permission to delete time tracking records.');
            }

            Time_Tracking__c record = [
                SELECT Id, Assignee__c, Comments__c
                FROM Time_Tracking__c
                WHERE Id = :timeTrackingId
                LIMIT 1
            ];

            record.Comments__c = comments.trim();
            update record;
            delete record;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Error deleting time tracking record: ' + ex.getMessage());
        }
    }

    private static Boolean hasAdminAccess() {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = :ADMIN_PERMISSION_SET_NAME
        ] > 0;
    }

    private static List<Time_Tracking__c> queryRelatedRecords(Id recordId, String objectType) {
        if (objectType == 'Case') {
            return [
                SELECT Id, Assignee__c, Case__c, Store__c, Start_Time__c, End_Time__c, Duration__c,
                       Status__c, Comments__c, Assignee__r.Name, Case__r.CaseNumber, Store__r.Name
                FROM Time_Tracking__c
                WHERE Case__c = :recordId
                ORDER BY Start_Time__c DESC
            ];
        }

        return [
            SELECT Id, Assignee__c, Case__c, Store__c, Start_Time__c, End_Time__c, Duration__c,
                   Status__c, Comments__c, Assignee__r.Name, Case__r.CaseNumber, Store__r.Name
            FROM Time_Tracking__c
            WHERE Store__c = :recordId
            ORDER BY Start_Time__c DESC
        ];
    }

    private static TimeTrackingWrapper toWrapper(Time_Tracking__c record) {
        TimeTrackingWrapper wrapper = new TimeTrackingWrapper();
        wrapper.id = record.Id;
        wrapper.assigneeName = record.Assignee__r != null ? record.Assignee__r.Name : '';
        wrapper.startTime = record.Start_Time__c;
        wrapper.endTime = record.End_Time__c;
        wrapper.durationMinutes = getDurationMinutes(record);
        wrapper.status = record.Status__c;
        wrapper.comments = record.Comments__c;
        wrapper.relatedRecordName = getRelatedRecordName(record);
        return wrapper;
    }

    private static String getRelatedRecordName(Time_Tracking__c record) {
        if (record.Case__c != null && record.Case__r != null) {
            return record.Case__r.CaseNumber;
        }
        if (record.Store__c != null && record.Store__r != null) {
            return record.Store__r.Name;
        }
        return '';
    }

    private static Decimal getDurationMinutes(Time_Tracking__c record) {
        if (record.Status__c == STATUS_COMPLETED && record.Duration__c != null) {
            return record.Duration__c;
        }
        if (record.Start_Time__c != null && record.End_Time__c != null) {
            return ((record.End_Time__c.getTime() - record.Start_Time__c.getTime()) / 60000.0);
        }
        if (record.Status__c == STATUS_IN_PROGRESS && record.Start_Time__c != null) {
            return ((System.now().getTime() - record.Start_Time__c.getTime()) / 60000.0);
        }
        return 0;
    }

    private static Boolean isSameRelatedRecord(Time_Tracking__c record, Id recordId, String objectType) {
        if (objectType == 'Case') {
            return record.Case__c == recordId;
        }
        return record.Store__c == recordId;
    }

    private static void setRelatedRecord(Time_Tracking__c record, Id recordId, String objectType) {
        if (objectType == 'Case') {
            record.Case__c = recordId;
        } else {
            record.Store__c = recordId;
        }
    }
}