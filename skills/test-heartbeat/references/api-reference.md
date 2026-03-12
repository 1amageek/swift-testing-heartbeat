# TestHeartbeat API Reference

## HeartbeatTrait

`TestTrait & SuiteTrait & TestScoping` — automatic lifecycle events around test execution.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `testID` | `String?` | Override test ID (default: `test.name`) |
| `metadata` | `[String: String]` | Extra metadata attached to all events |
| `config` | `HeartbeatConfig` | Heartbeat configuration |
| `isRecursive` | `Bool` | Always `true` — propagates to nested suites |

### Factory Methods

```swift
// Default
.heartbeat

// With options
.heartbeat(testID: "custom-id", metadata: ["key": "value"], config: config)
```

### Lifecycle Behavior

| Outcome | Phase emitted |
|---------|---------------|
| Test starts | `start` |
| Test succeeds | `done` |
| Test throws error | `failed` (with `error` in metadata) |
| Test cancelled | `cancelled` |

Suite-level scope is skipped — heartbeats are emitted only for individual test cases.

---

## Heartbeat

`struct Heartbeat: Sendable` — manual liveness-signal API.

### Initializers

```swift
// Create without emitting
Heartbeat(testID: String, metadata: [:], config: .fromEnvironment(), sink: nil)

// Create and emit start immediately
static func start(testID:metadata:config:sink:) throws -> Heartbeat
```

### Methods

| Method | Description |
|--------|-------------|
| `beat(_:metadata:)` | Emit event for named phase |
| `finish(metadata:)` | Emit `done` event |
| `fail(metadata:)` | Emit `failed` event |
| `cancel(metadata:)` | Emit `cancelled` event |
| `withPhase(_:metadata:operation:)` | Scoped: emits `name`, then `name:done` or `name:failed` |

### Error Handling

- `failureMode: .throwError` — errors propagate to caller (default, for development)
- `failureMode: .ignore` — errors suppressed silently (for CI)
- In `withPhase`, heartbeat errors in the failure path are always suppressed to preserve the original test error

---

## ProgressReporter

`struct ProgressReporter: Sendable` — rate-limited reporting for loops.

### Initializer

```swift
try ProgressReporter(
    testID: String,
    metadata: [:],
    minimumInterval: .seconds(1),
    config: .fromEnvironment(),
    sink: nil
)
```

Automatically calls `Heartbeat.start()` on init.

### Methods

| Method | Description |
|--------|-------------|
| `phase(_:metadata:)` | Emit unconditionally, reset timer |
| `every(_:phase:metadata:)` | Emit only if interval elapsed (default: `minimumInterval`) |
| `finish(metadata:)` | Emit `done` |
| `fail(metadata:)` | Emit `failed` |
| `withPhase(_:metadata:operation:)` | Scoped phase with auto done/failed |

### Important

`ProgressReporter` is a value type with mutable state. Use `mutating` methods (`phase`, `every`, `withPhase`). Do not share across concurrent tasks.

---

## HeartbeatConfig

`struct HeartbeatConfig: Sendable`

### Properties

| Property | Type | Default |
|----------|------|---------|
| `directoryURL` | `URL` | `/tmp/test-heartbeat` |
| `filePrefix` | `String` | `"heartbeat"` |
| `isEnabled` | `Bool` | `true` |
| `includeThreadID` | `Bool` | `false` |
| `failureMode` | `HeartbeatFailureMode` | `.throwError` |

### Environment Variables

| Variable | Maps to |
|----------|---------|
| `TEST_HEARTBEAT_DIR` | `directoryURL` |
| `TEST_HEARTBEAT_ENABLED` | `isEnabled` (`1`/`true`/`yes`) |
| `TEST_HEARTBEAT_FAILURE_MODE` | `failureMode` (`throw`/`ignore`) |

---

## HeartbeatEvent

`struct HeartbeatEvent: Codable, Sendable`

| Field | Type | Description |
|-------|------|-------------|
| `schemaVersion` | `Int` | Always `1` |
| `testID` | `String` | Test identifier |
| `phase` | `String` | Phase name |
| `timestamp` | `Date` | Wall clock (ISO 8601) |
| `monotonicNanoseconds` | `UInt64` | Monotonic uptime nanos — use this for staleness |
| `processID` | `Int32` | Process PID |
| `threadID` | `UInt64?` | Optional thread ID |
| `metadata` | `[String: String]` | Custom key-value pairs |

---

## HeartbeatPhase

Well-known phase constants:

| Constant | Value |
|----------|-------|
| `.start` | `"start"` |
| `.progress` | `"progress"` |
| `.done` | `"done"` |
| `.failed` | `"failed"` |
| `.cancelled` | `"cancelled"` |

---

## HeartbeatSink

```swift
public protocol HeartbeatSink: Sendable {
    func write(_ event: HeartbeatEvent) throws
}
```

Default implementation: `FileHeartbeatSink` — atomic JSON file write per test ID.

---

## FileHeartbeatSink

`struct FileHeartbeatSink: HeartbeatSink, Sendable`

- Creates directory on first write
- Filename: `{filePrefix}-{sanitized_testID}.json`
- Sanitization: non-alphanumeric chars (except `-`, `_`, `.`) replaced with `_`
- Writes are atomic (`.atomic` option)

---

## TestID

Helper for generating stable test IDs:

```swift
TestID.make()                    // "{fileID}::{function}::L{line}"
TestID.make("explicit-id")      // "explicit-id"
```
