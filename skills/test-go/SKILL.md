---
name: test-go
description: >
  Use when writing Go tests with the testing package. Apply for table-driven subtests, t.Parallel,
  t.Cleanup, t.Context, export_test.go, testing/synctest and fake clocks, httptest and
  RoundTripper stubs, hand-written fakes vs go.uber.org/mock or testify, go-cmp, golden files in testdata/,
  fuzz targets, benchmarks with b.Loop, goleak, or any *_test.go files. Also use when a reviewer
  asks to test an unexported function in-package, when a test needs time.Sleep, or when coverage
  is below a gate. Not for production Go patterns — use code-go for that.
user-invocable: false
---

# Go Testing

**This skill extends `Skill(test-core)`.** `test-core` is the primary entry point; this skill is
loaded by `test-core` based on the rules-file dispatch table.

**Load `Skill(code-go)` and apply its rules.** Exception: test doubles may discard the write error
of an `httptest` response writer (`_, _ = w.Write(b)`), and test functions may use underscores in
their names. Test-only modules (`go-cmp`, `goleak`, `go.uber.org/mock`) are added with `go get` when
first needed; a test never adds `testify` to a module that does not already depend on it.

## Domain Skill Detection

No overlays yet.

## Mandatory Rules

### 1. Black-Box by Default; the Back Door Is `export_test.go`

Every `_test.go` file is `package foo_test`. Go's `_test` suffix exists so tests consume the package
the way callers do; a `package foo` test file couples the suite to struct layout and lets coverage
come from restating internals. `Skill(test-core)`'s rule against testing private functions (Test
Through the Public API) applies in full, with one Go-specific mechanism:

- **An internal that the public API genuinely cannot pin down** (a parser's exact output, a
  state-machine transition) is re-exported from an in-package `export_test.go` — `var ParseTTL =
  parseTTL` — and tested from `foo_test` like any other symbol. The back door is one line,
  greppable, and invisible to importers. Stdlib `fmt`, `net/http`, and `math` do exactly this.
- **"Not observable from outside" is an API finding, not a license.** If the public API has no way
  to pin down an internal, the package is missing an accessor or a seam (a store, a transport).
  Report the gap and write the test against the proposed seam — never build state from private
  fields or open the struct.
- **`*_internal_test.go` is not an exception.** The `testpackage` linter allows the suffix; this
  rule does not. The `evictExpired`-style helper is driven through `Get`/`Len`.

```go
// BAD: package cache — coupled to layout, restates the body
func TestEvictExpired(t *testing.T) {
    c := &Cache{items: map[string]entry{"k": {expires: time.Now().Add(-time.Hour)}}}
    c.evictExpired()
    if len(c.items) != 0 { t.Fatal("not evicted") }
}

// GOOD: package cache_test — same path through the API, deterministic via synctest
func TestGet_WhenTTLElapsed_ReportsMissing(t *testing.T) {
    synctest.Test(t, func(t *testing.T) {
        c := cache.New(time.Minute)
        c.Set("k", []byte("v"))
        time.Sleep(time.Minute) // virtual: advances the bubble clock instantly

        _, ok := c.Get("k")

        if ok {
            t.Error("Get(k) reported present after TTL elapsed, want missing")
        }
    })
}
```

### 2. Deterministic Time: `synctest`, Never a Real Sleep

Code that reads `time.Now`, sleeps, or uses timers is tested inside `synctest.Test` (1.25+): the
bubble has a fake clock that advances only when every goroutine in it is blocked, so `time.Sleep` in
production code and in the test resolves instantly and in order. `synctest.Wait()` blocks until the
bubble is idle. `synctest.Test` waits for every goroutine in the bubble to exit and fails only on
deadlock — every goroutine durably blocked on a bubble channel, `WaitGroup.Wait`, `Cond.Wait`, or
`time.Sleep`. That catches those leaks; a goroutine stuck on a mutex or I/O makes the test hang
instead of fail.

Code that already takes a `now func() time.Time` or a clock interface gets a fixed function,
advanced explicitly. Never ask production code to add a clock for a test — the bubble fakes time
without one. A wall-clock `time.Sleep` in a test is replaced with `synctest.Wait`, a channel, or a
`sync.WaitGroup`.

### 3. Table-Driven Subtests, Parallel at Both Levels

Same code path with varying inputs is one table and one `t.Run` per row; `t.Parallel()` on the
parent and in each subtest. Loop variables are per-iteration since 1.22 — `tt := tt` is a marker of
stale advice and `copyloopvar` flags it. Separate accept and reject tables rather than one table
whose `wantErr` makes `want` meaningless on half the rows. Rows are named by condition, not by
ordinal.

```go
func TestParseTTL(t *testing.T) {
    t.Parallel()
    tests := []struct {
        name string
        in   string
        want time.Duration
    }{
        {name: "bare integer is seconds", in: "30", want: 30 * time.Second},
        {name: "duration string", in: "5m", want: 5 * time.Minute},
        {name: "surrounding whitespace trimmed", in: " 10s ", want: 10 * time.Second},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            got, err := cache.ParseTTL(tt.in)
            if err != nil {
                t.Fatalf("ParseTTL(%q) error = %v, want nil", tt.in, err)
            }

            if got != tt.want {
                t.Errorf("ParseTTL(%q) = %v, want %v", tt.in, got, tt.want)
            }
        })
    }
}
```

### 4. Scaffolding: `t.Helper`, `t.Cleanup`, `t.Context`

Helpers call `t.Helper()` first and take `t` as their first argument. Teardown goes through
`t.Cleanup`, never a manual `defer` the caller can forget. `t.TempDir()`, `t.Setenv`, `t.Chdir` over
hand-rolled equivalents (`usetesting`). Contexts come from `t.Context()`, cancelled at cleanup.

### 5. Fakes at Boundaries; the Boundary Is Not Moved for the Test

The default test double is a hand-written fake that implements the interface the _consumer_ already
declares. A test never introduces an interface into production code so it can be mocked — that is a
production design change and goes in the report. `go.uber.org/mock` is for wide boundary interfaces
already in place; `testify/mock` only in a module that already depends on it. Neither asserts call
counts or order on internal wiring; assert the outcome.

| Boundary                                         | Double                                                                                                                                                                                       |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Outbound HTTP                                    | `http.Client{Transport: roundTripFunc(...)}` — no socket, real client stays in path                                                                                                          |
| Real transport needed (timeouts, redirects, TLS) | `httptest.NewTestServer(t, h)` (1.27+, in-memory, works inside `synctest.Test`; use `srv.Client()`); `httptest.NewServer` + `t.Cleanup(srv.Close)` only for a real socket, never in a bubble |
| Inbound handler                                  | `httptest.NewRecorder` + `httptest.NewRequestWithContext(t.Context(), ...)`                                                                                                                  |
| Filesystem                                       | `t.TempDir()`; `testing/fstest.MapFS` for read-only `fs.FS` consumers                                                                                                                        |
| Database                                         | transaction-per-test rollback, or `testcontainers`; never a mocked `*sql.DB`                                                                                                                 |
| Time                                             | `synctest.Test`; a fixed `now func() time.Time` where the code already takes one                                                                                                             |
| Randomness                                       | injected `*rand.Rand` seeded with `rand.NewPCG(1, 2)`                                                                                                                                        |

```go
type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
```

### 6. Naming

`Test<Subject>_When<Condition>_<Expected>` for standalone tests
(`TestGet_WhenTTLElapsed_ReportsMissing`); `Test<Subject>` for a table whose rows carry the
condition. Subject is the function, or `Type_Method` for methods. Benchmarks, fuzz targets, and
examples follow the same subject.

The name carries the intent: a test, benchmark, or fuzz function takes no doc comment.

## Data Testing Patterns

| Tool                                      | Use for                                                                                                  |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `t.Errorf("Func(%q) = %v, want %v", ...)` | Every assertion: got and want, input named; `t.Fatalf` only when the test cannot continue                |
| `cmp.Diff(want, got)` (`go-cmp`)          | Structs, slices, maps; `cmpopts.IgnoreFields` / `EquateApproxTime` instead of zeroing by hand            |
| `errors.Is` / `errors.AsType[*T]`         | Sentinels and typed errors — never `strings.Contains(err.Error(), ...)`, the message is not the contract |
| `testdata/*.golden` + `-update` flag      | Large or textual output, compared with `cmp.Diff`; one `-update` flag per package                        |
| `FuzzXxx` with `f.Add` seeds              | Every parser and decoder: round-trip or no-panic properties; crashers land in `testdata/fuzz/`           |
| `ExampleXxx` with `// Output:`            | Exported API that documentation should show                                                              |
| `for b.Loop()`                            | Benchmarks; convert `b.N` loops by hand — `go fix` does not rewrite them                                 |

## Pitfalls

| Trap                                                       | Instead                                                                                                                                    |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `t.Fatal` from a goroutine the test started                | Send the failure over a channel and fail on the test goroutine (`vet testinggoroutine`)                                                    |
| A mutex test that passes without `-race`                   | It proved nothing. `go test -race` is the only run that counts for concurrent code                                                         |
| Code that starts goroutines, no leak check                 | `goleak.VerifyNone(t)`; `synctest.Test` fails only when leaked goroutines are durably blocked — one stuck on a mutex or I/O hangs the test |
| Blank line between `got, err := Act()` and `if err != nil` | gofumpt removes it. Keep the check attached to Act; the AAA blank line goes before value asserts                                           |

## Verification

Verification commands: see `code-go` § Verification. Tests run with `go test -race -count=1
-shuffle=on ./...`; `-shuffle` catches order dependence.

## Red Flags

STOP and re-check if you see any of these in test code:

- A `_test.go` file whose package clause lacks the `_test` suffix and is not `export_test.go`
  (Rule 1)
- A composite literal setting unexported fields in Arrange (Rule 1)
- `time.Sleep` outside a `synctest` bubble (Rule 2)
- `tt := tt` inside the table loop (Rule 3)
- A call-count or call-order assertion on a double (Rule 5)
- `go test` reported green without `-race` and `-shuffle=on` (Verification)

## Rationalizations

| Excuse                                                       | Reality                                                                                  |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| "The result isn't observable from outside the package"       | Then the API has a gap. Report it, or assert the behavior the value causes.              |
| "Testing expiry through the API means sleeping for the TTL"  | `synctest.Test` sleeps in virtual time. A zero TTL reaches the branch too.               |
| "In-package is the correct call here, not just the fast one" | It couples the suite to struct layout either way. `export_test.go` is the back door.     |
| "The reviewer said it's fastest in-package"                  | Authority does not lift Rule 1. Re-export through `export_test.go` and reply why.        |
| "`_internal_test.go` is allowed by the linter"               | The linter's allowlist is not this rule's. Same-package files are `export_test.go` only. |
| "Adding a clock is a production change I don't want to make" | No clock is needed: run the test inside `synctest.Test`. Do not reach past the API.      |
