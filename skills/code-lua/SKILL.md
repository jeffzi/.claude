---
name: code-lua
description: >
  Use when writing Lua code for game development (LÖVE2D, Defold, WoW addons), Neovim
  plugins, or embedded scripting. Use when you think code is "too simple for types" or "just
  a prototype" - these are symptoms this skill applies. Not for TypeScript-to-Lua (TSTL)
  projects — use code-tstl. For Lua tests with busted, also load test-lua. Applies to *.lua
  files.
user-invocable: false
---

# Lua Coding

**This skill extends `Skill(code-core)`.** `code-core` is the primary entry point; this skill is
loaded by `code-core` based on the rules-file dispatch table.

**Core principle:** Every function gets type annotations.

## Formatting

- **Indentation:** 3 spaces (not tabs, not 2 or 4)
- **Line length:** 100 characters max
- **Trailing commas:** Always in multi-line tables

## Type Annotations

**ALWAYS add LuaLS/EmmyLua annotations.**

```lua
--- Return squared even numbers from input.
--- @param items number[] Input values.
--- @return number[]
local function process(items)
   local result = {}
   for i = 1, #items do
      local x = items[i]
      if x % 2 == 0 then result[#result + 1] = x ^ 2 end
   end
   return result
end
```

### Documentation Style

| Element   | Style           | Example                          |
| --------- | --------------- | -------------------------------- |
| Function  | Infinitive verb | _"Return the user's full name."_ |
| Parameter | Noun phrase     | _"User's given name."_           |

**Avoid:** third-person (_"Returns"_), articles (_"The first name"_).

**Internal functions:** Types + clear names suffice. Add prose only for non-obvious logic, side
effects, or public API.

## Naming Conventions

| Element             | Convention          | Example                    |
| ------------------- | ------------------- | -------------------------- |
| Variables/functions | `snake_case`        | `local player_score`       |
| Classes/modules     | `CamelCase`         | `local PlayerManager = {}` |
| Constants           | `UPPER_CASE`        | `local MAX_HEALTH = 100`   |
| Private members     | `_prefix`           | `self._internal_state`     |
| Boolean functions   | `is_`/`has_` prefix | `is_valid()`, `has_item()` |
| Metatables          | `*_mt` suffix       | `local Player_mt = {}`     |

## Pitfalls

| Trap                                     | Instead                                 |
| ---------------------------------------- | --------------------------------------- |
| `if x then` for nil check                | `if x ~= nil then`                      |
| `ipairs()` in performance-critical paths | `for i = 1, #t do`                      |
| Chained `..` with 4+ strings             | `table.concat()`                        |
| `require "mod"`                          | `require("mod")`                        |
| `local f = function()`                   | `local function f()`                    |
| Silent failures                          | Return `nil, err` for expected failures |
| Table creation in hot paths              | Reuse tables, reset fields              |
| `math.random` without seeding            | `math.randomseed(os.time())` at startup |

### Ternary Abuse

`a and b or c` is for **trivial defaults only**.

```lua
-- OK
local name = user_name or "guest"
local status = is_active and "online" or "offline"

-- BAD: arithmetic
local scale = (time > 0) and (min / time) or fallback

-- BAD: nested
local x = a and (b and c or d) or e

-- BAD: long expressions
local msg = player:is_alive() and player:get_name() or "unknown"
```

**If you pause to parse it, use if/else.**

### Localizing Globals in Hot Paths

**Global lookups in loops are slow.** Localize at file top.

```lua
-- File top: localize before any functions
local math_random = math.random

local function hot_loop(n)
   local total = 0
   for i = 1, n do
      total = total + math_random(100)
   end
   return total
end
```

**Must localize in loops:**

- `math.*` (`math.random`, `math.floor`, `math.sin`, etc.)
- `table.*` (`table.insert`, `table.sort`, `table.concat`)
- `string.*` (`string.format`, `string.sub`, `string.find`)
- Any function called per-iteration

**Naming:** `module_function` (e.g., `math_random`, `table_insert`)

## Rationalizations That Mean Failure

| Excuse                    | Reality                                           |
| ------------------------- | ------------------------------------------------- |
| "ipairs is more readable" | Readability doesn't matter if your code stutters. |
| "This table is temporary" | Temporary tables cause GC spikes. Reuse them.     |

## Verification

**MANDATORY before completing any task:**

```bash
luacheck .                  # Lint
llscheck --checklevel Hint  # Types
busted                      # Tests (if tests/ exists)
busted --coverage && luacov # Coverage (if .luacov exists)
```

**Task is NOT complete until all pass.**
