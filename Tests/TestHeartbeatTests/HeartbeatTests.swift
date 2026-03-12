import Testing
import Foundation
@testable import TestHeartbeat

// MARK: - Test Sink

/// In-memory sink that records every event for verification.
/// Uses NSLock for thread safety — @unchecked Sendable is required here
/// because Mutex needs macOS 15+ and HeartbeatSink is a sync protocol (actor unusable).
final class RecordingSink: HeartbeatSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [HeartbeatEvent] = []

    var events: [HeartbeatEvent] {
        lock.withLock { _events }
    }

    func write(_ event: HeartbeatEvent) throws {
        lock.withLock { _events.append(event) }
    }
}

/// Sink that always throws to test error handling.
struct FailingSink: HeartbeatSink {
    struct WriteError: Error {}

    func write(_ event: HeartbeatEvent) throws {
        throw WriteError()
    }
}

// MARK: - HeartbeatEvent

@Suite("HeartbeatEvent")
struct HeartbeatEventTests {

    @Test("round-trips through JSON")
    func jsonRoundTrip() throws {
        let event = HeartbeatEvent(
            testID: "roundTrip",
            phase: "setup",
            monotonicNanoseconds: 123_456_789,
            processID: 42,
            metadata: ["key": "value"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HeartbeatEvent.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.testID == "roundTrip")
        #expect(decoded.phase == "setup")
        #expect(decoded.monotonicNanoseconds == 123_456_789)
        #expect(decoded.processID == 42)
        #expect(decoded.threadID == nil)
        #expect(decoded.metadata == ["key": "value"])
    }
}

// MARK: - HeartbeatConfig

@Suite("HeartbeatConfig")
struct HeartbeatConfigTests {

    @Test("reads directory from environment")
    func environmentDirectory() {
        let config = HeartbeatConfig.fromEnvironment(
            environment: ["TEST_HEARTBEAT_DIR": "/custom/dir"]
        )
        #expect(config.directoryURL.path == "/custom/dir")
    }

    @Test("defaults to enabled")
    func defaultEnabled() {
        let config = HeartbeatConfig.fromEnvironment(environment: [:])
        #expect(config.isEnabled)
    }

    @Test("respects disabled flag")
    func disabledByEnvironment() {
        let config = HeartbeatConfig.fromEnvironment(
            environment: ["TEST_HEARTBEAT_ENABLED": "false"]
        )
        #expect(!config.isEnabled)
    }

    @Test("reads failure mode from environment")
    func failureModeFromEnvironment() {
        let config = HeartbeatConfig.fromEnvironment(
            environment: ["TEST_HEARTBEAT_FAILURE_MODE": "ignore"]
        )
        #expect(config.failureMode == .ignore)
    }

    @Test(
        "enabled flag accepts multiple truthy values",
        arguments: ["1", "true", "yes", "TRUE", "Yes"]
    )
    func enabledVariations(value: String) {
        let config = HeartbeatConfig.fromEnvironment(
            environment: ["TEST_HEARTBEAT_ENABLED": value]
        )
        #expect(config.isEnabled)
    }

    @Test(
        "enabled flag rejects non-truthy values",
        arguments: ["0", "false", "no", "whatever"]
    )
    func disabledVariations(value: String) {
        let config = HeartbeatConfig.fromEnvironment(
            environment: ["TEST_HEARTBEAT_ENABLED": value]
        )
        #expect(!config.isEnabled)
    }
}

// MARK: - Heartbeat

@Suite("Heartbeat")
struct HeartbeatTests {

    @Test("start emits a start event")
    func startEvent() throws {
        let sink = RecordingSink()
        _ = try Heartbeat.start(testID: "test1", sink: sink)

        #expect(sink.events.count == 1)
        #expect(sink.events.first?.phase == "start")
        #expect(sink.events.first?.testID == "test1")
    }

    @Test("beat records phase and metadata")
    func beatRecordsPhase() throws {
        let sink = RecordingSink()
        let hb = Heartbeat(testID: "test2", metadata: ["env": "ci"], sink: sink)
        try hb.beat("setup", metadata: ["step": "1"])

        let event = try #require(sink.events.first)
        #expect(event.phase == "setup")
        #expect(event.metadata["env"] == "ci")
        #expect(event.metadata["step"] == "1")
    }

    @Test("metadata merge prefers per-beat values")
    func metadataMerge() throws {
        let sink = RecordingSink()
        let hb = Heartbeat(testID: "test3", metadata: ["key": "base"], sink: sink)
        try hb.beat("phase", metadata: ["key": "override"])

        let event = try #require(sink.events.first)
        #expect(event.metadata["key"] == "override")
    }

    @Test("throwError mode propagates sink errors")
    func throwErrorMode() {
        let hb = Heartbeat(testID: "fail", sink: FailingSink(), failureMode: .throwError)
        #expect(throws: FailingSink.WriteError.self) {
            try hb.beat("boom")
        }
    }

    @Test("ignore mode suppresses sink errors")
    func ignoreMode() throws {
        let hb = Heartbeat(testID: "safe", sink: FailingSink(), failureMode: .ignore)
        try hb.beat("ok")
    }

    @Test("beat populates real PID and monotonic nanoseconds")
    func beatPopulatesSystemValues() throws {
        let sink = RecordingSink()
        let hb = Heartbeat(testID: "sysvals", sink: sink)
        try hb.beat("check")

        let event = try #require(sink.events.first)
        #expect(event.processID == ProcessInfo.processInfo.processIdentifier)
        #expect(event.monotonicNanoseconds > 0)
    }

    @Test("successive beats have non-decreasing monotonic time")
    func monotonicOrder() throws {
        let sink = RecordingSink()
        let hb = Heartbeat(testID: "order", sink: sink)
        try hb.beat("first")
        try hb.beat("second")

        let events = sink.events
        #expect(events.count == 2)
        #expect(events[1].monotonicNanoseconds >= events[0].monotonicNanoseconds)
    }
}

// MARK: - ProgressReporter

@Suite("ProgressReporter")
struct ProgressReporterTests {

    @Test("init emits a start event")
    func initEmitsStart() throws {
        let sink = RecordingSink()
        _ = try ProgressReporter(testID: "prog1", sink: sink)

        #expect(sink.events.count == 1)
        #expect(sink.events.first?.phase == "start")
    }

    @Test("phase emits unconditionally")
    func phaseEmits() throws {
        let sink = RecordingSink()
        var reporter = try ProgressReporter(testID: "prog2", sink: sink)

        try reporter.phase("setup")
        try reporter.phase("teardown")

        #expect(sink.events.count == 3) // start + setup + teardown
    }

    @Test("every throttles by interval")
    func everyThrottles() throws {
        let sink = RecordingSink()
        var reporter = try ProgressReporter(
            testID: "prog3",
            minimumInterval: .seconds(60),
            sink: sink
        )

        // These should all be throttled since 60s hasn't elapsed
        for i in 0..<10 {
            try reporter.every(phase: "iter-\(i)")
        }

        // Only the start event should exist — all iterations throttled
        #expect(sink.events.count == 1)
    }

    @Test("every emits when interval has elapsed")
    func everyEmitsAfterInterval() throws {
        let sink = RecordingSink()
        // Use zero interval so every call emits
        var reporter = try ProgressReporter(
            testID: "prog4",
            minimumInterval: .zero,
            sink: sink
        )

        try reporter.every(phase: "iter-0")
        try reporter.every(phase: "iter-1")

        // start + 2 iterations
        #expect(sink.events.count == 3)
        #expect(sink.events[1].phase == "iter-0")
        #expect(sink.events[2].phase == "iter-1")
    }

    @Test("every accepts explicit interval override")
    func everyExplicitInterval() throws {
        let sink = RecordingSink()
        var reporter = try ProgressReporter(
            testID: "prog5",
            minimumInterval: .seconds(60),
            sink: sink
        )

        // Override with zero — should emit despite long default interval
        try reporter.every(.zero, phase: "override")
        #expect(sink.events.count == 2) // start + override
    }
}

// MARK: - FileHeartbeatSink

@Suite("FileHeartbeatSink")
struct FileHeartbeatSinkTests {

    @Test("writes valid JSON to disk")
    func writesJSON() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-heartbeat-\(UUID().uuidString)")

        let config = HeartbeatConfig(directoryURL: tmpDir)
        let sink = FileHeartbeatSink(config: config)

        let event = HeartbeatEvent(
            testID: "fileTest",
            phase: "check",
            monotonicNanoseconds: 999,
            processID: 1
        )
        try sink.write(event)

        let fileURL = tmpDir.appendingPathComponent("heartbeat-fileTest.json")
        let data = try Data(contentsOf: fileURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HeartbeatEvent.self, from: data)

        #expect(decoded.testID == "fileTest")
        #expect(decoded.phase == "check")

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("skips write when disabled")
    func skipsWhenDisabled() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-heartbeat-\(UUID().uuidString)")

        let config = HeartbeatConfig(directoryURL: tmpDir, isEnabled: false)
        let sink = FileHeartbeatSink(config: config)

        let event = HeartbeatEvent(
            testID: "noop",
            phase: "skip",
            monotonicNanoseconds: 0,
            processID: 1
        )
        try sink.write(event)

        #expect(!FileManager.default.fileExists(atPath: tmpDir.path))
    }

    @Test("sanitizes test ID in filename")
    func sanitizesFilename() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-heartbeat-\(UUID().uuidString)")

        let config = HeartbeatConfig(directoryURL: tmpDir)
        let sink = FileHeartbeatSink(config: config)

        let event = HeartbeatEvent(
            testID: "My/Test::Name<>",
            phase: "check",
            monotonicNanoseconds: 0,
            processID: 1
        )
        try sink.write(event)

        let files = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        let filename = try #require(files.first)
        #expect(filename == "heartbeat-My_Test__Name__.json")

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("second write overwrites with latest event")
    func atomicOverwrite() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-heartbeat-\(UUID().uuidString)")

        let config = HeartbeatConfig(directoryURL: tmpDir)
        let sink = FileHeartbeatSink(config: config)

        let first = HeartbeatEvent(
            testID: "overwrite",
            phase: "old",
            monotonicNanoseconds: 100,
            processID: 1
        )
        try sink.write(first)

        let second = HeartbeatEvent(
            testID: "overwrite",
            phase: "new",
            monotonicNanoseconds: 200,
            processID: 1
        )
        try sink.write(second)

        // Only one file should exist
        let files = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        #expect(files.count == 1)

        // Content should be the latest event
        let fileURL = tmpDir.appendingPathComponent("heartbeat-overwrite.json")
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HeartbeatEvent.self, from: data)
        #expect(decoded.phase == "new")
        #expect(decoded.monotonicNanoseconds == 200)

        try FileManager.default.removeItem(at: tmpDir)
    }
}

// MARK: - TestID

@Suite("TestID")
struct TestIDTests {

    @Test("returns explicit ID when provided")
    func explicitID() {
        let id = TestID.make("custom-id")
        #expect(id == "custom-id")
    }

    @Test("generates ID from call site when no explicit ID")
    func generatedID() {
        let id = TestID.make()
        #expect(id.contains("HeartbeatTests"))
        #expect(id.contains("::"))
    }
}
