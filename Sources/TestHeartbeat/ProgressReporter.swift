import Foundation

/// Rate-limited heartbeat reporter for long-running loops.
///
/// Calls to `every(_:phase:metadata:)` are throttled so the sink is
/// not flooded during tight iterations.
///
/// ```swift
/// var progress = try ProgressReporter(testID: "benchmark")
/// for i in 0..<10_000 {
///     try progress.every(.milliseconds(500), phase: "iteration-\(i)")
///     try await work(i)
/// }
/// try progress.phase("done")
/// ```
public struct ProgressReporter: Sendable {

    public let heartbeat: Heartbeat
    public let minimumInterval: Duration

    private var lastBeat: ContinuousClock.Instant
    private let clock = ContinuousClock()

    public init(
        testID: String,
        metadata: [String: String] = [:],
        minimumInterval: Duration = .seconds(1),
        sink: any HeartbeatSink = FileHeartbeatSink(),
        failureMode: HeartbeatFailureMode = .throwError
    ) throws {
        self.heartbeat = try Heartbeat.start(
            testID: testID,
            metadata: metadata,
            sink: sink,
            failureMode: failureMode
        )
        self.minimumInterval = minimumInterval
        self.lastBeat = clock.now
    }

    /// Emit a heartbeat unconditionally for the named phase.
    public mutating func phase(
        _ name: String,
        metadata: [String: String] = [:]
    ) throws {
        try heartbeat.beat(name, metadata: metadata)
        lastBeat = clock.now
    }

    /// Emit a heartbeat only if at least `interval` has elapsed since the last beat.
    public mutating func every(
        _ interval: Duration? = nil,
        phase: @autoclosure () -> String,
        metadata: [String: String] = [:]
    ) throws {
        let threshold = interval ?? minimumInterval
        let now = clock.now
        if now - lastBeat >= threshold {
            try heartbeat.beat(phase(), metadata: metadata)
            lastBeat = now
        }
    }
}
