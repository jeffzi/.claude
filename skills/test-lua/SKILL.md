---
name: test-lua
description: >
  Use when writing Lua tests with busted. Apply for assertions, spies/stubs, test isolation,
  before_each/setup patterns, coverage with luacov, or any *_test.lua files. Not for production
  Lua code — use code-lua for that.
paths: "**/*_test.lua, **/spec/**/*.lua"
user-invocable: false
model: sonnet
effort: medium
---

# Lua Testing with Busted

**Core principle:** Test behavior, not implementation. Every test follows Arrange-Act-Assert.

**Also apply:** `code-lua` rules. Exception: test helper functions don't need full LuaLS
annotations.

## Mandatory Rules

### 1. Arrange-Act-Assert Structure

```lua
-- BAD: mixed up
it("creates player", function()
   assert.are_equal(100, PlayerManager.new("test").health)
   local p = PlayerManager.new("other")
   assert.is_true(p:is_alive())
end)

-- GOOD: clear AAA with blank-line separators
it("creates player with default health", function()
   local name = "test"

   local player = PlayerManager.new(name)

   assert.are_equal(100, player.health)
end)
```

### 2. Descriptive Test Names

Format: `<unit> <when condition> <expected outcome>`

```lua
it("move_to when target is out of bounds clamps to boundary", ...)
it("take_damage when health reaches zero marks player as dead", ...)
```

One `describe` per module. Flat structure — no nested `describe` blocks.

### 3. `are_same` Over `are_equal` for Tables

`are_equal` checks reference identity for tables. `are_same` does deep comparison — use it as your
default for table assertions.

```lua
-- BAD: passes only if same reference
assert.are_equal({ 1, 2, 3 }, result)  -- FAILS even if values match

-- GOOD: deep comparison
assert.are_same({ 1, 2, 3 }, result)
```

Reserve `are_equal` for primitives (numbers, strings, booleans) and intentional reference checks.

### 4. Use `before_each` for Shared Setup

Isolation over speed. Prefer `before_each` (runs per test) over `setup` (runs once per describe).

```lua
-- BAD: shared mutable state across tests
describe("Inventory", function()
   local inv = Inventory.new()  -- shared, mutations leak

   it("adds item", function()
      inv:add("sword")
      assert.are_equal(1, inv:count())
   end)

   it("starts empty", function()
      assert.are_equal(0, inv:count())  -- FAILS: leaked from previous test
   end)
end)

-- GOOD: fresh state per test
describe("Inventory", function()
   local inv

   before_each(function()
      inv = Inventory.new()
   end)

   it("adds item", function()
      inv:add("sword")
      assert.are_equal(1, inv:count())
   end)

   it("starts empty", function()
      assert.are_equal(0, inv:count())  -- passes
   end)
end)
```

Use `setup`/`teardown` only for truly expensive one-time operations (file I/O, process spawning).

### 5. Generate Parameterized Tests at Describe Level

Loops **inside** an `it` block hide failures. Generate separate `it` blocks instead.

```lua
-- BAD: loop inside test — stops at first failure, no per-case reporting
it("rejects invalid input", function()
   for _, input in ipairs({ nil, "", 0 }) do
      assert.has_error(function() validate(input) end)
   end
end)

-- GOOD: each case is a separate test
for _, case in ipairs({
   { input = nil, desc = "nil" },
   { input = "", desc = "empty string" },
   { input = 0, desc = "zero" },
}) do
   it("validate rejects " .. case.desc, function()
      assert.has_error(function() validate(case.input) end)
   end)
end
```

When parameterization is overkill (2-3 values on the same code path), just write separate `assert`
calls — no loop needed.

### 6. MVP Tests — Minimum Tests, Maximum Coverage

```lua
-- BAD: separate tests for same code path
it("rejects nil", function()
   assert.has_error(function() fn(nil) end)
end)
it("rejects empty string", function()
   assert.has_error(function() fn("") end)
end)

-- GOOD: merge related validations
it("rejects invalid input", function()
   assert.has_error(function() fn(nil) end)
   assert.has_error(function() fn("") end)
end)
```

| Merge when                            | Keep separate when    |
| ------------------------------------- | --------------------- |
| Same code path, different inputs      | Different code paths  |
| Related edge cases (nil, empty, zero) | Complex setup differs |
| Same behavior across APIs             | Tests need isolation  |

### 7. Mock at Boundaries Only

```lua
-- BAD: mocking internal function
stub(parser, "_normalize")

-- GOOD: mock the external dependency
stub(http_client, "get").returns({ status = 200, body = "{}" })
```

Always revert spies/stubs in `after_each` to prevent leaks:

```lua
after_each(function()
   -- revert all stubs/spies created in this scope
   http_client.get:revert()
end)
```

## Assertion Quick Reference

| Pattern               | Assertion                                                                  |
| --------------------- | -------------------------------------------------------------------------- |
| Equality (primitives) | `assert.are_equal(expected, actual)`                                       |
| Deep table comparison | `assert.are_same(expected, actual)`                                        |
| Truthy/falsy          | `assert.is_true(val)` / `assert.is_false(val)`                             |
| Nil checks            | `assert.is_nil(val)` / `assert.is_not_nil(val)`                            |
| Error thrown          | `assert.has_error(fn)` / `assert.has_error(fn, "msg")`                     |
| No error              | `assert.has_no_error(fn)`                                                  |
| String contains       | `assert.matches("pattern", str)`                                           |
| Type check            | `assert.is_number(val)` / `assert.is_string(val)` / `assert.is_table(val)` |
| Near (floats)         | `assert.is_near(expected, actual, tolerance)`                              |

**Argument order:** `expected` first, then `actual`. Consistent with busted convention.

**Underscores, not dots:** `assert.are_equal()` not `assert.are.equal()`.

## Spy/Stub Quick Reference

| Need to...                      | Use                                         |
| ------------------------------- | ------------------------------------------- |
| Track calls to existing method  | `spy.on(obj, "method")`                     |
| Replace with noop + track calls | `stub(obj, "method")`                       |
| Replace with custom return      | `stub(obj, "method").returns(value)`        |
| Replace all methods             | `mock(obj)`                                 |
| Check called                    | `assert.spy(s).was_called()`                |
| Check called N times            | `assert.spy(s).was_called(n)`               |
| Check call args                 | `assert.spy(s).was_called_with(arg1, arg2)` |
| Check not called                | `assert.spy(s).was_not_called()`            |
| Restore original                | `s:revert()`                                |

## Pitfalls

| Trap                               | Instead                                                        |
| ---------------------------------- | -------------------------------------------------------------- |
| `assert.are_equal()` for tables    | `assert.are_same()` — deep comparison                          |
| `assert.are.equal()` (dots)        | `assert.are_equal()` (underscores)                             |
| `setup` for mutable state          | `before_each` — fresh state per test                           |
| Forgetting `spy:revert()`          | Always revert in `after_each`                                  |
| Loops inside `it` blocks           | Generate `it` blocks at describe level                         |
| `assert.is_true(x)` for nil check  | `assert.is_not_nil(x)` — `is_true` fails on non-boolean truthy |
| Shared tables across tests         | Create new tables in `before_each`                             |
| Testing private functions directly | Test through public API                                        |
| Mocking internal modules           | Mock at system boundaries (I/O, HTTP, DB)                      |
| Interdependent test order          | Each test sets up its own context                              |

## Rationalizations

| Excuse                                  | Reality                                                      |
| --------------------------------------- | ------------------------------------------------------------ |
| "Mocking internals is faster"           | You're testing implementation, not behavior.                 |
| "Loop is cleaner than generating tests" | Generated tests show all cases, loop stops at first failure. |
| "`setup` is fine, tests don't mutate"   | Until they do. `before_each` prevents surprise coupling.     |
| "`are_equal` works for this table"      | It checks reference identity. `are_same` checks values.      |
| "Spy cleanup isn't needed here"         | Leaked spies cause cascading failures in other tests.        |

## Verification

**MANDATORY before completing any task:**

```bash
luacheck .                  # Lint
llscheck --checklevel Hint  # Types
busted                      # Tests
busted --coverage && luacov # Coverage (if .luacov exists)
```

**Task is NOT complete until all pass.**
