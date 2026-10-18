# Documentation and Verification Detail

## Contents

- [Documentation on public items](#documentation-on-public-items)
- [Verification fallback commands](#verification-fallback-commands)

---

## Documentation on public items

`///` on every public item, `//!` at crate and module level. A fallible `pub fn` has `# Errors`; one
that can panic has `# Panics`; unsafe items have `# Safety`; every public fn has a runnable `#
Examples` doctest (one that touches the filesystem uses `tempfile` as a dev-dependency). Use
intra-doc links (`[`Config`]`), not URLs. Internal items that must be `pub` get `#[doc(hidden)]`.
Rustdoc builds with `-D warnings`.

## Verification fallback commands

When the project exposes no gate (Taskfile, justfile, Makefile, CI workflow, pre-commit config),
fall back to these commands using the project's pinned toolchain (`rust-toolchain.toml`):

- `cargo fmt --all --check`
- `cargo clippy --all-targets --all-features -- -D warnings`
- `cargo nextest run --all-features` (`cargo test` without nextest) plus `cargo test --doc
  --all-features` (nextest skips doctests)
- `RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --all-features`

Conditional commands (run when the condition applies):

- `cargo deny check` — a `deny.toml` exists
- `cargo machete` — unused dependencies
- `cargo semver-checks` — library about to be published
- `cargo +nightly miri test` — crate contains `unsafe`
