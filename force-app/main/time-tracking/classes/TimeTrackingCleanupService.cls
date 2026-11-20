public with sharing class TimeTrackingCleanupService {

    /**
     * Finds In-progress timers whose owning browser tab(s) have stopped
     * sending heartbeats and marks them Paused - Offline, using the last
     * heartbeat (or start time, if no heartbeat was ever recorded) as the
     * pause point so unobserved time stops accruing.
     */
    public static Integer cleanupStaleTimers() {
        Integer staleThresholdMinutes = TimeTrackingConstants.DEFAULT_STALE_THRESHOLD_MINUTES;
        Datetime staleCutoff = System.now().addMinutes(-staleThresholdMinutes);

        List<Time_Tracking__c> staleTimers = [
            SELECT Id, Assignee__c, Start_Time__c, Last_Heartbeat__c, Status__c, Paused_Duration_Minutes__c, Timer_Instance_Id__c
            FROM Time_Tracking__c
            WHERE Status__c = :TimeTrackingConstants.STATUS_IN_PROGRESS
              AND (Last_Heartbeat__c = null OR Last_Heartbeat__c < :staleCutoff)
              AND Start_Time__c < :staleCutoff
        ];

        if (staleTimers.isEmpty()) {
            return 0;
        }

        List<TimeTracking_Update__e> events = new List<TimeTracking_Update__e>();
        for (Time_Tracking__c timer : staleTimers) {
            Datetime pausePoint = timer.Last_Heartbeat__c != null ? timer.Last_Heartbeat__c : timer.Start_Time__c;
            timer.Status__c = TimeTrackingConstants.STATUS_PAUSED_OFFLINE;
            timer.Pause_Started_At__c = pausePoint;
            events.add(new TimeTracking_Update__e(
                Assignee_Id__c = String.valueOf(timer.Assignee__c),
                Timer_Id__c = String.valueOf(timer.Id),
                Status__c = TimeTrackingConstants.STATUS_PAUSED_OFFLINE,
                Originating_Instance_Id__c = timer.Timer_Instance_Id__c
            ));
        }

        update staleTimers;
        // Notify every open tab/window for these users as soon as the cleanup
        // job runs, instead of waiting for each tab's own polling cycle.
        EventBus.publish(events);
        return staleTimers.size();
    }
}
