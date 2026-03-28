# Vitest API Reference

- [Mocking Quick Reference](#mocking-quick-reference)
- [Fake Timers Quick Reference](#fake-timers-quick-reference)
- [Vitest Config Recommendations](#vitest-config-recommendations)

## Mocking Quick Reference

### The Clearing Trifecta

| Method                 | Clears history |              Removes impl              | Restores original |
| ---------------------- | :------------: | :------------------------------------: | :---------------: |
| `vi.clearAllMocks()`   |      Yes       |                   No                   |        No         |
| `vi.resetAllMocks()`   |      Yes       | Yes (restores original in Vitest 3.x!) |        No         |
| `vi.restoreAllMocks()` |      Yes       |                  Yes                   |        Yes        |

**Vitest 3.x gotcha:** `vi.resetAllMocks()` restores the **original implementation** for spies —
unlike Jest where it replaced with a noop. If your `afterEach` calls `resetAllMocks` expecting
functions to return `undefined`, you're now silently running real implementations.

**None of these unmock `vi.mock()` module mocks.** Module-level mocks persist for the entire file.

### `vi.mock` Factory Rules

```typescript
// BAD: factory can't access file-scope variables (ReferenceError at hoist time)
import { helper } from "./helpers";
vi.mock("./module", () => ({ fn: () => helper() }));

// GOOD: use vi.hoisted() for variables needed by factories
const mocks = vi.hoisted(() => ({ fn: vi.fn() }));
vi.mock("./module", () => ({ fn: mocks.fn }));

// GOOD: partial mock with async factory
vi.mock(import("./calculator"), async (importOriginal) => {
  const mod = await importOriginal();
  return { ...mod, multiply: vi.fn(() => 42) };
});
```

**Default exports:** In Vitest, you must specify `default` explicitly in `vi.mock` factories.
`vi.mock('./config', () => ({ default: { apiUrl: 'test' } }))`.

### Mock This, Not That

| Mock                     | Don't mock                  |
| ------------------------ | --------------------------- |
| HTTP clients             | Business logic              |
| Database connections     | Internal functions          |
| File I/O                 | Data transformations        |
| External APIs / services | Your own modules' internals |

## Fake Timers Quick Reference

| Pattern                 | Correct                                    | Wrong                                   |
| ----------------------- | ------------------------------------------ | --------------------------------------- |
| Advance with async code | `await vi.advanceTimersByTimeAsync(ms)`    | `vi.advanceTimersByTime(ms)`            |
| Run all pending timers  | `await vi.runAllTimersAsync()`             | `vi.runAllTimers()`                     |
| Advance to next timer   | `await vi.advanceTimersToNextTimerAsync()` | `vi.advanceTimersToNextTimer()`         |
| Cleanup                 | `afterEach(() => vi.useRealTimers())`      | `vi.useRealTimers()` inline at test end |
| Deadlock avoidance      | Separate promise creation from awaiting    | `await sleep(1000)` with fake timers    |

**The fundamental deadlock:** `await sleep(1000)` suspends the test waiting for `setTimeout` to fire
— but `setTimeout` is fake and only fires when you call `vi.runAllTimers()`, which never executes
because the test is suspended. Fix: `const p = sleep(1000); await vi.runAllTimersAsync(); await p;`

## Vitest Config Recommendations

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    clearMocks: true, // clear call history between tests, keep implementations
    // Use 'projects' (not deprecated 'workspace') for multi-project:
    // projects: [
    //   { extends: true, test: { name: 'unit', include: ['**/*.unit.test.ts'] } },
    // ],
  },
});
```

If you have a separate `vitest.config.ts`, it does **not** inherit from `vite.config.ts` — use
`mergeConfig(viteConfig, defineConfig({ test: { ... } }))`.
