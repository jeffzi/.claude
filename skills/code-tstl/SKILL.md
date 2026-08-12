---
name: code-tstl
description: >
  Use when writing TypeScript-to-Lua (TSTL) code targeting Lua 5.1. Use when transpiling TypeScript
  to Lua for game engines (LÖVE, Defold, WoW, MA Lighting), embedded Lua, or any TSTL project.
  Use when you see "while loop" where a numeric for should be, or Map/Set where LuaMap/LuaSet
  belongs - these are symptoms this skill applies. Not for standard TypeScript — use code-ts.
  Not for TSTL plugin development — use code-tstl-plugin.
user-invocable: false
---

# TSTL - TypeScript-to-Lua for Lua 5.1

**Core principle:** Write TypeScript that generates the Lua code an expert would write by hand.
Every idiomatic TypeScript pattern has a TSTL-specific cost — know it and avoid it in hot paths.

**REQUIRED BACKGROUND:** Load `Skill(code-ts)` first for general TypeScript rules. This skill adds
TSTL-specific patterns on top.

## Domain Skill Detection

When reviewing or writing TSTL code, check for plugin development patterns. If detected, load the
corresponding skill:

| Detection pattern                                                             | Skill to load             |
| ----------------------------------------------------------------------------- | ------------------------- |
| `import * as tstl from "typescript-to-lua"` with `tstl.Plugin` implementation | `Skill(code-tstl-plugin)` |

Only load skills that are actually installed. If a skill fails to load, continue without it.

## Lua 5.1 Hard Constraints

These are **compile errors or runtime crashes**, not style preferences:

| Constraint                                          | What happens                     | Workaround                                                                           |
| --------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------ |
| No `continue`                                       | **Compile error**                | Invert condition: `if (!skip) { body }`                                              |
| No bitwise ops (`&`, `\|`, `^`, `<<`, `>>`, `\| 0`) | **Compile error**                | External bit library or arithmetic (`% 256` for `& 0xFF`, `math.floor()` not `\| 0`) |
| 60-upvalue limit per closure                        | **Runtime crash**                | Bundle variables into a single table                                                 |
| 200-local limit per scope                           | **Runtime crash** (100+ imports) | Namespace imports: `import * as utils from "..."`                                    |
| `#` unreliable on sparse arrays                     | **Wrong length**                 | Never create gaps — use `push`/`pop`/`splice` only                                   |

## Mandatory Rules

### Use `$range()` for Every Numeric Loop

Standard `for` loops transpile to `while` loops, bypassing Lua's native `FORPREP`/`FORLOOP` VM
opcodes. **2-100x slower** depending on iteration count.

```typescript
// BAD: transpiles to while loop
for (let i = 0; i < count; i++) { process(i); }

// GOOD: transpiles to native numeric for
import { $range } from "@typescript-to-lua/language-extensions";
for (const i of $range(0, count - 1)) { process(i); }
```

**No exceptions in hot paths.** This is the single highest-impact optimization.

### Use `LuaMap`/`LuaSet` Instead of `Map`/`Set`

ES6 `Map`/`Set` are full polyfill classes with insertion-order tracking and metatable dispatch.
`LuaMap`/`LuaSet` compile to raw Lua table operations.

```typescript
// BAD: heavy polyfill — __TS__New(Map), metatable methods, order tracking
const enemies = new Map<string, Enemy>();

// GOOD: compiles to raw table ops — enemies = {}; enemies[key] = val
const enemies = new LuaMap<string, Enemy>();
```

Use ES6 `Map`/`Set` **only** when you specifically need insertion-order preservation.

### Use `LuaTable` Instead of TypeScript Arrays

TypeScript arrays are 0-indexed; TSTL emits `[i + 1]` on every numeric index access to bridge the
gap to Lua's 1-based tables. That arithmetic fires on **every read and write in hot loops**.

```typescript
// BAD: 0-indexed array — TSTL adds +1 on every access
const enemies: Enemy[] = [];
for (const i of $range(0, enemies.length - 1)) {
  const e = enemies[i]; // transpiles to: enemies[i + 1]
}

// GOOD: LuaTable — native 1-based indexing, zero arithmetic overhead
const enemies = new LuaTable<number, Enemy>();
for (const i of $range(1, enemies.length())) {
  const e = enemies.get(i); // transpiles to: enemies[i]
}
```

Key API differences vs TypeScript arrays:

| Operation   | TypeScript array | LuaTable equivalent            |
| ----------- | ---------------- | ------------------------------ |
| Get element | `arr[i]`         | `tbl.get(i)`                   |
| Set element | `arr[i] = v`     | `tbl.set(i, v)`                |
| Length      | `arr.length`     | `tbl.length()`                 |
| Append      | `arr.push(v)`    | `tbl.set(tbl.length() + 1, v)` |

**Exception:** When iterating with `for...of` (not indexed access), TSTL uses `ipairs` — no `+1` is
added, though `ipairs` is still slower than a numeric `$range()` loop when you can index directly.
The rule applies to any code that indexes by a numeric variable.

For O(1) removal in hot paths, use swap-with-last + `pop()` instead of `splice()`.

### Use `const enum` — Always

Regular enums create a runtime lookup table. `const enum` inlines values directly — zero allocation,
zero field access.

```typescript
// BAD: table allocation + field lookups at runtime
enum State { Idle, Moving, Attacking }

// GOOD: values inlined as constants (0, 1, 2)
const enum State { Idle, Moving, Attacking }
```

### Interfaces + Free Functions Over Classes

TSTL classes generate metatable chains via `__TS__Class()` and `__TS__New()`. Every method call
traverses `__index`. Benchmarked at **~12x slower than local variable access**, with **~20%
additional overhead per inheritance level**.

```typescript
// BAD: metatable dispatch on every method call
class Enemy {
  health: number;
  constructor(health: number) { this.health = health; }
  takeDamage(amount: number) { this.health -= amount; }
}

// GOOD: direct table field access, zero metatable overhead
interface Enemy { health: number; }
function createEnemy(health: number): Enemy { return { health }; }
function takeDamage(enemy: Enemy, amount: number): void { enemy.health -= amount; }
```

Reserve classes for code where OOP abstraction genuinely helps maintainability, not hot-path
entities.

### No `continue` — Invert Conditions

```typescript
// BAD: compile error in Lua 5.1
for (const e of enemies) {
  if (e.isDead) continue;
  e.update();
}

// GOOD: inverted condition
for (const e of enemies) {
  if (!e.isDead) { e.update(); }
}
```

### No Async/Await — Use Coroutines

TSTL's `async`/`await` transpiles to a `__TS__Promise` polyfill with wrong execution order (resolves
immediately instead of deferring) and adds polyfill weight. Coroutines are native Lua, zero-cost,
and integrate with host engine schedulers.

```typescript
// BAD: __TS__Promise polyfill, wrong execution order, no engine integration
async function fadeOut(entity: Entity): Promise<void> {
  for (let alpha = 1; alpha >= 0; alpha -= 0.1) {
    entity.alpha = alpha;
    await delay(16);
  }
}

// GOOD: native Lua coroutine, zero overhead, engine-integrated
function fadeOut(entity: Entity): void {
  for (const _ of $range(1, 10)) {
    entity.alpha -= 0.1;
    coroutine.yield();  // yields to engine scheduler
  }
}
// const co = coroutine.create(() => fadeOut(entity));
// In game loop: coroutine.resume(co);
```

## Hot-Path Patterns

### Localize Repeated Field Access in Hot Loops

Lua local variables use register-based access; table field lookups go through hash tables. Any field
read repeated per iteration of a hot loop should be hoisted to a `const` local before the loop.

This applies to **all** table field access — globals (`_G`), module tables, context objects, nested
fields — not just `Math.*`.

```typescript
// BAD: ctx.world looked up through hash table on every iteration
for (const i of $range(0, n - 1)) {
  despawn(ctx.world, ctx.tracked[i]);
}

// GOOD: localized before the loop
const world = ctx.world;
const tracked = ctx.tracked;
for (const i of $range(0, n - 1)) {
  despawn(world, tracked[i]);
}

// BAD: math.cos, math.sin looked up through _G each iteration
for (const p of particles) { p.x += Math.cos(p.angle) * p.speed; }

// GOOD: cached as locals at module top
const cos = Math.cos;
const sin = Math.sin;
for (const p of particles) { p.x += cos(p.angle) * p.speed; }
```

### No Array Method Chaining — Single-Pass Loops

Each `.filter()`, `.map()`, `.reduce()` allocates a new table and makes N callback invocations (~12x
slower than inline code in Lua 5.1).

```typescript
// BAD: 2 temporary tables + 2N function calls
const result = enemies.filter(e => e.isAlive).map(e => e.position);

// GOOD: single pass, zero temporaries, native for
const result = new LuaTable<number, Position>();
let resultLen = 0;
for (const i of $range(1, enemies.length())) {
  const e = enemies.get(i)!;
  if (e.isAlive) { resultLen++; result.set(resultLen, e.position); }
}
```

### Mutate In Place — No Object Spread in Loops

`{...obj}` transpiles to `__TS__ObjectAssign({}, obj)` — creates 2 tables and copies all fields via
`pairs()` iteration every call.

```typescript
// BAD: 2 new tables per call
function move(e: Entity, dx: number, dy: number): Entity {
  return { ...e, x: e.x + dx, y: e.y + dy };
}

// GOOD: zero allocations
function move(e: Entity, dx: number, dy: number): void {
  e.x += dx;
  e.y += dy;
}
```

### Reuse Tables — Pre-allocate With Object Literals

Incremental construction (`a={}; a.x=1; a.y=2`) causes **3 rehashes and 2.9x slower** than
constructor form (`{x:1, y:2}`). For per-frame returns, reuse a scratch table:

```typescript
// BAD: new table every frame per entity
function getVelocity(e: Entity): Vector2 { return { x: cos(e.angle) * e.speed, y: sin(e.angle) * e.speed }; }

// GOOD: reuse scratch table
const _vel: Vector2 = { x: 0, y: 0 };
function getVelocity(e: Entity, out: Vector2 = _vel): Vector2 {
  out.x = cos(e.angle) * e.speed;
  out.y = sin(e.angle) * e.speed;
  return out;
}
```

### Build Strings with `table.concat`

Template literals produce `..` chains with intermediate string allocations. Repeated concatenation
is O(n^2).

```typescript
// BAD: O(n²) string concatenation in loop
let log = "";
for (const e of events) { log += `[${e.time}] ${e.msg}\n`; }

// GOOD: collect in array, join once (table.concat is C-level, single allocation)
const parts: string[] = [];
for (const e of events) { parts.push(`[${e.time}] ${e.msg}`); }
const log = table.concat(parts, "\n");
```

## TS-vs-Lua Correctness Caveats

Silent behavioral differences between TypeScript and transpiled Lua — these won't error, they'll
just do the wrong thing:

| Caveat                             | JS behavior                       | Lua behavior                | Fix                                                                                        |
| ---------------------------------- | --------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------ |
| `undefined` vs `null`              | Distinct values                   | Both are `nil`              | Prefer `undefined`; never rely on the distinction                                          |
| Assign `undefined` to key          | Key exists with value `undefined` | Key is **deleted**          | Use sentinel (`-1`, `""`) if key must persist                                              |
| Boolean coercion: `0`, `""`, `NaN` | All falsy                         | All **truthy**              | Explicit comparisons: `x !== 0`, `x !== ""`, `x === x` (NaN); `??` not `\|\|` for defaults |
| `==` vs `===`                      | Loose vs strict equality          | Both compile to strict `==` | Always use `===` (enable `eqeqeq` lint rule)                                               |
| `for...in` on arrays               | Iterates string indices           | **Forbidden**               | `$range()` or `for...of`                                                                   |
| `Array.fill(v, start, end)`        | Clamps `end` to array length      | Fills to `end` regardless   | Be explicit about bounds                                                                   |
| `Array.sort` stability             | Stable (ES2019+)                  | **Not guaranteed**          | Implement stable sort if equal-element order matters                                       |
| Key iteration order                | Insertion order (ES2015+)         | **Unspecified**             | Use arrays when order matters                                                              |
| `async`/`await` execution order    | Deferred (microtask queue)        | **Immediate** resolution    | Use coroutines instead (see Mandatory Rules)                                               |

## Interop

For interop patterns (`@noSelf`, `LuaMultiReturn`, external declarations, global callbacks), see
`references/interop.md`.

## Recommended `tsconfig.json`

```jsonc
{
  "compilerOptions": {
    "target": "ESNext",
    "lib": ["ESNext"],
    "moduleResolution": "Node",
    "types": ["@typescript-to-lua/language-extensions", "lua-types/5.1"],
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
  },
  "tstl": {
    "luaTarget": "5.1",
    "luaLibImport": "require-minimal",
    "noImplicitSelf": true,
    "noImplicitGlobalVariables": true,
    "noHeader": true,
  },
}
```

Key TSTL settings:

- **`luaLibImport: "require-minimal"`** — tree-shakes polyfills (not `"inline"` which duplicates)
- **`noImplicitSelf: true`** — eliminates hidden `self` on implemented functions only (not
  declarations, interfaces, or class methods — those still need `@noSelf` / `this: void`)
- **`noImplicitGlobalVariables: true`** — forces `local` declarations, prevents accidental globals

## Rationalizations That Mean You're About to Fail

| Excuse                              | Reality                                                                               |
| ----------------------------------- | ------------------------------------------------------------------------------------- |
| "Standard `for` is fine"            | Transpiles to `while` — 2-100x slower. Use `$range()`.                                |
| "Arrays are natural TypeScript"     | TSTL adds `[i + 1]` on every indexed access. Use `LuaTable`.                          |
| "Map is more familiar"              | `Map` is a heavy polyfill. `LuaMap` is a raw table.                                   |
| "Classes are cleaner"               | Classes are 12x slower method dispatch. Use interfaces.                               |
| "`continue` works in TS"            | Compile error in Lua 5.1. Invert the condition.                                       |
| "Spread is readable"                | `__TS__ObjectAssign` allocates 2 tables per call. Mutate in place.                    |
| "One allocation won't matter"       | At 60fps × 100 entities = 6,000 allocations/second. It matters.                       |
| "I'll optimize later"               | TSTL performance cliffs are structural. Fix the pattern, not the hot path.            |
| "`inline` polyfills are simpler"    | Duplicated across every file. Use `require-minimal`.                                  |
| "These callbacks are fine"          | Each callback in a loop = closure allocation = GC pressure.                           |
| "`\| 0` truncates to int"           | Bitwise OR is a **compile error** in Lua 5.1. Use `math.floor()`.                     |
| "I'll use empty-if for no-continue" | `if (x === undefined) {} else { body }` — just write `if (x !== undefined) { body }`. |
| "Promises are standard JS"          | `__TS__Promise` polyfill with wrong execution order. Use coroutines.                  |
| "Setting key to undefined is fine"  | It **deletes** the key in Lua. Use a sentinel value.                                  |

## Verification

**MANDATORY before completing any task:**

```bash
npx tstl              # Transpile first — catches continue, bitwise, and other Lua 5.1 errors
```

Then run the gates the project exposes: read the `scripts` in `package.json` and run its typecheck,
lint/format, and test scripts, whatever they are named. Tests always run separately. If no script
covers type checking, fall back to `npx tsc --noEmit`.

Inspect generated `.lua` files for `while` loops (should be `for`), `__TS__Class` (should be plain
tables), and `__TS__New(Map)` (should be raw `{}`). **Task is NOT complete until output Lua looks
like code an expert would write.**
