---
name: code-ts
description: >
  Use when writing any TypeScript code, regardless of perceived simplicity or prototyping context.
  Use when you think code is "just a quick script" or "types slow me down" - these are symptoms
  this skill applies. Not for TypeScript-to-Lua — use code-tstl. Not for TSTL plugins — use
  code-tstl-plugin. For tests, also load test-ts. Applies to *.ts and *.tsx files.
user-invocable: false
---

# TypeScript - Production-Quality Code

**This skill extends `Skill(code-core)`.** `code-core` is the primary entry point; this skill is
loaded by `code-core` based on the rules-file dispatch table.

**Core principle:** No `as` casts, no `any` leaks, no floating promises.

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

| Construct         | Runtime?      | Notes                                                                                         |
| ----------------- | ------------- | --------------------------------------------------------------------------------------------- |
| `readonly`        | Erased        | No runtime immutability — use `Object.freeze()`                                               |
| `private` keyword | Erased        | Accessible at runtime — use `#private` for enforcement                                        |
| `enum`            | IIFE + object | ~200 bytes each — prefer union literals; `const enum` does not inline under `isolatedModules` |

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

| Trap                                                                                  | Instead                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Partial<T>` is deep                                                                  | Shallow only — nested objects stay required                                                                                                                                                                                                                           |
| `Omit<T, "key">` verifies key                                                         | It does not — define `type StrictOmit<T, K extends keyof T> = Omit<T, K>`                                                                                                                                                                                             |
| `"a" \| "b" \| string` narrows                                                        | Collapses to `string` — remove the `string` widener                                                                                                                                                                                                                   |
| `Object.keys()` returns `(keyof T)[]`                                                 | Returns `string[]` — intentional due to structural typing                                                                                                                                                                                                             |
| `.filter(x => x !== null)` narrows                                                    | Returns original type — needs explicit type predicate                                                                                                                                                                                                                 |
| `JSON.stringify` always returns string                                                | Returns `undefined` for undefined/functions/symbols; throws on BigInt/circular                                                                                                                                                                                        |
| Chained `.map().filter().reduce()`                                                    | Single `for-of` loop in hot paths — no intermediate arrays                                                                                                                                                                                                            |
| Spread-in-reduce `{ ...acc, [key]: val }`                                             | O(n^2) — mutate accumulator in place                                                                                                                                                                                                                                  |
| `interface &` intersection for composition                                            | Use `interface extends` — intersections aren't cached, conflicts produce `never`                                                                                                                                                                                      |
| `exactOptionalPropertyTypes`: conditional-spreading every `T \| undefined` assignment | On types you own where a present-`undefined` key is harmless, declare `x?: T \| undefined` and assign plainly; keep bare `?:` + `...(v !== undefined && { x: v })` only where a stray `undefined` key clobbers spread-merged defaults or leaks via `Object.keys`/JSON |

## House tsconfig

House tsconfig lives in `setup-ts/references/tsconfig.json` — run `/setup-ts init` or
`/setup-ts update` to install or reconcile it; never hand-write one here.

## Rationalizations That Mean You're About to Fail

| Excuse                              | Reality                                                                                  |
| ----------------------------------- | ---------------------------------------------------------------------------------------- |
| "Quick `as` cast, I'll fix later"   | Use `Set.has()` instead of `includes()`, or `isRecord` guard. Almost always avoidable.   |
| "Types slow me down"                | Types catch bugs at write-time. Debugging is slower.                                     |
| "This is too simple for validation" | `JSON.parse` returns `any`. One leak infects the chain.                                  |
| "`strict: true` is enough"          | Misses `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `verbatimModuleSyntax`. |
| "I'll add `import type` later"      | Without `verbatimModuleSyntax`, bundlers can't distinguish.                              |

## Verification

Run the gates the project exposes: read the `scripts` in `package.json` and run its typecheck,
lint/format, and test scripts, whatever they are named. Tests always run separately from static
checks. If no script covers type checking, fall back to `npx tsc --noEmit`.
