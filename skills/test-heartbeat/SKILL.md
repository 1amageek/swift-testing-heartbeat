---
name: test-heartbeat
description: Add heartbeat-based hang detection to Swift tests using TestHeartbeat library. Use when writing or reviewing Swift tests that need hang detection, liveness monitoring, or progress reporting — especially for integration tests, benchmarks, or long-running test suites. Supports automatic lifecycle via .heartbeat trait, manual Heartbeat API, and rate-limited ProgressReporter.
license: MIT
---

# TestHeartbeat

Liveness-signal library for Swift Testing. Emits heartbeat events to `/tmp/test-heartbeat/` so an external watchdog can detect hung tests by monitoring "no-progress time" rather than total execution time.

## When to Use

- **Integration tests** that perform I/O or network calls
- **Benchmark tests** with long iteration loops
- **Any test suite** where hangs have occurred or are likely (AsyncStream, continuations, actor deadlocks)
- Do NOT use for fast unit tests — the overhead is unnecessary

## Quick Start

### 1. Add Dependency

```swift
// Package.swift
.package(url: "https://github.com/1amageek/swift-testing-heartbeat", from: "0.1.0")

// Target dependency
.testTarget(name: "MyTests", dependencies: ["TestHeartbeat"])
```

### 2. Choose Your API

| API | Use Case |
|-----|----------|
| `.heartbeat` trait | Automatic lifecycle — attach to `@Test` or `@Suite` |
| `Heartbeat` | Manual phase boundaries within a test |
| `ProgressReporter` | Rate-limited reporting inside tight loops |

## Instructions

### Automatic: `.heartbeat` Trait (Recommended)

Attach `.heartbeat` to `@Test` or `@Suite`. It automatically emits `start`, `done`, `failed`, or `cancelled` events. When attached to `@Suite`, it applies recursively to all child tests.

```swift
import Testing
import TestHeartbeat

@Test("integration test", .tags(.integration), .heartbeat)
func integrationTest() async throws {
    // start emitted automatically
    try await performWork()
    // done emitted automatically (or failed/cancelled on error)
}

@Suite(.heartbeat, .serialized)
struct BenchmarkTests {
    // All tests in this suite get automatic heartbeat
}
```

With metadata for watchdog context:

```swift
@Test(.heartbeat(metadata: ["kind": "benchmark", "timeout": "30"]))
func heavyBenchmark() async throws { ... }
```

### Manual: `Heartbeat` API

Use when you need explicit phase boundaries within a single test.

```swift
@Test func complexPipeline() async throws {
    let hb = try Heartbeat.start(testID: "complexPipeline")

    try await hb.withPhase("setup") {
        try await prepareDatabase()
    }

    try await hb.withPhase("execute") {
        try await runPipeline()
    }

    try await hb.withPhase("verify") {
        try await checkResults()
    }

    try hb.finish()
}
```

`withPhase("name")` emits `name` on entry, `name:done` on success, `name:failed` on error.

For simple cases without scoping:

```swift
let hb = try Heartbeat.start(testID: "myTest")
try hb.beat("step-1")
try await doWork()
try hb.beat("step-2")
try await doMoreWork()
try hb.finish()
```

### Rate-Limited: `ProgressReporter`

Use inside tight loops to avoid flooding the sink.

```swift
@Test func largeBenchmark() async throws {
    var progress = try ProgressReporter(
        testID: "largeBenchmark",
        minimumInterval: .seconds(1)
    )

    for i in 0..<100_000 {
        try await processItem(i)
        try progress.every(phase: "iteration-\(i)")
    }

    try progress.finish()
}
```

- `phase(_:)` — emits unconditionally
- `every(_:phase:)` — emits only if `minimumInterval` has elapsed since last beat
- `withPhase(_:)` — scoped phase with automatic done/failed

### Configuration

Environment variables (no code changes needed):

| Variable | Default | Purpose |
|----------|---------|---------|
| `TEST_HEARTBEAT_DIR` | `/tmp/test-heartbeat` | Output directory |
| `TEST_HEARTBEAT_ENABLED` | `true` | Enable/disable |
| `TEST_HEARTBEAT_FAILURE_MODE` | `throw` | `throw` for dev, `ignore` for CI |

Set `ignore` in CI to prevent heartbeat I/O errors from breaking tests:

```bash
TEST_HEARTBEAT_FAILURE_MODE=ignore xcodebuild test ...
```

Programmatic configuration:

```swift
let config = HeartbeatConfig(
    directoryURL: URL(fileURLWithPath: "/custom/path"),
    isEnabled: true,
    includeThreadID: true,
    failureMode: .ignore
)

@Test(.heartbeat(config: config))
func myTest() async throws { ... }
```

### Custom Sink

Implement `HeartbeatSink` to redirect output (stdout, socket, os_log, etc.):

```swift
struct StdoutSink: HeartbeatSink {
    func write(_ event: HeartbeatEvent) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        print(String(data: data, encoding: .utf8)!)
    }
}

let hb = Heartbeat(testID: "myTest", sink: StdoutSink())
```

## Watchdog Integration

The watchdog monitors `/tmp/test-heartbeat/` and detects hangs by checking `monotonicNanoseconds` staleness:

1. Scan JSON files in `TEST_HEARTBEAT_DIR`
2. For each file, compare `monotonicNanoseconds` against current time
3. If delta exceeds threshold (e.g., 10s for integration, 15s for benchmark) — flag as hung
4. On hang detection, run `sample <processID>` to capture stack trace

Heartbeat JSON file format:

```json
{
    "schemaVersion": 1,
    "testID": "myTest",
    "phase": "execute",
    "timestamp": "2025-03-12T10:00:00Z",
    "monotonicNanoseconds": 123456789,
    "processID": 12345,
    "metadata": {}
}
```

## Common Issues

### Heartbeat files not appearing

1. Check `TEST_HEARTBEAT_ENABLED` is not set to `false`
2. Verify the output directory is writable
3. Ensure the test actually runs (not filtered out)

### Tests fail with heartbeat I/O errors

Set `TEST_HEARTBEAT_FAILURE_MODE=ignore` or use `.ignore` failure mode in `HeartbeatConfig`.

### ProgressReporter not emitting

`every()` is rate-limited by `minimumInterval` (default 1s). Use `phase()` for unconditional emission, or reduce the interval.

### Combining with `.timeLimit`

`.heartbeat` and `.timeLimit(.minutes(N))` complement each other. `.timeLimit` is the final safety net; heartbeat provides granular "no-progress" detection. Use both:

```swift
@Test(.heartbeat, .timeLimit(.minutes(5)))
func longRunningTest() async throws { ... }
```

For detailed API reference, consult `references/api-reference.md`.
