import Foundation

/// Controls whether heartbeat write failures crash the test or are silently suppressed.
public enum HeartbeatFailureMode: Sendable {
    /// Propagate errors to the caller. Suitable for development.
    case throwError
    /// Suppress errors so heartbeat failures never break test execution. Suitable for CI.
    case ignore
}

/// Configuration for heartbeat file output.
public struct HeartbeatConfig: Sendable {

    public var directoryURL: URL
    public var filePrefix: String
    public var isEnabled: Bool
    public var includeThreadID: Bool
    public var failureMode: HeartbeatFailureMode

    public init(
        directoryURL: URL,
        filePrefix: String = "heartbeat",
        isEnabled: Bool = true,
        includeThreadID: Bool = false,
        failureMode: HeartbeatFailureMode = .throwError
    ) {
        self.directoryURL = directoryURL
        self.filePrefix = filePrefix
        self.isEnabled = isEnabled
        self.includeThreadID = includeThreadID
        self.failureMode = failureMode
    }

    /// Build configuration from environment variables.
    ///
    /// - `TEST_HEARTBEAT_DIR`: Output directory (default: `/tmp/test-heartbeat`)
    /// - `TEST_HEARTBEAT_ENABLED`: `1`/`true`/`yes` to enable (default: enabled)
    /// - `TEST_HEARTBEAT_FAILURE_MODE`: `ignore` or `throw` (default: `throw`)
    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HeartbeatConfig {
        let dir = environment["TEST_HEARTBEAT_DIR"] ?? "/tmp/test-heartbeat"

        let enabled = environment["TEST_HEARTBEAT_ENABLED"].map {
            ["1", "true", "yes"].contains($0.lowercased())
        } ?? true

        let failureMode: HeartbeatFailureMode = {
            guard let raw = environment["TEST_HEARTBEAT_FAILURE_MODE"] else { return .throwError }
            return raw.lowercased() == "ignore" ? .ignore : .throwError
        }()

        return HeartbeatConfig(
            directoryURL: URL(fileURLWithPath: dir),
            isEnabled: enabled,
            failureMode: failureMode
        )
    }
}
