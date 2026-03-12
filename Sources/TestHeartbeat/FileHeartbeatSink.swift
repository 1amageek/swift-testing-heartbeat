import Foundation

/// Writes heartbeat events as JSON files, one file per test.
///
/// Each call to `write` atomically replaces the file for the given `testID`,
/// so the watchdog always reads a complete, valid JSON document.
public struct FileHeartbeatSink: HeartbeatSink, Sendable {

    private let config: HeartbeatConfig

    public init(config: HeartbeatConfig = .fromEnvironment()) {
        self.config = config
    }

    public func write(_ event: HeartbeatEvent) throws {
        guard config.isEnabled else { return }

        try FileManager.default.createDirectory(
            at: config.directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let fileURL = config.directoryURL.appendingPathComponent(filename(for: event.testID))
        let data = try encoder.encode(event)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Private

    private func filename(for testID: String) -> String {
        "\(config.filePrefix)-\(sanitize(testID)).json"
    }

    private func sanitize(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".":
                return Character(scalar)
            default:
                return Character("_")
            }
        }.reduce(into: "") { $0.append($1) }
    }
}
