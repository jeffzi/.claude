---
name: code-swift
description: >
  Use when writing any Swift code, regardless of perceived simplicity or prototyping context.
  Use when you think "just a quick script" or "concurrency is overkill" — these are symptoms
  this skill applies. Also use when encountering Swift 6.x strict concurrency errors, Sendable
  warnings, or actor isolation issues. Applies to any *.swift file. For test files (*Tests.swift),
  also load test-swift. Not for Swift test patterns — use test-swift for that.
paths: "**/*.swift"
user-invocable: false
model: sonnet
effort: medium
---

# Swift — Production-Quality Code

**Core principle:** Swift 6.2 changed the concurrency default — code runs on the caller's executor
by default; opt into concurrency with `@concurrent`. Use `Mutex` for thread-safe state, not
`@unchecked Sendable`. Check `Package.swift` for the Swift tools version and language mode before
writing concurrency code.

## Mandatory Rules

### Swift 6.2 Concurrency: Caller Inheritance by Default (SE-0461)

Nonisolated async functions now **inherit the caller's execution context** instead of hopping to the
global concurrent pool. CPU-intensive work called from `@MainActor` context **blocks the main
thread** unless explicitly opted out with `@concurrent`:

```swift
// ❌ DANGEROUS in 6.2: blocks MainActor if called from MainActor context
nonisolated func processImages() async -> [Image] {
    // CPU-intensive work runs on caller's executor — may be MainActor
}

// ✅ CORRECT: explicitly opt into concurrent execution
@concurrent
func processImages() async -> [Image] {
    // Guaranteed to run on the global concurrent executor
}
```

**`defaultIsolation MainActor` mode** (SE-0466): new Xcode 26 projects default all types and
functions to `@MainActor` unless marked otherwise. Check `Package.swift` for
`.defaultIsolation(MainActor.self)` in swiftSettings. Library authors must NOT enable this — it
forces MainActor isolation on all public API.

### Use Mutex, Not @unchecked Sendable

The `Synchronization` framework (Swift 6.0+) provides `Mutex` for genuinely thread-safe `Sendable`
classes. `@unchecked Sendable` defeats the purpose of strict concurrency — use it only for wrapping
C/ObjC types with documented thread safety:

```swift
// ❌ BAD: @unchecked Sendable hides real data races
final class Cache: @unchecked Sendable {
    private var storage: [String: Data] = [:]  // unprotected!
}

// ✅ GOOD: Mutex provides real thread safety + genuine Sendable
import Synchronization

final class Cache: Sendable {
    let storage = Mutex<[String: Data]>([:])
    func get(_ key: String) -> Data? {
        storage.withLock { $0[key] }
    }
}
```

**When `@unchecked Sendable` is justified:** immutable-after-init classes, types wrapping C/ObjC
APIs with documented thread safety, or types already protected by a lock where Mutex can't be used
(e.g., NSLock interop). Always document the invariant.

### No Obvious Comments

Only explain **WHY** for non-obvious decisions. Never explain what code does.

```swift
// ❌ FORBIDDEN
var total = 0  // Initialize total to zero
for item in items { total += item }  // Add each item

// ✅ Self-documenting
let total = items.reduce(0, +)
```

## Concurrency Patterns

### Actor Reentrancy — Never Split Check-and-Act Across Suspension

Actors are reentrant: when an actor method suspends at `await`, other work can execute on that actor
before resumption. Never guard a condition then mutate across a suspension point:

```swift
// ❌ State may change between guard and mutation
actor Account {
    var balance: Double = 1000
    func transfer(amount: Double, to other: Account) async {
        guard balance >= amount else { return }
        await other.deposit(amount)  // ⚠️ balance can change here
        balance -= amount            // may overdraw
    }
}

// ✅ Debit first in one atomic step (no suspension between check and mutation)
actor Account {
    var balance: Double = 1000
    func transfer(amount: Double, to other: Account) async {
        guard balance >= amount else { return }
        balance -= amount            // atomic with guard — no suspension
        await other.deposit(amount)
    }
}
```

### withTaskCancellationHandler — Use Mutex for the Race Condition

The `onCancel` handler fires **immediately on any thread**, creating a race if you need to cancel a
resource created inside the operation:

```swift
// ✅ Use Mutex to synchronize
import Synchronization

let holder = Mutex<URLSessionDataTask?>(nil)
return try await withTaskCancellationHandler {
    let task = session.dataTask(with: url) { ... }
    holder.withLock { $0 = task }
    task.resume()
} onCancel: {
    holder.withLock { $0?.cancel() }
}
```

### Task.immediate — Reduce Scheduling Latency (SE-0472)

`Task.immediate` starts executing synchronously if already on the correct executor, avoiding
queue-then-dequeue overhead of standard `Task { }`:

```swift
Task.immediate { @MainActor in
    // Starts running NOW if already on MainActor
    // Falls back to standard scheduling if not
}
```

Use in performance-sensitive UI code where `Task { }` scheduling causes visible lag.

## Quick Reference

### Concurrency Decision Framework

| Feature               | `async let`           | `TaskGroup`        | `Task { }` | `Task.detached` |
| --------------------- | --------------------- | ------------------ | ---------- | --------------- |
| Task count            | Fixed at compile time | Dynamic            | Single     | Single          |
| Cancellation          | Auto on scope exit    | Auto on scope exit | Manual     | Manual          |
| Actor inheritance     | Yes                   | Yes                | Yes        | **No**          |
| TaskLocal propagation | Yes                   | Yes                | Yes        | **No**          |
| Structured            | Yes                   | Yes                | No         | No              |

**Avoid `Task.detached`** unless you explicitly need to escape the parent's actor context and
TaskLocal values.

### TaskGroup Bounded Concurrency

```swift
await withTaskGroup(of: Void.self) { group in
    let maxConcurrent = 4
    for (i, url) in urls.enumerated() {
        if i >= maxConcurrent { await group.next() }  // backpressure
        group.addTask { await process(url) }
    }
}
```

### InlineArray and Span (Swift 6.2)

**InlineArray** — fixed-size, stack-allocated, no heap overhead:

```swift
var buffer: [50 of String]  // sugar syntax — NOT InlineArray<50, String>
```

**Span** — safe alternative to `UnsafeBufferPointer` with compile-time lifetime enforcement:

```swift
let array = [1, 2, 3]
let span = array.span  // borrows array's memory — cannot outlive array

// ❌ Cannot return a span — it borrows local memory
// ❌ Cannot capture in escaping closures
```

### some vs any Escalation

Escalate only as needed: **concrete type** (best) -> **`some Protocol`** (opaque, static dispatch)
-> **`any Protocol`** (existential, dynamic dispatch, 7-67% slower).

```swift
// ✅ BEST: concrete when possible
func makeCircle() -> Circle { Circle(radius: 5) }

// ✅ GOOD: opaque — static dispatch, full optimization
func makeShape() -> some Shape { Circle(radius: 5) }

// ✅ OK: existential — only for heterogeneous collections or runtime polymorphism
func shapes() -> [any Shape] { [Circle(radius: 5), Square(side: 3)] }
```

### Typed Throws Composition Gotcha

When a `do` block has `try` calls throwing different typed errors, the catch error type collapses to
`any Error`:

```swift
do {
    try functionA()  // throws(ErrorA)
    try functionB()  // throws(ErrorB)
} catch {
    // error is `any Error`, NOT ErrorA | ErrorB
}
```

Use typed throws for **leaf functions** with well-defined failure modes. Use untyped `throws` for
orchestration layers.

## Pitfalls

| Trap                                              | Instead                                                               |
| ------------------------------------------------- | --------------------------------------------------------------------- |
| Nonisolated async = background thread (pre-6.2)   | In 6.2, inherits caller's executor — use `@concurrent` for background |
| `@unchecked Sendable` for mutable state           | `Mutex` from `Synchronization` framework                              |
| `Task { try await op() }` fire-and-forget         | Error silently swallowed — handle in `do/catch` or store handle       |
| Guard-then-mutate across `await` in actors        | Debit first atomically, then `await`                                  |
| Multiple consumers of `AsyncStream`               | Single-consumer only — runtime crash, not compile error               |
| `withTaskCancellationHandler` capturing task      | `onCancel` fires on any thread — synchronize with `Mutex`             |
| `any Protocol` when `some` suffices               | 7-67% overhead — escalate concrete -> some -> any                     |
| Protocol method in extension only                 | Static dispatch through existential — declare in protocol body        |
| `.reduce(initial, +)` with value-type accumulator | `.reduce(into:)` — avoids O(n^2) CoW copying                          |
| `.sorted().first` / `.filter { }.count > 0`       | `.min()` / `.contains(where:)` — O(n) vs O(n log n)                   |
| `InlineArray<50, String>`                         | Sugar: `[50 of String]`                                               |
| Property wrappers in Sendable classes             | Known conflict — use `@unchecked Sendable` on container or actor      |

## macOS Development

For macOS-specific patterns (window management, menu system, AppKit-SwiftUI interop, sandboxing,
Liquid Glass), read `references/macos-patterns.md`.

## Rationalizations That Mean Failure

| Excuse                                    | Reality                                                               |
| ----------------------------------------- | --------------------------------------------------------------------- |
| "Nonisolated means it runs off MainActor" | Changed in 6.2 — now inherits caller's executor                       |
| "@unchecked Sendable is fine with a lock" | Use Mutex — compiler-verified, not trust-based                        |
| "Task fire-and-forget is convenient"      | Errors silently swallowed. Handle them.                               |
| "Just a quick actor wrapper"              | Actors serialize ALL work, including independent ops                  |
| "any Protocol is flexible"                | Unnecessary overhead — use some unless you need heterogeneous storage |
| "I'll add @concurrent later"              | CPU work blocks MainActor NOW. Add it first.                          |

## SwiftLint Rules for Swift 6

Enable these opt-in rules to catch real bugs:

```yaml
opt_in_rules:
  - unhandled_throwing_task # CRITICAL: catches silently swallowed errors
  - async_without_await # flags unnecessary async
  - first_where # .filter{}.first -> .first(where:)
  - sorted_first_last # .sorted().first -> .min()
  - reduce_into # .reduce() -> .reduce(into:)
  - empty_count # .count == 0 -> .isEmpty
  - force_unwrapping
  - private_swiftui_state
analyzer_rules:
  - unused_declaration
  - unused_import
  - capture_variable # catches implicit retain cycles
```

## Verification

**MANDATORY before completing any task:**

```bash
swift build              # Compile check (strict concurrency if enabled)
swiftlint lint           # If .swiftlint.yml exists
swift test               # If tests exist — always run separately
```

**Task is NOT complete until all pass.**
