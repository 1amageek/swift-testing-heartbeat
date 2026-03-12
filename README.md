# TestHeartbeat

A liveness-signal library for Swift tests. Instead of relying on a fixed timeout to detect hung tests, TestHeartbeat lets tests **emit heartbeat events** at phase boundaries. An external watchdog monitors elapsed time since the last heartbeat — if progress stops, the test is hung.

A 5-minute test that reports progress every second is healthy.
A 10-second test that goes silent is hung.

## Why not `.timeLimit`?

`.timeLimit` kills a test after a fixed duration, regardless of whether it's making progress. This forces you to guess a worst-case budget. Too short and legitimate slow runs get killed; too long and a truly hung test wastes CI time.

TestHeartbeat measures **time without progress**, not total elapsed time. The watchdog only intervenes when a test stops reporting.

## Architecture

```
┌──────────────┐      JSON files      ┌──────────────┐
│  Test Code   │ ──── heartbeat ────▶ │   Watchdog   │
│  (Heartbeat) │      per testID      │  (external)  │
└──────────────┘                      └──────┬───────┘
                                             │
                                      monitors gap
                                      between beats
                                             │
                                      ┌──────▼───────┐
                                      │ sample / kill │
                                      └──────────────┘
```

| Component | Responsibility |
|---|---|
| **Heartbeat** | Emit liveness signals at phase boundaries |
| **ProgressReporter** | Rate-limited signals for tight loops |
| **HeartbeatTrait** | Auto-emit start/done/failed for Swift Testing |
| **FileHeartbeatSink** | Atomic JSON output the watchdog reads |
| **Watchdog** (external) | Detect silence, `sample`, kill |

TestHeartbeat handles **signal emission only**. Detection and response are the watchdog's job.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-testing-heartbeat.git", from: "0.1.0")
]
```

Then add `"TestHeartbeat"` to your test target's dependencies.

## Usage

### Trait (recommended)

The simplest way. Attach `.heartbeat` to automatically emit `start`, `done`, `failed`, or `cancelled`:

```swift
import Testing
import TestHeartbeat

@Test("syncs remote state", .heartbeat)
func syncsRemoteState() async throws {
    try await launchServer()
    try await performRequest()
    #expect(result.isValid)
}
```

With metadata:

```swift
@Test("vector search", .heartbeat(metadata: ["kind": "benchmark"]))
func vectorSearch() async throws { ... }
```

Applied to a suite:

```swift
@Suite(.heartbeat)
struct IntegrationTests {
    @Test func serverSync() async throws { ... }
    @Test func clientAuth() async throws { ... }
}
```

### Manual Heartbeat

For explicit control over phase boundaries:

```swift
let hb = try Heartbeat.start(testID: "myTest")
try hb.beat("setup")
try hb.beat("execute")
try hb.finish()
```

With scoped phases that auto-emit start/done/failed:

```swift
let hb = try Heartbeat.start(testID: "myTest")

try await hb.withPhase("download") {
    try await fetchData()
}

try await hb.withPhase("process") {
    try await transform(data)
}

try hb.finish()
```

### ProgressReporter

For long-running loops where you don't want to flood the sink:

```swift
var progress = try ProgressReporter(testID: "benchmark", minimumInterval: .seconds(1))

try progress.phase("warmup")
for i in 0..<100 {
    try await warmup(i)
    try progress.every(phase: "warmup-\(i)")
}

try progress.phase("measure")
for i in 0..<10_000 {
    try await measure(i)
    try progress.every(.milliseconds(500), phase: "measure-\(i)")
}

try progress.finish()
```

`every` only emits if enough time has passed. `phase` always emits.

## Lifecycle Phases

Well-known phase names defined in `HeartbeatPhase`:

| Phase | Meaning | Emitted by |
|---|---|---|
| `start` | Test began | `Heartbeat.start()`, `HeartbeatTrait` |
| `progress` | Still running (convention) | User code |
| `done` | Completed successfully | `finish()`, `HeartbeatTrait` |
| `failed` | Error occurred | `fail()`, `HeartbeatTrait` |
| `cancelled` | Task was cancelled | `cancel()`, `HeartbeatTrait` |

Custom phase strings are allowed via `beat(_:)`. The watchdog only needs to track the timestamp gap — it doesn't need to understand every phase name.

## Configuration

### Environment Variables

| Variable | Values | Default |
|---|---|---|
| `TEST_HEARTBEAT_DIR` | Directory path | `/tmp/test-heartbeat` |
| `TEST_HEARTBEAT_ENABLED` | `1` / `true` / `yes` | enabled |
| `TEST_HEARTBEAT_FAILURE_MODE` | `ignore` / `throw` | `throw` |

### Programmatic

```swift
let config = HeartbeatConfig(
    directoryURL: URL(fileURLWithPath: "/custom/path"),
    isEnabled: true,
    includeThreadID: true,
    failureMode: .ignore  // suppress heartbeat errors on CI
)

let hb = Heartbeat(testID: "myTest", config: config)
```

### Failure Mode

- `.throwError` — Heartbeat write errors propagate to the test. Good for development.
- `.ignore` — Heartbeat write errors are silently suppressed. Good for CI where the heartbeat infrastructure shouldn't break tests.

## Output Format

Each test gets one JSON file, atomically replaced on every beat:

```
/tmp/test-heartbeat/heartbeat-vectorSearch.json
```

```json
{
  "metadata": {
    "kind": "benchmark"
  },
  "monotonicNanoseconds": 1823081231231,
  "phase": "measure-421",
  "processID": 91827,
  "schemaVersion": 1,
  "testID": "vectorSearch",
  "threadID": null,
  "timestamp": "2026-03-12T09:41:12Z"
}
```

The watchdog reads `monotonicNanoseconds` and `phase`. If the file hasn't been updated within the threshold, the test is hung.

## Custom Sink

Implement `HeartbeatSink` to direct events to stdout, a socket, os_log, or anything else:

```swift
struct StdoutSink: HeartbeatSink {
    func write(_ event: HeartbeatEvent) throws {
        let data = try JSONEncoder().encode(event)
        print(String(data: data, encoding: .utf8)!)
    }
}

let hb = Heartbeat(testID: "myTest", sink: StdoutSink())
```

## Requirements

- Swift 6.2+
- macOS 13+

## License

MIT
