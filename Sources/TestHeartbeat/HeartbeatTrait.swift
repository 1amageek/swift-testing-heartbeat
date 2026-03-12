import Testing

/// A Swift Testing trait that automatically emits heartbeat events
/// around test execution.
///
/// Attach to `@Test` or `@Suite` to get automatic `start`, `done`,
/// `failed`, or `cancelled` lifecycle events without manual calls.
///
/// ```swift
/// @Test("my test", .heartbeat)
/// func myTest() async throws { ... }
///
/// @Test("benchmark", .heartbeat(metadata: ["kind": "benchmark"]))
/// func benchmark() async throws { ... }
/// ```
public struct HeartbeatTrait: TestTrait, SuiteTrait, TestScoping {

    public let testID: String?
    public let metadata: [String: String]
    public let config: HeartbeatConfig

    public var isRecursive: Bool { true }

    public init(
        testID: String? = nil,
        metadata: [String: String] = [:],
        config: HeartbeatConfig = .fromEnvironment()
    ) {
        self.testID = testID
        self.metadata = metadata
        self.config = config
    }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // Skip suite-level scope — only emit heartbeats for individual tests.
        guard !test.isSuite else {
            try await function()
            return
        }

        let id = testID ?? test.name
        let hb = Heartbeat(testID: id, metadata: metadata, config: config)

        do {
            try hb.beat(HeartbeatPhase.start)
            try await function()
            try hb.finish()
        } catch is CancellationError {
            do {
                try hb.cancel()
            } catch {
                // Suppress heartbeat failure to preserve the cancellation.
            }
            throw CancellationError()
        } catch {
            do {
                try hb.fail(metadata: ["error": String(describing: error)])
            } catch {
                // Suppress heartbeat failure to preserve the original test error.
            }
            throw error
        }
    }
}

// MARK: - Trait Factory

extension TestTrait where Self == HeartbeatTrait {

    /// Attach automatic heartbeat lifecycle events to a test.
    public static var heartbeat: HeartbeatTrait {
        HeartbeatTrait()
    }

    /// Attach automatic heartbeat lifecycle events with custom configuration.
    public static func heartbeat(
        testID: String? = nil,
        metadata: [String: String] = [:],
        config: HeartbeatConfig = .fromEnvironment()
    ) -> HeartbeatTrait {
        HeartbeatTrait(testID: testID, metadata: metadata, config: config)
    }
}

extension SuiteTrait where Self == HeartbeatTrait {

    /// Attach automatic heartbeat lifecycle events to all tests in a suite.
    public static var heartbeat: HeartbeatTrait {
        HeartbeatTrait()
    }

    /// Attach automatic heartbeat lifecycle events with custom configuration.
    public static func heartbeat(
        testID: String? = nil,
        metadata: [String: String] = [:],
        config: HeartbeatConfig = .fromEnvironment()
    ) -> HeartbeatTrait {
        HeartbeatTrait(testID: testID, metadata: metadata, config: config)
    }
}
