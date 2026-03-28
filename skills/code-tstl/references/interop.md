# TSTL Interop Patterns

- [@noSelf and this: void](#noself-and-this-void)
- [LuaMultiReturn and $multi()](#luamultireturn-and-multi)
- [External Lua Module Declarations](#external-lua-module-declarations)
- [Registering Global Callbacks](#registering-global-callbacks)

## `@noSelf` and `this: void`

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

## `LuaMultiReturn` and `$multi()`

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

## External Lua Module Declarations

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

## Registering Global Callbacks

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
