public class TimeTrackingConstants {

    public static final String STATUS_IN_PROGRESS = 'In progress';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_PAUSED_LUNCH = 'Paused - Lunch/Break';
    public static final String STATUS_PAUSED_OFFLINE = 'Paused - Offline';

    public static final Set<String> ACTIVE_OR_PAUSED_STATUSES = new Set<String>{
        STATUS_IN_PROGRESS,
        STATUS_PAUSED_LUNCH,
        STATUS_PAUSED_OFFLINE
    };

    public static final Set<String> PAUSED_STATUSES = new Set<String>{
        STATUS_PAUSED_LUNCH,
        STATUS_PAUSED_OFFLINE
    };

    public static final String TYPE_CLIENT = 'Client';
    public static final String TYPE_INTERNAL_MEETING = 'Internal Meeting';
    public static final String TYPE_INTERNAL_TASK = 'Internal Task';

    public static final Set<String> INTERNAL_TYPES = new Set<String>{
        TYPE_INTERNAL_MEETING,
        TYPE_INTERNAL_TASK
    };

    public static final Integer DEFAULT_HEARTBEAT_INTERVAL_SECONDS = 15;
    // A running timer is considered abandoned (tab/browser closed, laptop
    // asleep, network lost) once no open tab has sent a heartbeat for this
    // long. Two minutes leaves headroom for Chrome's intensive throttling of
    // hidden tabs (timers can be delayed to once per minute), so switching
    // focus to other tabs never causes a false "Paused - Offline".
    public static final Integer DEFAULT_STALE_THRESHOLD_MINUTES = 2;
    public static final Integer DEFAULT_CLEANUP_INTERVAL_MINUTES = 1;
    // Tolerance used when a reopened tab reports when the last tab was closed.
    public static final Integer TAB_CLOSE_TOLERANCE_SECONDS = 5;

    public static final String ADMIN_CUSTOM_PERMISSION = 'Time_Tracking_Admin_Access';
    public static final String ADMIN_PERMISSION_SET_NAME = 'Time_Tracking_Admin';
}
