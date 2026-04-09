---
name: code-tstl-plugin
description: >
  Use when writing TypeScript-to-Lua (TSTL) plugins — visitor transforms, printer overrides,
  beforeTransform/afterPrint/beforeEmit hooks. Use when you see deep internal imports from
  typescript-to-lua/dist/*, context.transformExpression causing infinite recursion, or need to
  choose between plain-object and class-based plugin shapes. Not for general TSTL application
  code — use code-tstl.
user-invocable: false
model: sonnet
effort: medium
---

# TSTL Plugin Development

**Core principle:** Import from `typescript-to-lua` — never from internal `dist/` paths. Choose
plugin shape by complexity: plain objects for single-hook plugins, classes when you need the type
checker or cross-hook state. Always delegate via `super` transform methods.

**REQUIRED BACKGROUND:** Load `code-ts` for general TypeScript rules and `code-tstl` for Lua 5.1
constraints. This skill adds TSTL plugin-specific patterns on top.

## Mandatory Rules

### Import from Public API Only

```typescript
// BAD: internal paths break on minor TSTL updates
import * as lua from "typescript-to-lua/dist/LuaAST";
import { Plugin } from "typescript-to-lua/dist/transpilation/plugins";
import { TransformationContext } from "typescript-to-lua/dist/transformation/context";

// GOOD: single public import
import * as tstl from "typescript-to-lua";
```

Everything you need — `Plugin`, `LuaTarget`, factory functions (`tstl.createIdentifier`,
`tstl.createCallExpression`, etc.), type guards (`tstl.isStringLiteral`, `tstl.isCallExpression`,
etc.), AST types, `EmitHost`, `CompilerOptions`, `transpileVirtualProject` — is re-exported from the
top-level `typescript-to-lua` module.

### Use `superTransform*` — Never Bare `transform*`

```typescript
// BAD: calls YOUR visitor again → infinite recursion → stack overflow
const result = context.transformExpression(node);

// GOOD: calls previous plugin or default TSTL visitor
const result = context.superTransformExpression(node);
```

| Method                                   | Calls                                     |
| ---------------------------------------- | ----------------------------------------- |
| `context.superTransformExpression(node)` | Previous plugin or default visitor (safe) |
| `context.superTransformStatements(node)` | Previous plugin or default visitor (safe) |
| `context.transformExpression(node)`      | **Your own visitor** (infinite recursion) |
| `context.transformStatements(node)`      | **Your own visitor** (infinite recursion) |

### Choose Plugin Shape by Complexity

**Plain object** — single hook, no type checker, no cross-hook state:

```typescript
import * as tstl from "typescript-to-lua";

// Single-hook string processors, moduleResolution overrides
const plugin: tstl.Plugin = {
  beforeEmit(_program, _options, _emitHost, result) {
    for (const file of result) {
      file.code = file.code.replace(/____exports\.(\w+)/g, "$1");
    }
  },
};
export default plugin;
```

State that lives in module-scope closures is fine here — everything is visible at the top of the
file and a class wrapper adds indirection for zero gain.

**Class with `implements tstl.Plugin`** — visitors + type checker, or cross-hook state:

```typescript
import * as ts from "typescript";
import * as tstl from "typescript-to-lua";

class MyPlugin implements tstl.Plugin {
  private checker!: ts.TypeChecker;
  private stripDebug = false;

  // One-time setup: cache expensive lookups here, not in visitors
  beforeTransform(program: ts.Program, options: tstl.CompilerOptions): void {
    this.checker = program.getTypeChecker();
    this.stripDebug = process.env["STRIP_DEBUG"] === "1";
  }

  visitors: tstl.Visitors = {
    [ts.SyntaxKind.CallExpression]: (node: ts.CallExpression, context) => {
      // Type-aware decisions use this.checker
      // Cached config uses this.stripDebug (not re-read per call)
      return context.superTransformExpression(node);
    },
  };
}
export default new MyPlugin();
```

**What triggers the need for a class:**

- `ts.TypeChecker` — only available from `program.getTypeChecker()` in `beforeTransform`; you need
  somewhere to store it for visitors
- Cross-hook state — collect data in visitors, act on it in `afterPrint`
- Visitors + lifecycle hooks on the same plugin

### Cache Expensive Lookups in `beforeTransform`

```typescript
// BAD: re-reads env var on every visited node
visitors: {
  [ts.SyntaxKind.ExpressionStatement]: (node, context) => {
    if (process.env["STRIP_DEBUG"] === "1") { ... }  // N calls per compilation
  },
}

// GOOD: read once in beforeTransform, check cached flag in visitor
beforeTransform(program: ts.Program): void {
  this.stripDebug = process.env["STRIP_DEBUG"] === "1";
}
visitors: {
  [ts.SyntaxKind.ExpressionStatement]: (node, context) => {
    if (this.stripDebug) { ... }  // simple boolean check
  },
}
```

## Plugin Lifecycle (7 Hooks)

Execution order: `beforeTransform` → `visitors` → `printer` → `afterPrint` → `beforeEmit` →
`afterEmit` + `moduleResolution` (on demand).

| Hook               | Fires                   | Returns                | Use for                                          |
| ------------------ | ----------------------- | ---------------------- | ------------------------------------------------ |
| `beforeTransform`  | Once per compilation    | `Diagnostic[]` or void | Setup, type checker caching, config reads        |
| `visitors`         | Per matching TS node    | Lua AST node(s)        | TS→Lua AST transforms (core work)                |
| `printer`          | Per file                | `PrintResult`          | Custom Lua formatting (only one printer active!) |
| `afterPrint`       | After all files printed | `Diagnostic[]` or void | Post-print validation, cross-file checks         |
| `beforeEmit`       | After bundling          | `Diagnostic[]` or void | String-based rewrites, final output mutation     |
| `afterEmit`        | After disk write        | void                   | Side effects (logs, manifests)                   |
| `moduleResolution` | Per `require`           | `string` or undefined  | Custom import path mapping                       |

**Only one `printer` can be active** across all plugins — last one wins. Prefer AST transforms or
`beforeEmit` string manipulation when possible.

## Visitor Patterns

**Return types:** Expression visitors must return `tstl.Expression`. Statement visitors return
`tstl.Statement | tstl.Statement[] | undefined` (returning `undefined` erases the statement).

**Object-form with `priority`:** When you need to control visitor ordering within a single plugin,
use the object form: `{ priority: 1, transform(node, context) { ... } }`. Higher priority fires
first. The function form `(node, context) => { ... }` is shorthand with default priority.

### Pattern 1: Wrap-and-Modify (Most Common)

Delegate to default, then mutate the result:

```typescript
[ts.SyntaxKind.StringLiteral]: (node: ts.StringLiteral, context) => {
  const result = context.superTransformExpression(node);
  if (tstl.isStringLiteral(result) && result.value === "__VERSION__") {
    return tstl.createStringLiteral(this.version);
  }
  return result;
},
```

### Pattern 2: Conditional Stripping

Return `undefined` from statement visitors to erase code:

```typescript
[ts.SyntaxKind.ExpressionStatement]: (node: ts.ExpressionStatement, context) => {
  if (this.shouldStrip && isTargetCall(node.expression)) {
    return undefined;  // statement removed from output
  }
  return context.superTransformStatements(node);
},
```

### Pattern 3: String-Based Post-Processing (`beforeEmit`)

For simple rewrites, string manipulation in `beforeEmit` avoids AST complexity:

```typescript
beforeEmit(program: ts.Program, options: tstl.CompilerOptions,
           emitHost: tstl.EmitHost, result: tstl.EmitFile[]): void {
  for (const file of result) {
    file.code = file.code.replace(/____exports\.(\w+)/g, "$1");
  }
}
```

For Lua AST factory functions and type guards, see `references/lua-ast.md`.

## Testing with `transpileVirtualProject`

```typescript
import * as tstl from "typescript-to-lua";

function compile(source: string): string {
  const result = tstl.transpileVirtualProject(
    { "main.ts": source },
    {
      noHeader: true,
      luaPlugins: [{ plugin: new MyPlugin() }],
      noImplicitSelf: true,
      luaTarget: tstl.LuaTarget.Lua51,
      luaLibImport: tstl.LuaLibImportKind.None,
    },
  );
  const file = result.transpiledFiles.find((f) => f.outPath.endsWith("main.lua"));
  if (!file?.lua) {
    const msgs = result.diagnostics.map((d) => d.messageText).join("\n");
    throw new Error(`No Lua output.\n${msgs}`);
  }
  return file.lua;
}
```

**Key testing rules:**

- Use `tstl.LuaTarget.Lua51` and `tstl.LuaLibImportKind.None` — not string literals or `as any`
  casts
- Pass plugin as `{ plugin: new MyPlugin() }` (the `InMemoryLuaPlugin` shape)
- Assert both positive (code present) and negative (code stripped) expectations
- Check `result.diagnostics` is empty for success cases

## Plugin Composition

- Visitor chains execute in `luaPlugins` array order from `tsconfig.json`
- `superTransform*` calls the previous plugin in the chain, or the built-in visitor
- Plugin order matters: stripping plugins should run before optimization plugins
- All lifecycle hooks fire for every plugin in order
- Only **one printer** can be active (last one wins)

## Common Mistakes and Rationalizations

| Mistake                                         | What happens                                        | Instead                                                   |
| ----------------------------------------------- | --------------------------------------------------- | --------------------------------------------------------- |
| `import ... from "typescript-to-lua/dist/..."`  | Breaks on next minor TSTL update                    | `import * as tstl from "typescript-to-lua"`               |
| `context.transformExpression(node)`             | Calls YOUR visitor again — stack overflow           | `context.superTransformExpression(node)`                  |
| Class for a single-hook string processor        | Adds indirection for zero gain                      | Plain object — match shape to complexity                  |
| Plain object with visitors or type checker      | No place to store `TypeChecker` or cross-hook state | Class-based plugin with `beforeTransform` setup           |
| Reading env vars inside visitor body            | Re-reads on every matching node                     | Cache in `beforeTransform`                                |
| `luaLibImport: "none" as any` in tests          | Bypasses type safety for no reason                  | `luaLibImport: tstl.LuaLibImportKind.None`                |
| Comments explaining WHAT code does              | Noise — the code already says what                  | Comments explaining WHY the approach was chosen           |
| `node:` prefix missing on Node.js imports       | May resolve incorrectly                             | `import * as fs from "node:fs"`                           |
| Forgetting `return undefined` strips statements | Statement silently disappears from output           | Explicit — works for statement visitors only              |
| Using multiple printers across plugins          | Only one printer is active globally — last one wins | Prefer AST transforms or `beforeEmit` string manipulation |

## Verification

**MANDATORY before completing any task:**

```bash
npx tsc --noEmit         # Type checking (biome doesn't type-check)
npx biome check .        # Linting and formatting
npx vitest run           # Plugin unit tests — always run separately
```

Inspect test output Lua for correct transformations. Check that no `typescript-to-lua/dist/` imports
remain. Lefthook manages git hooks. **Task is NOT complete until tests pass and all imports use the
public API.**
