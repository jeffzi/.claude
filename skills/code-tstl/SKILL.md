---
name: code-tstl
description: >
  Use when writing TypeScript-to-Lua (TSTL) code targeting Lua 5.1. Use when transpiling TypeScript
  to Lua for game engines (LÖVE, Defold, WoW, MA Lighting), embedded Lua, or any TSTL project.
  Use when you see "while loop" where a numeric for should be, or Map/Set where LuaMap/LuaSet
  belongs - these are symptoms this skill applies.
---

# TSTL - TypeScript-to-Lua for Lua 5.1

**Core principle:** Write TypeScript that generates the Lua code an expert would write by hand.
Every idiomatic TypeScript pattern has a TSTL-specific cost — know it and avoid it in hot paths.

**REQUIRED BACKGROUND:** Load `code-ts` first for general TypeScript rules. This skill adds
TSTL-specific patterns on top.

## Domain Skill Detection

When reviewing or writing TSTL code, check for plugin development patterns. If detected, load the
corresponding skill:

| Detection pattern                                                             | Skill to load      |
| ----------------------------------------------------------------------------- | ------------------ |
| `import * as tstl from "typescript-to-lua"` with `tstl.Plugin` implementation | `code-tstl-plugin` |

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

### Cache Math Functions as Locals

Global lookups through `_G` hash table are **~30% slower** per access than local register reads.

```typescript
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
const result: Position[] = [];
for (const i of $range(1, enemies.length)) {
  const e = enemies[i - 1];
  if (e.isAlive) { result.push(e.position); }
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

## Interop

### `@noSelf` and `this: void`

TSTL adds a hidden `self` parameter to all functions by default. Use `noImplicitSelf: true` in
tsconfig, or annotate explicitly:

```typescript
/** @noSelfInFile */  // at top of utility files

// Or per-function:
function process(this: void, x: number): number { return x * 2; }
```

**`noImplicitSelf` does NOT cover declarations or classes.** Even with `noImplicitSelf: true`,
ambient functions (`.d.ts`), interfaces, and class methods still get a `self` parameter. You must
always add `@noSelf` to declaration namespaces and `this: void` to declaration functions — the
tsconfig option only affects implemented (non-ambient) functions.

### `LuaMultiReturn` and `$multi()`

Lua functions return multiple values on the stack. Without `LuaMultiReturn`, TSTL wraps returns in a
table.

```typescript
/** @noSelf */
declare namespace mylib {
  function getPos(): LuaMultiReturn<[number, number]>;
}
const [x, y] = mylib.getPos();

// Returning multiple values from your own functions:
function findMinMax(this: void, arr: number[]): LuaMultiReturn<[number, number]> {
  let min = arr[0], max = arr[0];
  for (const v of arr) { if (v < min) min = v; if (v > max) max = v; }
  return $multi(min, max);
}
```

### External Lua Module Declarations

Use `.d.ts` files with `@noSelf` for existing Lua libraries:

```typescript
// mylib.d.ts
/** @noSelf */
declare namespace mylib {
  function doSomething(x: number): number;
}
```

Key annotations: `@noSelf` (dot-call, not colon-call), `@customConstructor` (bypass `__TS__New`),
`@noResolution` (prevent `require()` path rewriting).

When a Lua API uses a TypeScript reserved word (`new`, `delete`, `default`, etc.) as a function
name, use object-literal notation instead of `declare namespace`:

```typescript
// BAD: syntax error — "new" is a TS reserved word
// declare namespace pool { export function new(): Entity; }

// GOOD: object-literal notation
declare const pool: { new: (this: void) => Entity };
```

### Registering Global Callbacks

With `noImplicitGlobalVariables: true`, all declarations are `local` — host engines that expect
global callbacks (`OnStart`, `OnUpdate`, `love.update`, etc.) won't find them. Use `declare var` to
tell TSTL a global exists, then assign to it:

```typescript
// globals.d.ts — declare the shape the engine expects
declare var OnStart: (this: void) => void;
declare var OnUpdate: (this: void, dt: number) => void;

// main.ts — assign implementations (compiles to global assignment)
OnStart = () => { init(); };
OnUpdate = (dt) => { world.update(dt); };
```

For dynamic registration, use `globalThis`:

```typescript
function registerHandler<TArgs extends unknown[]>(
  name: string, handler: (this: void, ...args: TArgs) => void
): void {
  // @ts-ignore — intentional global assignment
  globalThis[name] = handler;
}
```

## Correctness Caveats

Silent behavioral differences between TypeScript and transpiled Lua — these won't error, they'll
just do the wrong thing:

| Caveat                             | JS behavior                       | Lua behavior                | Fix                                                          |
| ---------------------------------- | --------------------------------- | --------------------------- | ------------------------------------------------------------ |
| `undefined` vs `null`              | Distinct values                   | Both are `nil`              | Prefer `undefined`; never rely on the distinction            |
| Assign `undefined` to key          | Key exists with value `undefined` | Key is **deleted**          | Use sentinel (`-1`, `""`) if key must persist                |
| Boolean coercion: `0`, `""`, `NaN` | All falsy                         | All **truthy**              | Explicit comparisons: `x !== 0`, `x !== ""`, `x === x` (NaN) |
| `==` vs `===`                      | Loose vs strict equality          | Both compile to strict `==` | Always use `===` (enable `eqeqeq` lint rule)                 |
| `for...in` on arrays               | Iterates string indices           | **Forbidden**               | `$range()` or `for...of`                                     |
| `Array.fill(v, start, end)`        | Clamps `end` to array length      | Fills to `end` regardless   | Be explicit about bounds                                     |
| `Array.sort` stability             | Stable (ES2019+)                  | **Not guaranteed**          | Implement stable sort if equal-element order matters         |
| Key iteration order                | Insertion order (ES2015+)         | **Unspecified**             | Use arrays when order matters                                |
| `async`/`await` execution order    | Deferred (microtask queue)        | **Immediate** resolution    | Use coroutines instead (see Mandatory Rules)                 |

## Pitfalls

| Trap                             | Instead                                                         |
| -------------------------------- | --------------------------------------------------------------- |
| `for (let i = 0; ...)`           | `for (const i of $range(start, end))`                           |
| `new Map()` / `new Set()`        | `new LuaMap()` / `new LuaSet()`                                 |
| `class` for hot-path entities    | Interface + free functions                                      |
| `continue` in loops              | Invert condition                                                |
| `{...obj}` in loops              | Mutate in place                                                 |
| `.filter().map().reduce()` chain | Single `for` loop with `$range()`                               |
| `enum Foo { }`                   | `const enum Foo { }`                                            |
| `\|\|` for defaults              | `??` — Lua treats `0`, `""`, and `NaN` as truthy                |
| `splice()` in hot paths          | Swap-with-last + `pop()` for O(1) removal                       |
| `Math.fn()` in tight loops       | Cache as local: `const cos = Math.cos`                          |
| Building strings with `+=`       | Collect in array, `table.concat()` once                         |
| Regular `for-of` on arrays       | `$range()` — `for-of` uses `ipairs` (slower than numeric `for`) |

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
npx tstl              # Transpile — catches continue, bitwise, and other Lua 5.1 errors
npx tsc --noEmit      # Type checking (biome doesn't type-check)
npx biome check .     # Linting and formatting
npx vitest run        # If tests exist — always run separately
```

Inspect generated `.lua` files for `while` loops (should be `for`), `__TS__Class` (should be plain
tables), and `__TS__New(Map)` (should be raw `{}`). Lefthook manages git hooks. **Task is NOT
complete until output Lua looks like code an expert would write.**
