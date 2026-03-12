import Foundation

/// Rate-limited heartbeat reporter for long-running loops.
///
/// Calls to `every(_:phase:metadata:)` are throttled so the sink is
/// not flooded during tight iterations.
///
/// **Important:** This type is a value type with mutable state (`lastBeat`).
/// It is designed for use within a single execution context. Do not share
/// a single instance across concurrent tasks.
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
        config: HeartbeatConfig = .fromEnvironment(),
        sink: (any HeartbeatSink)? = nil
    ) throws {
        self.heartbeat = try Heartbeat.start(
            testID: testID,
            metadata: metadata,
            config: config,
            sink: sink
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

    // MARK: - Lifecycle

    /// Emit a `done` event indicating the test completed successfully.
    public func finish(metadata: [String: String] = [:]) throws {
        try heartbeat.finish(metadata: metadata)
    }

    /// Emit a `failed` event indicating the test encountered an error.
    public func fail(metadata: [String: String] = [:]) throws {
        try heartbeat.fail(metadata: metadata)
    }

    // MARK: - Scoped Phase

    /// Execute an operation wrapped by phase start/done/failed events.
    ///
    /// Emits `name` before the operation, `name:done` on success,
    /// and `name:failed` on error. The `lastBeat` timestamp is updated
    /// at each boundary.
    public mutating func withPhase<T>(
        _ name: String,
        metadata: [String: String] = [:],
        operation: () async throws -> T
    ) async throws -> T {
        try phase(name, metadata: metadata)
        do {
            let result = try await operation()
            try phase("\(name):done", metadata: metadata)
            return result
        } catch {
            do {
                try phase("\(name):failed", metadata: metadata)
            } catch {
                // Suppress heartbeat failure to preserve the original error.
            }
            throw error
        }
    }
}
