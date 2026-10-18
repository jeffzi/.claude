---
name: code-rust
description: >
  Use when writing any Rust code, regardless of perceived simplicity or prototyping context. Use
  when you think "just unwrap it for now", "clone to satisfy the borrow checker", or "wrap it in
  Arc<Mutex>" — these are symptoms this skill applies. Also use when choosing thiserror vs anyhow,
  writing unsafe blocks, tokio async code, Edition 2024 migrations, or clippy configuration. Not for
  scaffolding project tooling config — use /setup-rust. For tests, also load test-rust. Applies to
  *.rs files.
user-invocable: false
---

# Rust — Production-Quality Code

**This skill extends `Skill(code-core)`.** `code-core` is the primary entry point; this skill is
loaded by `code-core` based on the rules-file dispatch table.

Crate metadata: !`cargo metadata --no-deps --format-version 1 2>/dev/null | head -c 1500`

If the injection above is empty (no `Cargo.toml` in scope or `cargo` unavailable), read `Cargo.toml`
manually for: `edition` (assume 2024 when absent), `rust-version`, whether the crate is a library
(`[lib]`) or application (`[[bin]]` only), and the `[lints]` / `[workspace.lints]` tables. Several
rules below split on library vs application.

**Core principle:** Errors propagate as typed values, panics mark broken invariants only, and
ownership is restructured rather than cloned around.

## Mandatory Rules

### 1. Typed Errors in Libraries, Contextual Errors in Applications

**Library crate:** a `thiserror` enum per module or crate. `#[from]` / `#[source]` preserve the
chain; `#[error(transparent)]` wraps a single inner error. Never `Result<T, String>`, never `Box<dyn
Error>` in a public signature, never `format!` an inner error into a `String`. If `thiserror` is not
yet a dependency, add it — a hand-rolled `Display` + `Error::source` impl is boilerplate that drifts
on the next variant.

**Application crate:** `anyhow` (or `eyre`) with `.context("...")` at every fallible call; `main`
returns `anyhow::Result<()>`.

Public error enums carry `#[non_exhaustive]` — adding a variant is otherwise a breaking change.
Large `Err` payloads are boxed (`clippy::result_large_err`).

```rust
// BAD: stringly-typed, chain lost, callers cannot match
pub fn load(path: &String) -> Result<Config, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("read failed: {e}"))?;
    toml::from_str(&text).map_err(|e| e.to_string())
}

// GOOD: typed, chained, semver-safe
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ConfigError {
    #[error("failed to read {}", path.display())]
    Io { path: PathBuf, #[source] source: std::io::Error },
    #[error("invalid TOML in {}", path.display())]
    Parse { path: PathBuf, #[source] source: toml::de::Error },
    #[error("retries = {retries} exceeds {}", MAX_RETRIES)]
    RetriesTooHigh { retries: u32 },
}

/// # Errors
/// Returns [`ConfigError::Io`] if the file cannot be read, [`ConfigError::Parse`] if it is not
/// valid TOML, and [`ConfigError::RetriesTooHigh`] if `retries` exceeds [`MAX_RETRIES`].
pub fn load(path: impl AsRef<Path>) -> Result<Config, ConfigError> { ... }
```

### 2. No Panics on Library Code Paths

`.unwrap()`, `.expect()`, `panic!`, `todo!`, `unimplemented!`, `unreachable!`, and index syntax
`v[i]` do not appear on any path reachable from a library's public API. Use `?`, `.get(i)`,
`.ok_or(...)`, `let ... else`. In applications they are acceptable only in `main`-adjacent setup
where crashing is the correct response.

`expect("...")` is allowed only when an invariant _established in the surrounding code_ guarantees
success and the message states that invariant (`expect("len checked non-zero above")`). "Cannot fail
on an in-memory buffer" is a guess about a dependency, not a proof. A `JoinError` from
`spawn_blocking` / `JoinHandle` is a real failure (the task panicked or was cancelled) — map it into
the error enum, never `.expect()` it away. A silent fallback is the same bug in disguise:
`unwrap_or_default()`, `unwrap_or_else(|_| original)`, or `.ok()` on a fallible call discards the
error (`code-core` Rule 4); return the `Result`. A poisoned lock propagates as an error variant;
`PoisonError::into_inner` is acceptable only when the guarded data has no invariant a panic could
break, stated in a comment.

Library crates enable `clippy::unwrap_used`, `clippy::expect_used`, `clippy::indexing_slicing`,
`clippy::panic` (see [Lint Configuration](#lint-configuration)). Test modules opt out locally.

### 3. Restructure Ownership Instead of Cloning

`.clone()` is not a borrow-checker fix. Before cloning, try in order:

| Borrow-checker symptom                        | Restructure                                                                    |
| --------------------------------------------- | ------------------------------------------------------------------------------ |
| "borrowed value does not live long enough"    | Return an owned value, or run the work inside the borrow's scope               |
| Returning `&T` out of a `MutexGuard`          | Clone only `Copy`-like values; heap-owning `T` is stored as `Arc<T>`           |
| Two `&mut` into one struct                    | Split the struct, or take `&mut` to the fields separately                      |
| Closure needs `'static` for `spawn`           | Move the owned value in; `Arc` only if genuinely shared afterwards             |
| `String` param cloned to pass to another call | Take `&str` / `impl AsRef<str>` and borrow through                             |
| `Arc<Mutex<T>>` for state that is read-mostly | `Arc<RwLock<T>>`; immutable shared state is `Arc<T>`; a single owner is `&mut` |
| Producer/consumer through a shared lock       | A channel — the handoff is the ownership transfer                              |

### 4. API Boundary Types

A public signature is semver; `&String` today is a breaking change tomorrow. When a requested public
signature violates a row below, write the compliant one and report the change.

| Instead of                                                                | Use                                                                                                     |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `&String`, `&Vec<T>`, `&PathBuf`                                          | `&str`, `&[T]`, `impl AsRef<Path>`; `impl IntoIterator<Item = T>` for sequences (`clippy::ptr_arg`)     |
| Explicit lifetimes the compiler infers                                    | Elide them (`clippy::needless_lifetimes`)                                                               |
| By-value parameter that is only read                                      | Borrow it (`clippy::needless_pass_by_value`)                                                            |
| Pure value-returning `pub fn` without attribute                           | `#[must_use]`                                                                                           |
| Public type without derives                                               | `Debug` always; `Clone`, `PartialEq`, `Eq`, `Hash`, `Default` where they make sense                     |
| Bare `u64` for a domain id                                                | A newtype (`UserId(u64)`)                                                                               |
| Constructor with more than three optional fields                          | A builder                                                                                               |
| `pub` by default                                                          | `pub(crate)` by default; `pub` only on the curated surface, re-exported via `pub use` at the crate root |
| Public enum or constructor-built struct that downstream matches or builds | `#[non_exhaustive]` — not on plain all-`pub` data structs, where it breaks literals                     |
| Trait downstream must not implement                                       | The sealed-trait pattern                                                                                |
| `mod.rs`, glob imports outside tests                                      | `foo.rs` + `foo/`; explicit imports                                                                     |

### 5. Unsafe Is Audited at the Block

`// SAFETY:` before every `unsafe {}` block; `# Safety` on every `unsafe fn` and `unsafe impl`.
Crates containing `unsafe` enable `clippy::undocumented_unsafe_blocks`. Full patterns, the
`write_at` example, and application-vs-library `unsafe_code` lint guidance:
[references/unsafe-and-async.md](references/unsafe-and-async.md#unsafe-auditing).

### 6. Async: tokio, No Guards Across `.await`, No Blocking

No lock guards or `RefCell` borrows across `.await`; blocking I/O to `spawn_blocking`; every spawned
task joined or its handle stored. Full rules:
[references/unsafe-and-async.md](references/unsafe-and-async.md#async-tokio).

### 7. Documentation on Public Items

`///` on every public item, `//!` at crate and module level. Full rules (doc sections, intra-doc
links, `#[doc(hidden)]`):
[references/docs-and-verification.md](references/docs-and-verification.md#documentation-on-public-items).

## Modern Replacements

| Outdated                                | Use instead                                   |
| --------------------------------------- | --------------------------------------------- |
| `lazy_static!`, `once_cell::sync::Lazy` | `std::sync::LazyLock` / `OnceLock`            |
| `#[async_trait]` for static dispatch    | native `async fn` in traits                   |
| `failure`, `error-chain`                | `thiserror` (lib) / `anyhow` (app)            |
| `structopt`                             | `clap` v4 derive                              |
| scattered `#![deny(...)]` in `lib.rs`   | `[lints]` / `[workspace.lints]` in Cargo.toml |
| `-> impl Trait` lifetime workarounds    | precise capturing `+ use<..>`                 |
| `static mut`                            | `LazyLock`, `OnceLock`, atomics, or `Mutex`   |

## Lint Configuration

Lints live in `Cargo.toml`, not in `#![deny]` attributes. The house `[lints]` table ships with
`/setup-rust` — do not hand-write it. If the crate lacks it, stop and ask the user to run
`/setup-rust init` (new crate) or `/setup-rust update` (existing crate); the command is user-invoked
only. Library crates additionally opt into the restriction lints named in Rule 2. Threshold settings
(`msrv`, `too-many-arguments-threshold`, `disallowed-methods`) go in `clippy.toml`; workspace
members set `[lints] workspace = true`.

## Red Flags

Stop and re-check if any of these appear in code you are writing or reviewing:

- `.unwrap()` / `.expect()` / `v[i]` on a path reachable from a `pub fn` in a library
- An `unsafe {}` block with no `// SAFETY:` line above it
- `.clone()` added after a borrow-checker error rather than a restructure
- A lock guard or `RefCell` borrow still alive at an `.await`
- A spawned task whose `JoinHandle` is dropped
- A `pub fn` signature taking `&String` or `&Vec<T>`
- `unwrap_or_default()` or `.ok()` silently discarding an error on a fallible call

## Rationalizations That Mean You're About to Fail

| Excuse                                       | Reality                                                                      |
| -------------------------------------------- | ---------------------------------------------------------------------------- |
| "It cannot fail on an in-memory buffer"      | That is a guess about a dependency. Propagate it or prove it in the message. |
| "thiserror isn't a listed dependency"        | Add it. Hand-rolled `Display` + `source()` impls drift on the next variant.  |
| "We can polish the signature later"          | Public signatures are semver. `&String` today is a breaking change tomorrow. |
| "Clone is cheap here"                        | Measured? Restructure first; clone only when ownership is genuinely shared.  |
| "`Arc<Mutex>` is how Rust shares state"      | It is how Rust shares _mutable_ state. Most state is owned or read-only.     |
| "I'll add the SAFETY comment after it works" | Unaudited unsafe that compiles is UB nobody can find. Write it first.        |
| "Just make it compile and ship"              | `clippy -D warnings` is the bar, not `rustc`.                                |
| "It's a binary, unwrap is fine"              | Only where crashing is the correct response. Everything else uses `anyhow`.  |

## Verification

Run the gates the project exposes — Taskfile, justfile, Makefile, CI workflow, or pre-commit config
— using the project's pinned toolchain, and run the test suite separately from static checks. Every
command exits 0 before the task is complete. Fallback commands when no gate exists:
[references/docs-and-verification.md](references/docs-and-verification.md#verification-fallback-commands).
