---
name: test-rust
description: >
  Use when writing Rust tests with cargo test or cargo-nextest. Apply for #[cfg(test)] modules,
  integration tests in tests/, doctests, rstest parametrization and fixtures, proptest, insta
  snapshots, mockall or hand-rolled fakes, #[tokio::test] async tests, timing-dependent or flaky
  tests, coverage gaps, or any tests/*.rs files. Not for production Rust patterns —
  use code-rust for that.
user-invocable: false
---

# Rust Testing

**This skill extends `Skill(test-core)`.** `test-core` is the primary entry point; this skill is
loaded by `test-core` based on the rules-file dispatch table.

**Load `Skill(code-rust)` and apply its rules.** Exception: test code may `.unwrap()`, `.expect()`,
index, and `panic!`; a `#[cfg(test)]` module in a crate that denies them opens with
`#![allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing, clippy::panic)]`.
Test-only crates (`rstest`, `pretty_assertions`, `tempfile`, `wiremock`, ...) are added to
`[dev-dependencies]` when first needed.

## Domain Skill Detection

No overlays yet.

## Layout

| Test kind    | Location                                                              | Can see         | Runner              |
| ------------ | --------------------------------------------------------------------- | --------------- | ------------------- |
| Unit         | `#[cfg(test)] mod tests { use super::*; }` in-file                    | private items   | `cargo nextest run` |
| Integration  | `tests/<feature>.rs`                                                  | public API only | `cargo nextest run` |
| Doctest      | `/// # Examples` on public items                                      | public API only | `cargo test --doc`  |
| Compile-fail | `tests/compile_fail.rs` driver + `tests/ui/*.rs` cases via `trybuild` | public API only | `cargo nextest run` |
| Benchmark    | `benches/*.rs` via `criterion`                                        | public API only | `cargo bench`       |

## Mandatory Rules

### 1. Private Items: A Narrow Exception to `test-core` Rule 3

Rust's privacy unit is the module, so `mod tests` sees every private item in its file. That access
is a deliberate Rust-specific exception, bounded three ways:

- **The public surface is proven through public calls.** Every behavior reachable from a `pub` item
  is tested by calling that `pub` item — from `tests/` or from `mod tests`. Private tests never
  substitute for that.
- **A private test asserts an outcome, never restates the body.** Testing a private helper is
  justified for intricate internal invariants (a parser, a state machine, an unsafe helper) whose
  failure modes the public API cannot pin down individually.
- **Never assign private fields to Arrange.** State is built through the constructor or public
  methods. If the state you need is unreachable that way — a clock, a store, a counter — the seam is
  missing. Adding it (a `with_clock` constructor, an injected `Store`) is a production change:
  propose it as a finding, never apply it silently and never reach past the API instead. Tests
  written against the proposed seam say so in the report.

```rust
// BAD: pads coverage by restating the implementation of a private fn
#[test]
fn refill_adds_elapsed_times_rate() {
    let mut rl = limiter(4);
    rl.tokens = 2;
    rl.last = Instant::now() - Duration::from_secs(1);
    rl.refill();
    assert_eq!(rl.tokens, 6);
}

// GOOD: same code path through the public API; FakeClock is a shared handle (Rc<Cell<Instant>>)
// behind the proposed `with_clock` seam
#[test]
fn try_acquire_when_one_second_elapsed_refills_at_rate() {
    let clock = FakeClock::default();
    let mut rl = RateLimiter::with_clock(10, 4, Box::new(MemStore::default()), clock.clone());
    rl.try_acquire("k", 8).unwrap();

    clock.advance(Duration::from_secs(1));

    assert_eq!(rl.try_acquire("k", 6), Ok(()));
}
```

### 2. Deterministic Time and Randomness

No `std::thread::sleep`, and wall time (`Instant::now()`, `SystemTime::now()`) is read at most once,
to seed a fake clock, never in an Act or Assert. Inject a clock (a trait object or `fn() ->
Instant`) and drive it. Tokio-specific setup:
[references/rust-test-tooling.md](references/rust-test-tooling.md#async-and-tokio).

Seed every RNG (`StdRng::seed_from_u64(42)`).

### 3. Parametrize With `rstest`, One Code Path per Test

Same code path with varying inputs is one `#[rstest]` with `#[case]` rows, never a loop and never
one `#[test]` per value. Shared setup is a `#[fixture]` fn, injected by argument name. `rstest`
composes with `#[tokio::test]`: put `#[rstest]` first.

```rust
#[rstest]
#[case("a:b", ("a", "b"))]
#[case("a", ("a", ""))]
#[case("a:b:c", ("a", "b:c"))]
fn parse_key_when_split_on_first_colon_returns_prefix_and_rest(#[case] key: &str, #[case] expected: (&str, &str)) {
    ...
}
```

Distinct outcomes (`Ok` vs a specific `Err` variant) on the same path stay in one case table when
the expected value is expressible as data; otherwise split by outcome, not by input.

### 4. Fakes at Boundaries, `mockall` Sparingly

The default test double is a hand-rolled fake. `#[automock]` / `mock!` is for wide boundary traits
only — never for internal logic, and never with `.times(n)` assertions; assert the outcome.
Implementation and per-boundary tool table:
[references/rust-test-tooling.md](references/rust-test-tooling.md#test-doubles-by-boundary).

### 5. Assertions

- `assert_eq!` with `pretty_assertions` for structs and collections.
- `assert!(matches!(result, Err(LimitError::Exhausted { .. })))` for enum variants whose payload is
  irrelevant; `assert_eq!` on the full value when it matters.
- Snapshot, property-based, and panic-contract tools:
  [references/rust-test-tooling.md](references/rust-test-tooling.md#assertion-tools).
- A test that chains fallible setup returns `Result<(), E>` and uses `?` instead of `.unwrap()`
  ladders.

### 6. Naming

`fn <function>_when_<condition>_<expected>()` in snake case, including inside `mod tests`.
Integration test files are named by feature, not `test1.rs`.

## Verification

Verification commands: see `code-rust` § Verification. Two test-side traps: `clippy` lints test code
only with `--all-targets`, and `cargo nextest run` skips doctests, so `cargo test --doc` runs beside
it. `cargo llvm-cov --all-features` when the project has a coverage gate.

## Red Flags

STOP and re-check if you see any of these in test code:

- A struct field assigned directly in Arrange — state is built through constructors or public
  methods (Rule 1).
- `Instant::now()` or `SystemTime::now()` in an Act or Assert — inject a clock (Rule 2).
- `std::thread::sleep` anywhere in a test — pause time or inject a fake clock (Rule 2).
- `.times(n)` on a `mockall` double — assert the outcome, not the wiring (Rule 4).
- `tokio::spawn` whose `JoinHandle` is never awaited — a panic inside it silently passes
  ([Async](references/rust-test-tooling.md#async-and-tokio)).
- `cargo test` reported green without `clippy --all-targets` and `cargo test --doc` (Verification).

## Rationalizations

| Excuse                                            | Reality                                                                                  |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| "It's private, only `mod tests` can reach it"     | Reach the same path through the `pub` caller. Private tests pin invariants.              |
| "The reviewer told me to test it directly"        | Authority does not lift Rule 1. Test the parser directly; drive `refill` via its caller. |
| "Coverage attributes the hits either way"         | Coverage from a restated body is false coverage. It proves nothing.                      |
| "The sleep never undershoots"                     | Wall-clock time is slow on every run and flaky under load. Pause or inject.              |
| "Setting the field directly is the fastest setup" | It couples the test to struct layout. Add the seam; report it if you can't.              |
| "`mockall` is already a dev-dependency"           | Presence is not a reason. Fake unless the boundary trait is wide.                        |
| "`cargo test` was green"                          | Did clippy run with `--all-targets`? Did `cargo test --doc` run under nextest?           |
