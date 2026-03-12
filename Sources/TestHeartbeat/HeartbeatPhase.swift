/// Well-known phase names for heartbeat events.
///
/// These constants define the vocabulary shared between the test library
/// and the external watchdog. Custom phase strings are still allowed via
/// `Heartbeat.beat(_:)`, but lifecycle events should use these constants
/// so the watchdog can reliably detect start, completion, and failure.
public enum HeartbeatPhase {
    public static let start = "start"
    public static let progress = "progress"
    public static let done = "done"
    public static let failed = "failed"
    public static let cancelled = "cancelled"
}
