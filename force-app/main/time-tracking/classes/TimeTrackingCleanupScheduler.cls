public class TimeTrackingCleanupScheduler implements Schedulable {

    public static final String JOB_NAME = 'Time Tracking Stale Timer Cleanup';
    public static final String CRON_EVERY_MINUTE = '0 0/1 * * * ?';

    public void execute(SchedulableContext context) {
        TimeTrackingCleanupService.cleanupStaleTimers();
    }

    /**
     * Schedules the recurring cleanup job if it is not already scheduled.
     * Safe to call multiple times (e.g. from an org initialization script).
     */
    public static Id scheduleRecurringJob() {
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        return System.schedule(JOB_NAME, CRON_EVERY_MINUTE, new TimeTrackingCleanupScheduler());
    }
}
