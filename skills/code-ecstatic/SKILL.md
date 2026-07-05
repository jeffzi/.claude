---
name: code-ecstatic
description: >
  Use when writing game code with ecstatic ECS imports (`from "ecstatic"`). Use when you see
  `get(storage, id, Component)` instead of SoA column access, `each(storage, (id) => ...)` instead
  of `(arch, i, entity)`, or `Map`/class-based ECS patterns in a TSTL ecstatic project. Not for
  plugin development — use code-tstl-plugin. For TSTL constraints (no continue, $range, LuaMap),
  also load code-tstl.
user-invocable: false
model: sonnet
effort: medium
---

# ecstatic — ECS Game Code

## Prerequisite — MANDATORY

**STOP. Load `Skill(code-tstl)` now** if not already loaded. ecstatic targets Lua 5.1 via TSTL.
Without code-tstl loaded, you will emit invalid Lua: standard `for` loops instead of `$range()`,
`Map`/`Set` instead of `LuaMap`/`LuaSet`, `continue` statements, and other compile errors. If the
skill fails to load, continue without it — but use `$range()` for all numeric loops and avoid
`Map`/`Set`/`continue`/bitwise operators.

**Core principle:** ecstatic stores component data in Structure-of-Arrays (SoA). Inside `each()`,
access fields as `arch.Position.x[i]` — never use `get()`/`set()` per-entity in hot loops.

## API Cheat Sheet

All imports from `"ecstatic"`. `Archetype` and `EntityId` are ambient types (no import needed).

### Schema

| Function     | Signature                                           | Returns                      |
| ------------ | --------------------------------------------------- | ---------------------------- |
| `component`  | `component(name, fields?)`                          | `Component<N,T>` or `Tag<N>` |
| `components` | `components({ Name: { field: default }, Tag: {} })` | mapped descriptors           |

Tags = empty `{}`. Data components = `{ field: default }`.

### Archetype Definition

```typescript
interface Enemy extends Archetype<
  [typeof Position, typeof Health],       // required components
  [typeof Stunned, typeof OnFire]         // optional components (tags or data)
> {}
```

The interface is type-only. `register<Enemy>(world)` allocates per-world SoA storage. The TSTL
plugin reads the type parameters at compile time.

### World

| Function        | Signature                  | Returns        |
| --------------- | -------------------------- | -------------- |
| `create_world`  | `create_world()`           | `World`        |
| `register`      | `register<A>(world)`       | `StorageOf<A>` |
| `get_storage`   | `get_storage(world, arch)` | `StorageOf<A>` |
| `destroy_world` | `destroy_world(world)`     | `void`         |

### Lifecycle

| Function       | Signature                                        | Returns      |
| -------------- | ------------------------------------------------ | ------------ |
| `spawn`        | `spawn(storage, overrides?)`                     | `EntityId`   |
| `spawn_many`   | `spawn_many(storage, count, overrides?, out?)`   | `EntityId[]` |
| `despawn`      | `despawn(storage\|world, id)`                    | `void`       |
| `despawn_many` | `despawn_many(storage, ids?)` or `(world, ids?)` | `void`       |
| `alive`        | `alive(storage\|world, id)`                      | `boolean`    |

Stale IDs: `despawn` = silent no-op, `alive` = returns false, all others = error.

### Optional State

| Function       | Signature                                                  |
| -------------- | ---------------------------------------------------------- |
| `enable`       | `enable(storage, id, comp, values?)` or record form        |
| `enable_many`  | `enable_many(storage, ids, overrides)` or `(storage, ovr)` |
| `disable`      | `disable(storage, id, comp)` or `(storage, id, [comps])`   |
| `disable_many` | `disable_many(storage, ids, comps)` or `(storage, comps)`  |
| `has`          | `has(storage, id, comp)` or `(storage, id, [comps])` → ALL |
| `has_any`      | `has_any(storage, id, [comps])` → AT LEAST ONE             |

Resume semantics: `disable` + `enable` without overrides = pause/resume (data survives).

### Field Access (outside iteration)

| Function | Signature                                            |
| -------- | ---------------------------------------------------- |
| `get`    | `get(storage, id, Position.x)` → value               |
| `get`    | `get(storage, id, [Position.x, Position.y])` → multi |
| `set`    | `set(storage, id, Position.x, 42)`                   |
| `set`    | `set(storage, id, { Position: { x: 10 } })`          |

Use `get`/`set` for single-entity access outside loops. Inside `each()`, use SoA columns directly.

### Iteration

| Function    | Signature                                       |
| ----------- | ----------------------------------------------- |
| `each`      | `each(storage, [filter,] fn)`                   |
| `each_many` | `each_many([storage1, storage2], [filter,] fn)` |
| `query`     | `query(world, comps_or_filter, fn)`             |

**Callback shape: `(arch, i, entity) => void`** — NOT `(id) => void`, NOT `(entity) => void`.

### Resources

| Function         | Signature                                |
| ---------------- | ---------------------------------------- |
| `resource`       | `resource(name, defaults)`               |
| `get_resource`   | `get_resource(world, res)` → mutable ref |
| `set_resource`   | `set_resource(world, res, partial)`      |
| `reset_resource` | `reset_resource(world, res)`             |

### Relationships

| Function        | Signature                                          |
| --------------- | -------------------------------------------------- |
| `relation`      | `relation(name, constraints?, defaults?)`          |
| `link`          | `link(world, id, rel, target, values?)`            |
| `unlink`        | `unlink(world, id, rel)` (optional relations only) |
| `get_target`    | `get_target(world, id, rel)` → id or undefined     |
| `query_sources` | `query_sources(world, rel, target, [filter,] fn)`  |
| `get_sources`   | `get_sources(world, rel, target, out?)`            |
| `has_sources`   | `has_sources(world, rel, target)`                  |
| `count_sources` | `count_sources(world, rel, target)`                |

Use a plain EntityId field + `alive()` for forward-only references. Promote to `relation()` only
when you need reverse queries (`query_sources`, `get_sources`, `has_sources`, `count_sources`).

## The each() Callback — Critical Pattern

The #1 mistake: wrong callback shape. `each()` passes `(arch, i, entity)`, not `(id)`.

```typescript
// WRONG — will not compile or silently break
each(enemies, (id) => {
  get(enemies, id, Position);  // per-entity function call in a loop
});

// CORRECT — SoA column access
each(enemies, (arch, i, entity) => {
  const x = arch.Position.x[i];    // direct array index, zero overhead
  const hp = arch.Health.hp[i];
  arch.Position.x[i] += arch.Velocity.vx[i] * dt;

  if (hp <= 0) {
    despawn(enemies, entity);  // despawn-safe (reverse iteration)
  }
});
```

**What `arch`, `i`, `entity` are:**

- `arch` — the SoA storage. `arch.Position.x` is a `number[]`, `arch.Position.x[i]` is the value.
- `i` — dense index into all parallel arrays. Valid only inside this callback.
- `entity` — packed EntityId. Pass to `despawn()`, `enable()`, `alive()`, etc.

**Filtered iteration** — use `{ all?, any?, none? }` with optional components:

```typescript
each(enemies, { all: [OnFire], none: [Stunned] }, (arch, i, entity) => {
  arch.Health.hp[i] -= 5 * dt;  // only burning, non-stunned enemies
});
```

## Archetype Definition Pattern

```typescript
const { Position, Velocity, Health, Stunned, OnFire } = components({
  Position: { x: 0, y: 0 },
  Velocity: { vx: 0, vy: 0 },
  Health: { hp: 100, max_hp: 100 },
  Stunned: {},    // tag — 0-field, boolean flag via bitmask
  OnFire: {},     // tag
});

interface Enemy extends Archetype<
  [typeof Position, typeof Velocity, typeof Health],  // required
  [typeof Stunned, typeof OnFire]                     // optional
> {}

const world = create_world();
const enemies = register<Enemy>(world);
```

**Never use `typeof Position` etc. as interface field types.** The archetype is declared via the
`Archetype<Required, Optional>` generic, not as an object type.

## Game Patterns

### System = plain function

ecstatic has no system concept. A system is a function that calls `each()` or `query()`:

```typescript
export function movement_system(world: World): void {
  const dt = get_resource(world, Time).dt;
  query(world, [Position, Velocity], (arch, i) => {
    arch.Position.x[i] += arch.Velocity.vx[i] * dt;
    arch.Position.y[i] += arch.Velocity.vy[i] * dt;
  });
}
```

### Game loop = ordered function calls

```typescript
function update(world: World, dt: number): void {
  set_resource(world, Time, { dt });
  input_system(world);
  movement_system(world);
  combat_system(world);
  death_system(world);
  cleanup_system(world);
}
```

Order = causality. If A writes data B reads, A runs first.

### Optionals as state machines

Tags as exclusive states. Disable old, enable new:

```typescript
each(enemies, { all: [Idle] }, (arch, i, entity) => {
  if (target_in_range(arch, i)) {
    disable(enemies, entity, Idle);
    enable(enemies, entity, Attacking);
  }
});
```

### Cooldown timer (data-carrying optional)

```typescript
const Cooldown = component("Cooldown", { remaining: 0 });
// Declare as optional on archetype

enable(players, entity, Cooldown, { remaining: 2.0 });

each(players, { all: [Cooldown] }, (arch, i, entity) => {
  arch.Cooldown.remaining[i] -= dt;
  if (arch.Cooldown.remaining[i] <= 0) {
    disable(players, entity, Cooldown);
  }
});
```

### Deferred despawn (Dead flag pattern)

Mark dead, exclude from gameplay, sweep at end of frame:

```typescript
const Dead = component("Dead");  // optional tag on every dieable archetype

// Kill site: flag, don't despawn
each(enemies, (arch, i, entity) => {
  if (arch.Health.hp[i] <= 0) enable(enemies, entity, Dead);
});

// Gameplay: exclude dead
each(enemies, { none: [Dead] }, (arch, i) => { /* ... */ });

// End of frame: cleanup sweep (per-archetype)
each(enemies, { all: [Dead] }, (arch, i, entity) => {
  // release foreign handles here (go.delete, etc.)
  despawn(enemies, entity);
});

// Cross-archetype deferred list: use despawn(world, id) — not despawn(storage, id)
// despawn(world, id) resolves the entity's storage internally.
```

### Entity links (forward-only references)

```typescript
const Target = component("Target", { entity_id: 0 });

each(missiles, (arch, i, entity) => {
  const target_id = arch.Target.entity_id[i] as EntityId;
  if (!alive(world, target_id)) {
    despawn(missiles, entity);
    return;
  }
  // steer toward target...
});
```

### Relations (when you need reverse queries)

```typescript
const Targets = relation("Targets", [Position]);

// In archetype: required or optional
interface Missile extends Archetype<
  [typeof Position, typeof Velocity, typeof Targets],
  [typeof Stunned]
> {}

// Link
link(world, missile_id, Targets, enemy_id);

// Forward: get target
const target = get_target(world, missile_id, Targets);
if (target !== undefined) { /* alive */ }

// Reverse: find all missiles targeting an enemy
query_sources(world, Targets, enemy_id, (storage, i, missile) => {
  // retarget, detonate, etc.
});
```

### Resources for global state

```typescript
const Time = resource("Time", { dt: 0, elapsed: 0 });
const Stats = resource("Stats", { kills: 0, score: 0 });

set_resource(world, Time, { dt: delta });
const time = get_resource(world, Time);  // mutable ref

reset_resource(world, Stats);  // restore defaults each frame
```

## Common Mistakes

| Mistake                                            | Fix                                                                  |
| -------------------------------------------------- | -------------------------------------------------------------------- |
| `each(storage, (id) => ...)`                       | `each(storage, (arch, i, entity) => ...)`                            |
| `get(storage, id, Position)` inside each loop      | `arch.Position.x[i]` — direct SoA access                             |
| `interface E { Position: typeof Position }`        | `interface E extends Archetype<[typeof Position], [...]> {}`         |
| `register(world, { Position, Health })`            | `register<Enemy>(world)` — type param, no value arg                  |
| `for...of` on arrays                               | `$range()` — `for...of` uses ipairs, slower than numeric for         |
| `deferredList.length = 0` to clear array           | Use count variable: `despawn_count = 0` (Lua has no `.length` set)   |
| `Math.sqrt(...)` in tight loop                     | `const sqrt = Math.sqrt` — localize before loop (TSTL/Lua)           |
| `new Map()` for event queues                       | `new LuaMap()` or allocation-free dense queue                        |
| Storing `i` outside callback                       | Store `entity` (EntityId) — `i` is ephemeral, invalidated by despawn |
| `alive(enemyStorage, missileId)` (wrong storage)   | `alive(world, id)` — world form works across archetypes              |
| Missing `alive()` check on stored EntityId         | Always check `alive()` before using a stored reference               |
| `has(storage, id, Comp)` inside each for filtering | Use `each(storage, { all: [Comp] }, ...)` — bitmask filter           |

## Project Layout

```text
src/
  schema.ts             components, tags, archetypes (shared vocabulary)
  main.ts               world setup, update loop
  systems/
    movement.ts         one system per file, exports one function
    combat.ts
    cleanup.ts
```

Components and archetypes in `schema.ts`. Systems import from schema. `update()` calls systems in
order. See docs/cookbook.md for full layout guidance.

## Spawn Overrides

```typescript
// Defaults only
spawn(enemies);

// Override required component fields
spawn(enemies, { Position: { x: 10, y: 20 } });

// Enable optional at spawn time
spawn(enemies, { Shield: true });              // with defaults
spawn(enemies, { Shield: { hp: 200 } });       // with overrides
spawn(enemies, { Stunned: true, OnFire: true }); // multiple optionals
```
