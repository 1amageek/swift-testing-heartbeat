/// Destination for heartbeat events.
///
/// Implement this protocol to direct heartbeat output to a custom target
/// (e.g., stdout, socket, os_log).
public protocol HeartbeatSink: Sendable {
    func write(_ event: HeartbeatEvent) throws
}
