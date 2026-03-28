---
name: code-ts
description: >
  Use when writing any TypeScript code, regardless of perceived simplicity or prototyping context.
  Use when you think code is "just a quick script" or "types slow me down" - these are symptoms
  this skill applies. Not for TypeScript-to-Lua — use code-tstl. Not for TSTL plugins — use
  code-tstl-plugin. For tests, also load test-ts. Applies to *.ts and *.tsx files.
---

# TypeScript - Production-Quality Code

**Core principle:** No `as` casts, no `any` leaks, no floating promises. Quick code becomes
production code — write it correctly the first time.

## Domain Skill Detection

When reviewing or writing TypeScript code, check for TSTL project markers. If detected, load the
corresponding skill for TSTL-specific best practices:

| Detection pattern                                                                   | Skill to load      |
| ----------------------------------------------------------------------------------- | ------------------ |
| `tstl` section in `tsconfig.json`, `@typescript-to-lua/language-extensions` imports | `code-tstl`        |
| `import * as tstl from "typescript-to-lua"` with `tstl.Plugin` implementation       | `code-tstl-plugin` |

Only load skills that are actually installed. If a skill fails to load, continue without it.

## Mandatory Rules

### No `as` Casts — Narrow Instead

`as` is erased at runtime. It silences the compiler without fixing the problem. Use type predicates,
assertion functions, or schema validation to narrow properly.

```typescript
// BAD: as casts vanish at runtime — no safety
const obj = raw as Record<string, unknown>;
const msg = (err as Error).message;
const config = parsed as unknown as Config;  // double cast = red flag

// GOOD: narrow with checks or schema validation
function isRecord(val: unknown): val is Record<string, unknown> {
  return val !== null && typeof val === "object" && !Array.isArray(val);
}

if (isRecord(raw)) { /* raw is narrowed */ }

// GOOD: schema validation at external boundaries
const config = ConfigSchema.parse(parsed);  // Zod throws structured errors
```

**Acceptable `as` uses:** `as const` (compile-time only), and after a manual narrowing guard where
TS can't narrow automatically (e.g., `typeof x === "object"` doesn't narrow to
`Record<string, unknown>` — casting after the guard is fine). Never use `as` to skip validation.
Double casts (`as unknown as T`) are always a red flag.

**Type predicate tip:** Use `Set<string>.has()` instead of `Array.includes()` to avoid `as` inside
predicates:

```typescript
// BAD: as cast needed because includes() takes the element type
const LEVELS = ["debug", "info", "warn", "error"] as const;
function isLevel(v: unknown): v is Level { return LEVELS.includes(v as Level); }

// GOOD: Set<string>.has() accepts any string
const LEVELS: ReadonlySet<string> = new Set(["debug", "info", "warn", "error"]);
function isLevel(v: unknown): v is Level { return typeof v === "string" && LEVELS.has(v); }
```

### No `any` Leaks — Contain at Boundaries

`JSON.parse` returns `any` that silently infects every variable it touches. Always type the result
as `unknown` and validate:

```typescript
// BAD: any spreads silently
const config = JSON.parse(rawJson);
const port: number = config.port;  // any assigned to number — no error

// GOOD: unknown + validation
const raw: unknown = JSON.parse(rawJson);
const config = ConfigSchema.parse(raw);
```

### No Floating Promises

Every promise must be `await`ed, `.catch()`ed, or explicitly `void`ed.

```typescript
// BAD: silent failure — no error, no log, no indication
saveUser(currentUser);

// GOOD
await saveUser(currentUser);
void saveUser(currentUser);  // intentional fire-and-forget
```

**In try/catch, always `return await`** — without `await`, rejections bypass the catch block:

```typescript
// BAD: catch is dead code for fetchFromDb errors
async function getData() {
  try {
    return fetchFromDb();  // no await — rejection skips catch
  } catch (err) {
    return fallback();     // never called
  }
}

// GOOD
async function getData() {
  try {
    return await fetchFromDb();
  } catch (err) {
    return fallback();
  }
}
```

### No Obvious Comments

Only explain **WHY** for non-obvious decisions. Never explain what code does.

```typescript
// BAD
/** Loads config from disk. */       // obvious from function name
const port = config.port ?? 3000;   // use default if no port

// GOOD
// Port 0 is valid in Node but unreliable in CI — default to 3000.
const port = config.port ?? 3000;
```

### Use `import type` for Type-Only Imports

Explicit `import type` prevents bundlers from accidentally preserving dead imports and enables
single-file transpilers (esbuild, SWC):

```typescript
import type { User } from "./types.js";
import { type Config, processConfig } from "./config.js";
```

### Use `node:` Protocol for Built-ins

```typescript
// BAD
import * as fs from "fs";

// GOOD
import * as fs from "node:fs";
import { readFile } from "node:fs/promises";
```

## Quick Reference

### Compile-Time vs Runtime

Know what survives compilation and what vanishes:

| Construct                  | Runtime?       | Notes                                                   |
| -------------------------- | -------------- | ------------------------------------------------------- |
| `interface` / `type`       | Erased         | Zero bytes                                              |
| `readonly`                 | Erased         | No runtime immutability — use `Object.freeze()`         |
| `private` keyword          | Erased         | Accessible at runtime — use `#private` for enforcement  |
| `as` / `satisfies` / `!`   | Erased         | Zero safety at runtime                                  |
| `enum`                     | IIFE + object  | ~200 bytes each — prefer `const enum` or union literals |
| `class` / `abstract class` | Full prototype | `abstract` keyword erased                               |

### Narrowing Patterns

| Task                   | Pattern                                                             |
| ---------------------- | ------------------------------------------------------------------- |
| Null/undefined check   | `if (val != null)` or `if (val !== undefined)`                      |
| Object type guard      | `function isUser(v: unknown): v is User`                            |
| Assertion function     | `function assertString(v: unknown): asserts v is string`            |
| Discriminated union    | `switch (shape.kind)` + `assertNever` default                       |
| Filter with narrowing  | `.filter((x): x is string => x !== null)` — type predicate required |
| External data boundary | Schema validation (Zod, Valibot) — "parse, don't validate"          |

### Exhaustiveness Checking

```typescript
function assertNever(x: never): never {
  throw new Error(`Unexpected: ${JSON.stringify(x)}`);
}

function area(shape: Shape): number {
  switch (shape.kind) {
    case "circle": return Math.PI * shape.r ** 2;
    case "square": return shape.s ** 2;
    default: return assertNever(shape);  // compile error if variant added
  }
}
```

## Pitfalls

| Trap                                       | Instead                                                                          |
| ------------------------------------------ | -------------------------------------------------------------------------------- |
| `as` cast to silence compiler              | Narrow with type guard or schema validation                                      |
| `any` from `JSON.parse` spreading          | Type as `unknown`, validate at boundary                                          |
| `readonly` = immutable                     | `Object.freeze()` for runtime enforcement                                        |
| `private` = inaccessible                   | `#private` fields (ES2022+) for runtime                                          |
| `Partial<T>` is deep                       | Shallow only — nested objects stay required                                      |
| `Omit<T, "key">` verifies key              | It does not — use `StrictOmit<T, K extends keyof T>`                             |
| `"a" \| "b" \| string` narrows             | Collapses to `string` — remove the `string` widener                              |
| `Object.keys()` returns `(keyof T)[]`      | Returns `string[]` — intentional due to structural typing                        |
| `\|\|` for defaults                        | Use `??` — `\|\|` replaces `0`, `""`, `false`                                    |
| `if (promise)` checks value                | Always truthy — checks object ref, not resolved value                            |
| `return fetch()` in try/catch              | `return await` — otherwise catch is dead code                                    |
| `.filter(x => x !== null)` narrows         | Returns original type — needs explicit type predicate                            |
| `JSON.stringify` always returns string     | Returns `undefined` for undefined/functions/symbols; throws on BigInt/circular   |
| Chained `.map().filter().reduce()`         | Single `for-of` loop in hot paths — no intermediate arrays                       |
| Spread-in-reduce `{ ...acc, [key]: val }`  | O(n^2) — mutate accumulator in place                                             |
| `interface &` intersection for composition | Use `interface extends` — intersections aren't cached, conflicts produce `never` |

## Generics Gotchas

| Pattern                              | Issue                            | Fix                                          |
| ------------------------------------ | -------------------------------- | -------------------------------------------- |
| `T extends any ? T[] : never`        | Distributes over unions          | Wrap in tuple: `[T] extends [any]`           |
| `IsNever<never>`                     | Returns `never` not `true`       | `[T] extends [never] ? true : false`         |
| `infer P` in param position          | Produces intersection, not union | Expected behavior — design accordingly       |
| Generic inferred from multiple sites | Type widens unexpectedly         | Use `NoInfer<T>` (5.4+) on secondary sites   |
| Recursive conditional types          | ~100 depth limit (non-tail)      | Use accumulator pattern for ~1000 iterations |

## Recommended `tsconfig.json`

```jsonc
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noPropertyAccessFromIndexSignature": true,
    "noImplicitOverride": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "allowUnusedLabels": false,
    "allowUnreachableCode": false,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "target": "es2024",
    "skipLibCheck": true,
  },
}
```

**Key flags outside `strict: true`** that catch entire bug categories:

- **`noUncheckedIndexedAccess`** — `arr[0]` is `T | undefined`, not `T`
- **`exactOptionalPropertyTypes`** — prevents `{ key: undefined }` where key should be absent
- **`verbatimModuleSyntax`** — enforces `import type`, enables single-file transpilers
- **`isolatedModules`** — compatibility with esbuild/SWC
- **`skipLibCheck`** — 40-66% faster builds

## Rationalizations That Mean You're About to Fail

| Excuse                              | Reality                                                                                  |
| ----------------------------------- | ---------------------------------------------------------------------------------------- |
| "Quick `as` cast, I'll fix later"   | You won't. `as` hides bugs that crash at runtime.                                        |
| "Types slow me down"                | Types catch bugs at write-time. Debugging is slower.                                     |
| "Just prototyping"                  | Prototypes become production. No shortcuts.                                              |
| "This is too simple for validation" | `JSON.parse` returns `any`. One leak infects the chain.                                  |
| "`readonly` makes it immutable"     | Erased at runtime. Use `Object.freeze()`.                                                |
| "`private` keeps it safe"           | Erased at runtime. Use `#private` fields.                                                |
| "`strict: true` is enough"          | Misses `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `verbatimModuleSyntax`. |
| "I'll add `import type` later"      | Without `verbatimModuleSyntax`, bundlers can't distinguish.                              |
| "Filter narrows the type"           | `.filter(x => x !== null)` does NOT narrow — needs type predicate.                       |
| "This `as` cast is unavoidable"     | Use `Set.has()` instead of `includes()`, or `isRecord` guard. Almost always avoidable.   |

## Verification

**MANDATORY before completing any task:**

```bash
npx tsc --noEmit      # Type checking (biome doesn't type-check)
npx biome check .     # Linting and formatting
npx vitest run        # If tests exist — always run separately
```

Lefthook manages git hooks. **Task is NOT complete until all pass.**
