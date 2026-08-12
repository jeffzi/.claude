---
name: test-swift
description: >
  Use when writing Swift tests with Swift Testing or XCTest. Apply for parameterized tests,
  async test flakiness, Sendable mock issues, confirmation() usage, strict concurrency test
  errors, actor-isolated testing, exit tests, or any *Tests.swift files. Not for production
  Swift code patterns — use code-swift for that.
user-invocable: false
---

# Swift Testing

**This skill extends `Skill(test-core)`.** `test-core` is the primary entry point; this skill is
loaded by `test-core` based on the rules-file dispatch table.

**Load `Skill(code-swift)` and apply its rules.**

## Swift Testing vs XCTest Decision

| Swift Testing                   | XCTest only                                      |
| ------------------------------- | ------------------------------------------------ |
| All new unit tests              | UI automation (`XCUIApplication`)                |
| Business logic, async/await     | Performance tests (`XCTMetric`)                  |
| Parameterized tests             | Objective-C tests                                |
| Cross-platform (Linux, Windows) | `addTeardownBlock` (no Swift Testing equivalent) |

Both coexist in the same file. **Never mix assertions** — no `XCTAssert` in `@Test` functions, no
`#expect` in `XCTestCase` methods.

## Mandatory Rules

### 1. Concrete Expected Values in Parameterized Tests

**Never compute expected values from the same logic as the implementation.** Use literal values:

```swift
// BAD: test logic mirrors implementation — won't catch bugs
@Test(arguments: Day.allCases)
func greeting(day: Day) {
    #expect(greeting(of: day) == "Happy \(day.rawValue)!")
}

// GOOD: concrete expected values
@Test(arguments: [
    (Day.monday,  "Happy Monday!"),
    (Day.tuesday, "Happy Tuesday!"),
])
func greeting(day: Day, expected: String) {
    #expect(greeting(of: day) == expected)
}
```

### 2. Never Use zip() for Parameterized Arguments

`zip()` silently drops test cases when arrays have different lengths:

```swift
// BAD: if Ingredient has 5 cases but Dish has 4,
// the 5th ingredient is silently never tested
@Test(arguments: zip(Ingredient.allCases, Dish.allCases))
func cook(_ ingredient: Ingredient, into dish: Dish) { ... }

// GOOD: explicit array of tuples — nothing silently dropped
@Test(arguments: [
    (Ingredient.rice, Dish.onigiri),
    (Ingredient.egg, Dish.omelette),
])
func cook(_ ingredient: Ingredient, into dish: Dish) { ... }
```

### 3. `.serialized` for Shared State

Parameterized tests run in parallel by default. Use `.serialized` when they share state:

```swift
// On a single test
@Test(.serialized, arguments: migrations)
func applyMigration(_ migration: Migration) async throws { ... }

// On a suite — all tests and nested suites run serially
@Suite(.serialized)
struct DatabaseTests { ... }
```

### 4. TestScoping for Setup/Teardown

Use `init`/`deinit` for simple cases. For shared setup across suites, use **`TestTrait` +
`TestScoping`** (NOT `CustomExecutionTrait` — that doesn't exist):

```swift
struct WithTestDatabase: TestTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: () async throws -> Void
    ) async throws {
        let db = DatabaseContext(connectionString: "memory://test")
        try await DatabaseContext.$current.withValue(db) {
            try await function()
        }
    }
}

extension Trait where Self == WithTestDatabase {
    static var withTestDatabase: Self { .init() }
}

@Suite(.withTestDatabase)
struct UserRepositoryTests {
    @Test func insertUser() { ... }
}
```

### 5. Sendable Mocks — Actor or Mutex, Not @unchecked

**Actor-based (preferred)** — automatically Sendable, all access is `await`:

```swift
actor MockNetworkService: NetworkServiceProtocol {
    private var responses: [String: Data] = [:]
    private(set) var callCount = 0
    func fetch(from endpoint: String) async -> Data {
        callCount += 1
        return responses[endpoint] ?? Data()
    }
}
```

**Mutex-based** — synchronous reads, genuine `Sendable` (Mutex itself is Sendable):

```swift
import Synchronization

final class MockCache: Sendable {
    let storage = Mutex<[String: Data]>([:])
    func get(_ key: String) -> Data? { storage.withLock { $0[key] } }
    func set(_ key: String, _ data: Data) { storage.withLock { $0[key] = data } }
}
```

`@unchecked Sendable` is last resort — only in test targets where mocks are sequential.

### 6. @MainActor XCTestCase Needs Sendable

```swift
// BAD: missing Sendable — "sending main actor-isolated value" warnings
@MainActor
final class ViewModelTests: XCTestCase { ... }

// GOOD: add Sendable conformance
@MainActor
final class ViewModelTests: XCTestCase, Sendable {
    override func setUp() async throws {  // must be async throws
        try await super.setUp()
    }
}
```

### 7. Closure-Based Doubles Over Protocol Mocks

Prefer **closure-based test doubles** over protocol explosion:

```swift
class ViewModel {
    private let loadProduct: () async throws -> Product
    init(loadProduct: @escaping () async throws -> Product) {
        self.loadProduct = loadProduct
    }
}

// Test — no protocols, no mock types
@Test func reload() async throws {
    let vm = ViewModel(loadProduct: { Product(name: "Test") })
    try await vm.reload()
    #expect(vm.title == "Test")
}
```

## Quick Reference

### Migration Mapping

| XCTest                 | Swift Testing                          |
| ---------------------- | -------------------------------------- |
| `XCTestCase` subclass  | `@Suite` struct                        |
| `func testXxx()`       | `@Test func xxx()`                     |
| 40+ `XCTAssert*`       | `#expect()` (continues on failure)     |
| `XCTUnwrap`            | `try #require(optionalValue)`          |
| `XCTFail()`            | `Issue.record("message")`              |
| `setUp()/tearDown()`   | `init`/`deinit` or `TestScoping` trait |
| `XCTAssertThrowsError` | `#expect(throws: ErrorType.self) { }`  |

### Error Testing

**Inspect thrown errors** (Swift 6.1+) — `#expect(throws:)` returns the error:

```swift
let error = #expect(throws: GameError.self) {
    try playGame(at: 22)
}
#expect(error == .disallowedTime)

// When test can't continue without the error, use #require
let error = try #require(throws: NetworkError.self) {
    try fetchData(from: badURL)
}
#expect(error.statusCode == 404)
```

### Exit Tests (Swift 6.2, Experimental)

Test `fatalError`, `preconditionFailure`, and crashes — spawns a child process:

```swift
@_spi(Experimental) import Testing

@Test func fatalErrorWorks() async {
    await #expect(exitsWith: .failure) {
        fatalError("Kablooey!")
    }
}
```

### Async Testing

**`confirmation()`** replaces XCTest expectations:

```swift
@Test func callbackFires() async {
    await confirmation("received notification") { confirm in
        NotificationCenter.default.addObserver(
            forName: .dataLoaded, object: nil, queue: nil
        ) { _ in confirm() }
        loadData()
    }
}

// Multiple expected calls
await confirmation("fires 3 times", expectedCount: 3) { confirm in
    for item in items { process(item); confirm() }
}
```

**`withKnownIssue`** for tracked intermittent failures (keeps test running, alerts when fixed):

```swift
await withKnownIssue("apple/swift-testing#1234", isIntermittent: true) {
    try await flakyNetworkCall()
    #expect(result.count > 0)
}
```

### Deterministic Async Testing

Use Point-Free's **`withMainSerialExecutor`** (from `ConcurrencyExtras`) for deterministic Task
scheduling:

```swift
import ConcurrencyExtras

@Test func isLoadingState() async {
    await withMainSerialExecutor {
        let model = Model(fetch: { await Task.yield(); return "result" })
        let task = Task { await model.loadButtonTapped() }
        await Task.yield()
        #expect(model.isLoading == true)  // deterministic
        await task.value
    }
}
```

### Clock Injection

Point-Free's `swift-clocks` package (`import Clocks`) ships three clock types: **`TestClock`**
(manual control), **`ImmediateClock`** (squash time to zero), **`UnimplementedClock`** (fails if
used unexpectedly).

## Pitfalls

| Trap                                  | Instead                                                 |
| ------------------------------------- | ------------------------------------------------------- |
| `#expect(processExits:)`              | `#expect(exitsWith:)` + `@_spi(Experimental)`           |
| `@testable import` everywhere         | `package` access level — explicit, no optimization loss |
| `Date()` / `Task.sleep` in production | Inject `Clock` protocol — test with `TestClock`         |

## Memory Leak Detection

```swift
extension XCTestCase {
    func trackForMemoryLeaks(
        _ instance: AnyObject,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(instance,
                "Potential memory leak.", file: file, line: line)
        }
    }
}
```

`addTeardownBlock` runs after the test method returns — local variables are released, so
`weak
instance` is nil only if no retain cycle exists.

## Rationalizations

| Excuse                                 | Reality                                                    |
| -------------------------------------- | ---------------------------------------------------------- |
| "zip is convenient for pairs"          | Silently drops when lengths differ. Use explicit tuples.   |
| "Actor mocks are verbose"              | Closure-based doubles need no types at all.                |
| "@unchecked Sendable is fine in tests" | Mutex gives genuine safety with no overhead.               |
| "I'll fix the flaky test later"        | Use withKnownIssue — keeps running, alerts when fixed.     |
| "@testable is standard practice"       | Creates 5 distinct problems. Use `package` access.         |
| "setUp/tearDown is fine"               | Swift Testing uses init/deinit + TestScoping traits.       |
| "Just disable that test"               | Disabled tests stay disabled. withKnownIssue has feedback. |
