/**
 * Runs TimeTrackingCleanupService roughly once a minute.
 *
 * Apex cron expressions cannot repeat at sub-hour intervals (the seconds and
 * minutes fields must be plain integers, so '0 0/1 * * * ?' is rejected), so
 * the job re-schedules itself as a one-off run one minute later each time it
 * executes. An hourly watchdog job also runs the cleanup and restarts the
 * one-minute chain if it ever stops (e.g. after a failed execution).
 *
 * Start it once per org with:
 *     TimeTrackingCleanupScheduler.scheduleRecurringJob();
 */
public class TimeTrackingCleanupScheduler implements Schedulable {

    // Each one-off run gets a unique name: JOB_NAME + ' @ ' + run time.
    public static final String JOB_NAME = 'Time Tracking Stale Timer Cleanup';
    public static final String RUN_NAME_PREFIX = JOB_NAME + ' @ ';
    public static final String WATCHDOG_JOB_NAME = 'Time Tracking Cleanup Watchdog';
    public static final String WATCHDOG_CRON = '0 0 * * * ?';
    public static final Integer INTERVAL_MINUTES = TimeTrackingConstants.DEFAULT_CLEANUP_INTERVAL_MINUTES;

    private static final Set<String> LIVE_STATES = new Set<String>{ 'WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED', 'BLOCKED', 'PAUSED_BLOCKED' };

    private final Boolean isWatchdog;

    public TimeTrackingCleanupScheduler() {
        this(false);
    }

    public TimeTrackingCleanupScheduler(Boolean isWatchdog) {
        this.isWatchdog = isWatchdog == true;
    }

    public void execute(SchedulableContext context) {
        try {
            TimeTrackingCleanupService.cleanupStaleTimers();
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Time tracking cleanup failed: ' + ex.getMessage());
        }

        Id currentTriggerId = context != null ? context.getTriggerId() : null;
        if (!isWatchdog && currentTriggerId != null) {
            // Remove the finished one-off run so only the next run is listed.
            try {
                System.abortJob(currentTriggerId);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Could not abort finished cleanup run: ' + ex.getMessage());
            }
        }

        try {
            scheduleNextRun(currentTriggerId);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Could not schedule next cleanup run: ' + ex.getMessage());
        }
    }

    /**
     * Schedules the one-minute cleanup chain and the hourly watchdog if they
     * are not already scheduled. Safe to call multiple times.
     */
    public static Id scheduleRecurringJob() {
        List<CronTrigger> watchdog = [
            SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :WATCHDOG_JOB_NAME AND State IN :LIVE_STATES LIMIT 1
        ];
        if (watchdog.isEmpty()) {
            System.schedule(WATCHDOG_JOB_NAME, WATCHDOG_CRON, new TimeTrackingCleanupScheduler(true));
        }
        return scheduleNextRun(null);
    }

    /**
     * Removes both cleanup jobs (e.g. before a deployment that changes this class).
     */
    public static void unscheduleAll() {
        String runNamePattern = RUN_NAME_PREFIX + '%';
        for (CronTrigger job : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :WATCHDOG_JOB_NAME
               OR CronJobDetail.Name LIKE :runNamePattern
        ]) {
            System.abortJob(job.Id);
        }
    }

    private static Id scheduleNextRun(Id currentTriggerId) {
        Id existing = findPendingRun(currentTriggerId);
        if (existing != null) {
            return existing;
        }
        Datetime nextRun = System.now().addMinutes(INTERVAL_MINUTES);
        // Datetime.format() and System.schedule both use the running user's time zone.
        String cron = nextRun.format('s m H d M') + ' ? ' + nextRun.format('yyyy');
        String runName = RUN_NAME_PREFIX + nextRun.format('yyyy-MM-dd HH:mm:ss.SSS');
        return System.schedule(runName, cron, new TimeTrackingCleanupScheduler(false));
    }

    @TestVisible
    private static Id findPendingRun(Id excludeTriggerId) {
        String runNamePattern = RUN_NAME_PREFIX + '%';
        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :runNamePattern
              AND State IN :LIVE_STATES
              AND Id != :excludeTriggerId
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0].Id;
    }
}
