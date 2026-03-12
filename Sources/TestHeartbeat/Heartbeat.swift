import Foundation
import Dispatch

/// Minimal liveness-signal API.
///
/// Call `beat(_:)` at meaningful phase boundaries so an external watchdog
/// can distinguish a running test from a hung one.
///
/// ```swift
/// let hb = try Heartbeat.start(testID: "myTest")
/// try hb.beat("setup")
/// try hb.beat("execute")
/// try hb.finish()
/// ```
public struct Heartbeat: Sendable {

    public let testID: String
    public var metadata: [String: String]

    private let sink: any HeartbeatSink
    private let config: HeartbeatConfig

    public init(
        testID: String,
        metadata: [String: String] = [:],
        config: HeartbeatConfig = .fromEnvironment(),
        sink: (any HeartbeatSink)? = nil
    ) {
        self.testID = testID
        self.metadata = metadata
        self.config = config
        self.sink = sink ?? FileHeartbeatSink(config: config)
    }

    /// Create a heartbeat and immediately emit a `start` event.
    public static func start(
        testID: String,
        metadata: [String: String] = [:],
        config: HeartbeatConfig = .fromEnvironment(),
        sink: (any HeartbeatSink)? = nil
    ) throws -> Heartbeat {
        let hb = Heartbeat(
            testID: testID,
            metadata: metadata,
            config: config,
            sink: sink
        )
        try hb.beat(HeartbeatPhase.start)
        return hb
    }

    // MARK: - Beat

    /// Emit a heartbeat event for the given phase.
    public func beat(
        _ phase: String,
        metadata extra: [String: String] = [:]
    ) throws {
        let event = HeartbeatEvent(
            testID: testID,
            phase: phase,
            monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            processID: ProcessInfo.processInfo.processIdentifier,
            threadID: config.includeThreadID ? currentThreadID() : nil,
            metadata: metadata.merging(extra) { _, new in new }
        )

        switch config.failureMode {
        case .throwError:
            try sink.write(event)
        case .ignore:
            do {
                try sink.write(event)
            } catch {
                // Heartbeat write failure intentionally suppressed per failureMode configuration.
            }
        }
    }

    // MARK: - Lifecycle

    /// Emit a `done` event indicating the test completed successfully.
    public func finish(metadata: [String: String] = [:]) throws {
        try beat(HeartbeatPhase.done, metadata: metadata)
    }

    /// Emit a `failed` event indicating the test encountered an error.
    public func fail(metadata: [String: String] = [:]) throws {
        try beat(HeartbeatPhase.failed, metadata: metadata)
    }

    /// Emit a `cancelled` event indicating the test was cancelled.
    public func cancel(metadata: [String: String] = [:]) throws {
        try beat(HeartbeatPhase.cancelled, metadata: metadata)
    }

    // MARK: - Scoped Phase

    /// Execute an operation wrapped by phase start/done/failed events.
    ///
    /// Emits `name` before the operation, `name:done` on success,
    /// and `name:failed` on error. Errors from the operation are always
    /// rethrown; heartbeat failures in the error path are suppressed
    /// to preserve the original error.
    public func withPhase<T>(
        _ name: String,
        metadata: [String: String] = [:],
        operation: () async throws -> T
    ) async throws -> T {
        try beat(name, metadata: metadata)
        do {
            let result = try await operation()
            try beat("\(name):done", metadata: metadata)
            return result
        } catch {
            do {
                try beat("\(name):failed", metadata: metadata)
            } catch {
                // Suppress heartbeat failure to preserve the original error.
            }
            throw error
        }
    }
}

// MARK: - Private

private func currentThreadID() -> UInt64? {
    var tid: UInt64 = 0
    guard pthread_threadid_np(nil, &tid) == 0 else { return nil }
    return tid
}
