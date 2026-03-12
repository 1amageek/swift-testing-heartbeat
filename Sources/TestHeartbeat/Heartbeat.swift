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
/// try hb.beat("done")
/// ```
public struct Heartbeat: Sendable {

    public let testID: String
    public var metadata: [String: String]

    private let sink: any HeartbeatSink
    private let failureMode: HeartbeatFailureMode

    public init(
        testID: String,
        metadata: [String: String] = [:],
        sink: any HeartbeatSink = FileHeartbeatSink(),
        failureMode: HeartbeatFailureMode = .throwError
    ) {
        self.testID = testID
        self.metadata = metadata
        self.sink = sink
        self.failureMode = failureMode
    }

    /// Create a heartbeat and immediately emit a `"start"` event.
    public static func start(
        testID: String,
        metadata: [String: String] = [:],
        sink: any HeartbeatSink = FileHeartbeatSink(),
        failureMode: HeartbeatFailureMode = .throwError
    ) throws -> Heartbeat {
        let hb = Heartbeat(
            testID: testID,
            metadata: metadata,
            sink: sink,
            failureMode: failureMode
        )
        try hb.beat("start")
        return hb
    }

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
            metadata: metadata.merging(extra) { _, new in new }
        )

        switch failureMode {
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
}
