# Rust Test Tooling Reference

## Async and tokio

`#[tokio::test]` is the default async runner. `flavor = "multi_thread"` only when the behavior under
test needs real parallelism. Never build a second runtime or `block_on` inside a tokio test. Spawned
tasks in tests are awaited through their `JoinHandle` so a panic inside them fails the test.

For deterministic time under tokio, use `#[tokio::test(start_paused = true)]` and
`tokio::time::advance(...)` — both need `tokio = { version = "1", features = ["test-util"] }` in
`[dev-dependencies]`. Paused time makes `tokio::time::sleep` in production code resolve instantly
and in order.

## Test Doubles by Boundary

Hand-rolled fakes implement the boundary trait and record what they saw (`Rc<RefCell<_>>` in sync
tests; `Arc<Mutex<_>>` under tokio or when the trait requires `Send`).

| Boundary      | Tool                                                |
| ------------- | --------------------------------------------------- |
| Filesystem    | `tempfile::tempdir()` — never a real or `/tmp` path |
| External HTTP | `wiremock::MockServer` (async)                      |
| CLI binary    | `assert_cmd::Command::cargo_bin` + `predicates`     |
| Database      | transaction-per-test rollback, or `testcontainers`  |
| Time          | injected clock / `tokio::time::pause`               |

## Assertion Tools

- `insta::assert_snapshot!` / `assert_debug_snapshot!` for complex or textual output; review with
  `cargo insta review`; `.snap` files are committed.
- `proptest!` for round-trips, ordering, and invariants over generated input. `proptest` manages its
  own seeds — commit the `proptest-regressions/` directory so shrunk failures replay.
- `#[should_panic(expected = "...")]` only for a documented `# Panics` contract.
