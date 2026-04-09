---
name: test-ts
description: >
  Use when writing TypeScript tests with Vitest. Apply for mocking, fake timers, parametrization,
  property-based testing, test isolation, flaky tests, toEqual vs toStrictEqual confusion,
  timer/promise deadlocks, mock reset semantics, type-safe test factories, or any *.test.ts files.
  Not for production TypeScript code — use code-ts for that.
paths: "**/*.test.ts, **/*.test.tsx, **/*.spec.ts, **/*.spec.tsx"
user-invocable: false
model: sonnet
effort: medium
---

# TypeScript Testing with Vitest

**Core principle:** Test behavior, not implementation. Every test follows Arrange-Act-Assert.
Default to the strictest API (`toStrictEqual`, async timer variants, `expect.hasAssertions`) —
loosen only when you have a reason.

**Also apply:** `code-ts` rules. Exception: test helper functions don't need full JSDoc.

## Mandatory Rules

### 1. Arrange-Act-Assert Structure

```typescript
// BAD: mixed up
it("creates user", () => {
  expect(createUser("Alice").name).toBe("Alice");
  const user = new User("Bob");
  expect(user.isValid()).toBe(true);
});

// GOOD: clear AAA with blank-line separators
it("sets name on created user", () => {
  const name = "Alice";

  const user = createUser(name);

  expect(user.name).toBe(name);
});
```

### 2. Descriptive Test Names

Format: `<unit> <when condition> <expected outcome>`

```typescript
it("process rejects when executor throws after all retries", ...)
it("getStats returns all zeros for empty queue", ...)
```

Use `describe` blocks to mirror this format at the suite level — group by unit, then condition:

```typescript
describe("Queue", () => {
  describe("when empty", () => {
    it("returns size zero", ...);
    it("throws on dequeue", ...);
  });
  describe("when at capacity", () => {
    it("rejects new items", ...);
  });
});
```

### 3. `toStrictEqual` Over `toEqual` for Objects

`toEqual` silently ignores `undefined` properties, class/prototype differences, and sparse arrays.
Use `toStrictEqual` as your default — it catches structural mismatches that `toEqual` hides.

```typescript
// BAD: passes even though b is missing
expect({ a: 1, b: undefined }).toEqual({ a: 1 }); // PASSES ← silent mismatch

// GOOD: catches the difference
expect({ a: 1, b: undefined }).toStrictEqual({ a: 1 }); // FAILS ← correct
```

Reserve `toEqual` only when you intentionally want loose matching (e.g., ignoring extra `undefined`
fields from optional properties).

### 4. Always Use Async Timer APIs

Sync `vi.advanceTimersByTime()` fires timers but **does not flush microtasks** between callbacks.
When timer callbacks contain Promises, `.then()`, or `await`, the sync variant silently skips them —
causing deadlocks or flaky tests.

```typescript
// BAD: sync — skips microtasks between timer ticks
vi.advanceTimersByTime(1000);

// GOOD: async — flushes microtasks between each timer
await vi.advanceTimersByTimeAsync(1000);
```

**Always use:** `vi.runAllTimersAsync()`, `vi.advanceTimersByTimeAsync()`,
`vi.advanceTimersToNextTimerAsync()`. The sync variants exist only for purely synchronous timer
callbacks.

### 5. Fake Timers Cleanup in `afterEach`

Never call `vi.useRealTimers()` inline at the end of a test. If the test throws before that line,
fake timers leak into subsequent tests causing bizarre failures.

```typescript
// BAD: leaks on throw
it("times out", async () => {
  vi.useFakeTimers();
  // ... test ...
  vi.useRealTimers(); // never reached if test throws
});

// GOOD: afterEach always runs
afterEach(() => {
  vi.useRealTimers();
});

it("times out", async () => {
  vi.useFakeTimers();
  // ... test ...
});
```

### 6. `expect.hasAssertions()` for Callback/Event Tests

Without this, a test with assertions inside a callback that never fires passes silently:

```typescript
// BAD: passes even if event never fires
it("emits data", async () => {
  emitter.on("data", (d) => {
    expect(d).toBeTruthy(); // may never execute
  });
  await trigger();
});

// GOOD: fails if no assertions ran
it("emits data", async () => {
  expect.hasAssertions();
  emitter.on("data", (d) => {
    expect(d).toBeTruthy();
  });
  await trigger();
});
```

Better yet, prefer `events.once()` from `node:events` to turn event-waiting into an awaitable:

```typescript
import { once } from "node:events";
const [data] = await once(emitter, "data");
expect(data).toBeTruthy();
```

When the event fires mid-process (e.g., a "started" event during an async `process()` call), use
`void` to suppress the floating-promise lint while awaiting the event separately:

```typescript
const startedPromise = once(queue, "started");
void queue.process(executor); // intentional fire-and-forget
const [task] = await startedPromise;
```

### 7. No `as` Casts in Tests — Use Factories

`as` casts hide missing fields. When the type gains a new required field, the factory forces a
single update; casts silently create invalid objects.

```typescript
// BAD: hides missing required fields, won't catch schema changes
const user = { id: "1" } as User;

// GOOD: compiler errors when User gains new required fields
function createTestUser(overrides: Partial<User> = {}): User {
  return {
    id: "user-1",
    name: "Test User",
    email: "test@example.com",
    createdAt: new Date("2024-01-01"),
    ...overrides,
  };
}
```

Also applies to narrowing unknown results — use type guards, not `as`:

```typescript
// BAD
const r = result.result as { nested: { value: number } };

// GOOD
expect(result.result).toStrictEqual({ nested: { value: 42 } });
```

### 8. No Loops in Test Bodies

Use `test.for` (Vitest 2.x+) or `test.each` — they show all cases and run independently.

```typescript
// BAD: stops at first failure, no per-case reporting
for (const id of ids) {
  expect(id).toMatch(/^[0-9a-f-]+$/);
}

// GOOD: each case is a separate test
test.for([
  { input: "valid@email.com", valid: true },
  { input: "not-an-email", valid: false },
])("validates $input", ({ input, valid }) => {
  expect(validateEmail(input)).toBe(valid);
});
```

When `test.for`/`test.each` is overkill (e.g., checking 2–3 items), just write separate `expect`
calls — no loop needed.

### 9. MVP Tests — Minimum Tests, Maximum Coverage

```typescript
// BAD: separate tests for same code path
it("rejects null", () => { expect(() => fn(null)).toThrow(); });
it("rejects empty", () => { expect(() => fn("")).toThrow(); });

// GOOD: merge related validations
it("rejects invalid input", () => {
  expect(() => fn(null)).toThrow();
  expect(() => fn("")).toThrow();
});
```

| Merge when                          | Keep separate when    |
| ----------------------------------- | --------------------- |
| Same code path, different inputs    | Different code paths  |
| Related edge cases (null, empty, 0) | Complex setup differs |
| Same behavior across APIs           | Tests need isolation  |

### 10. Mock at Boundaries Only

```typescript
// BAD: mocking internal function
vi.spyOn(service, "_parseResponse").mockReturnValue({});

// GOOD: mock the external HTTP call
vi.mock("./api-client", () => ({
  default: { fetch: vi.fn().mockResolvedValue({ data: [] }) },
}));
```

### 11. Type-Level Tests with `expectTypeOf`

Runtime tests don't catch type regressions. Use `expectTypeOf` for compile-time assertions:

```typescript
// BAD: runtime-only "type test" that proves nothing
const statuses: Task["status"][] = ["pending", "running", "completed", "failed"];
expect(statuses).toContain(task.status);

// GOOD: compile-time type assertion
import { expectTypeOf } from "vitest";
expectTypeOf(task.status).toEqualTypeOf<"pending" | "running" | "completed" | "failed">();
expectTypeOf<Task>().toHaveProperty("createdAt").toEqualTypeOf<Date>();
```

For mocking API (clearing trifecta, vi.mock factory rules, mock this/not that), fake timers API, and
Vitest config recommendations, see `references/vitest-api.md`.

## Pitfalls

| Trap                                             | Instead                                                       |
| ------------------------------------------------ | ------------------------------------------------------------- |
| `toEqual` for object comparisons                 | `toStrictEqual` — catches `undefined` props, class mismatches |
| Sync timer APIs with async code                  | `vi.advanceTimersByTimeAsync()` and friends                   |
| `vi.useRealTimers()` at end of test              | `afterEach(() => vi.useRealTimers())`                         |
| `as` casts in test data                          | Factory functions with `Partial<T>` overrides                 |
| Assertions inside callbacks without guard        | `expect.hasAssertions()` or `events.once()`                   |
| Manual try/catch for promise assertions          | `await expect(fn()).resolves.toBe(v)` / `.rejects.toThrow()`  |
| `for` loops in test body                         | `test.for` / `test.each` or separate expects                  |
| Runtime "type tests"                             | `expectTypeOf` for compile-time assertions                    |
| `vi.mock` factory referencing imports            | `vi.hoisted()` for factory-accessible variables               |
| `vi.importActual` without `await`                | `async (importOriginal) => ({ ...(await importOriginal()) })` |
| `mock.results[0].value` for async mocks          | `mock.settledResults[0]` for resolved values                  |
| `vi.resetAllMocks()` expecting noop (Jest habit) | In Vitest 3.x it restores original implementation             |
| Missing `default` key in `vi.mock` factory       | `{ default: ... }` — Vitest requires it explicitly            |
| `toThrowError('')` for "any error"               | Empty string matches ALL errors (known bug). Use `toThrow()`  |
| `expect.soft()` forgotten for multi-field checks | Collects all failures instead of stopping at first            |
| `await sleep(100)` then assert                   | `await vi.waitFor(() => expect(...))`                         |

## Data Testing Patterns

| Tool               | Use For                                              |
| ------------------ | ---------------------------------------------------- |
| `fast-check`       | Property-based testing — prefer over hardcoded data  |
| `zod`              | Schema validation for runtime data                   |
| `expect.closeTo()` | Float comparisons with tolerance                     |
| `msw`              | HTTP mocking (interceptor-based, no server patching) |
| `@faker-js/faker`  | Realistic random test data                           |

## Verification

**MANDATORY before completing any task:**

```bash
npx vitest run           # Run test suite
npx tsc --noEmit         # Type check
```

**Task is NOT complete until all pass.**

## Rationalizations

| Excuse                               | Reality                                                                         |
| ------------------------------------ | ------------------------------------------------------------------------------- |
| "`toEqual` is fine for this"         | `toEqual` ignores `undefined` props and class differences. Use `toStrictEqual`. |
| "Sync timer advance works here"      | Until a microtask is added inside the callback. Use async variants always.      |
| "I'll clean up timers at the end"    | If the test throws, cleanup never runs. `afterEach` always runs.                |
| "`as` cast is just for tests"        | Tests are contracts. A cast hides broken contracts. Use factories.              |
| "The event listener definitely runs" | Without `hasAssertions`, a never-called listener = green test.                  |
| "Loop is cleaner than parametrize"   | Loop stops at first failure and hides which case broke.                         |
| "Runtime type check is enough"       | It proves nothing about compile-time safety. Use `expectTypeOf`.                |
| "`resetAllMocks` clears everything"  | It doesn't unmock modules and restores originals in Vitest 3.x.                 |
