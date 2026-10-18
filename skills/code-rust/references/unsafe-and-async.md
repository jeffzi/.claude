# Unsafe and Async Patterns

## Contents

- [Unsafe auditing](#unsafe-auditing)
- [Async: tokio](#async-tokio)

---

## Unsafe auditing

Every `unsafe {}` block is preceded by `// SAFETY:` naming the invariant that makes it sound; one
unsafe operation per block. Every `unsafe fn` and `unsafe impl` documents `# Safety`. Edition 2024
warns on bare unsafe ops inside an `unsafe fn` — wrap them in their own block. Prefer `NonNull<T>`
to `*mut T`; use `#[unsafe(no_mangle)]` and `unsafe extern "C" { ... }`.

```rust
/// # Safety
/// `idx < self.capacity()`; violating this writes outside the allocation.
pub unsafe fn write_at(&mut self, idx: usize, v: u64) {
    // SAFETY: caller guarantees idx < cap, so the offset stays inside the allocation from `new`.
    let slot = unsafe { self.buf.as_ptr().add(idx) };
    // SAFETY: `slot` is in-bounds (above) and aligned for u64 by `Layout::array::<u64>`.
    unsafe { slot.write(v) }
}
```

Application and web crates set `unsafe_code = "forbid"` in `[lints.rust]`; an application that needs
one low-level module sets `"deny"` and opens that module with `#![allow(unsafe_code)]` plus a
comment naming why. Any crate containing `unsafe` enables `clippy::undocumented_unsafe_blocks` and
runs Miri in verification.

## Async: tokio

- `tokio` is the runtime; `async-std` is discontinued — migrate, don't extend.
- Never hold a `std::sync::Mutex` guard or `RefCell` borrow across an `.await`
  (`clippy::await_holding_lock`). `std::mem::take` the data under the lock and drop the guard before
  awaiting, or use `tokio::sync::Mutex` when the critical section itself must await.
- CPU-heavy or blocking I/O moves to `spawn_blocking`; its `JoinError` propagates (Rule 2).
- Structured concurrency: `JoinSet` or `tokio::join!`; every spawned task is joined or its handle
  stored. A dropped `JoinHandle` silently discards the task's error (`code-core` Rule 4).
- Native `async fn` in traits for static dispatch; `#[async_trait]` only for `dyn Trait`.
- A function with no `.await` inside is not `async`.
