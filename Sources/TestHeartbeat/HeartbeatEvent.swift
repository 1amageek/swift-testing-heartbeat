import Foundation

/// A single heartbeat event emitted by a test to signal liveness.
public struct HeartbeatEvent: Codable, Sendable {

    public let schemaVersion: Int
    public let testID: String
    public let phase: String
    public let timestamp: Date
    public let monotonicNanoseconds: UInt64
    public let processID: Int32
    public let threadID: UInt64?
    public let metadata: [String: String]

    public init(
        schemaVersion: Int = 1,
        testID: String,
        phase: String,
        timestamp: Date = Date(),
        monotonicNanoseconds: UInt64,
        processID: Int32,
        threadID: UInt64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.testID = testID
        self.phase = phase
        self.timestamp = timestamp
        self.monotonicNanoseconds = monotonicNanoseconds
        self.processID = processID
        self.threadID = threadID
        self.metadata = metadata
    }
}
