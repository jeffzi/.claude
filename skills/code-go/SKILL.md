---
name: code-go
description: >
  Use when writing any Go code, regardless of perceived simplicity or prototyping context. Use
  when you think "just make it work, we'll polish next sprint", "log it and return nil", "put the
  helpers in util", or "define the interface next to the struct" — these are symptoms this skill
  applies. Also use when wrapping errors (%w vs %v, sentinel vs typed), spawning goroutines,
  threading context.Context, choosing where an interface lives, or modernizing superseded idioms
  (interface{}, ioutil, wg.Add, tt := tt). Not for scaffolding project tooling config
  (.golangci.yml, Taskfile, CI) — use /setup-go. For tests, also load test-go. Applies to
  *.go files.
user-invocable: false
---

# Go — Production-Quality Code

**This skill extends `Skill(code-core)`.** `code-core` is the primary entry point; this skill is
loaded by `code-core` based on the rules-file dispatch table.

Go version in play: !`go list -m -f '{{.GoVersion}}' 2>/dev/null || grep -m1 '^go ' go.mod
2>/dev/null`

When creating a module, set the `go` directive to the installed toolchain's version. If injection
above is empty, read `go.mod` manually before applying version-gated rules.

**Core principle:** Errors carry their chain to a caller that can act, every goroutine has an owner
that ends it, and abstractions are declared by the code that needs them.

## Domain Skill Detection

No overlays yet.

## Mandatory Rules

### 1. Errors Keep Their Chain

- Wrap with `fmt.Errorf("<operation> <subject>: %w", err)` at every call that crosses a boundary
  (package, I/O, goroutine). `%v` severs the chain: a caller can no longer `errors.Is` the cause.
- Sentinels are `var ErrNotFound = errors.New("user not found")` — lowercase, no trailing
  punctuation. A typed error (`type LimitError struct{...}`) only when callers need fields.
- Match with `errors.Is` / `errors.AsType[T]` (1.26+). Never `err == ErrX` on a wrapped error, never
  `strings.Contains(err.Error(), ...)`, never a type assertion on `err`.
- A fallback that hides a failure is a swallowed error (`code-core` Rule 4): `if err != nil { return
  "null" }`, `_ = json.Marshal(...)`, `if err != nil { return nil }`. Return the error, or make the
  fallback an explicit, documented behavior of the API.
- A non-2xx response is an error, not a result: `fmt.Errorf("get %s: unexpected status %d", url,
  resp.StatusCode)`, wrapping a sentinel (`ErrStatus`) when callers branch on it.
- `defer resp.Body.Close()` and `defer rows.Close()` are bare (errcheck-exempt). Every other
  `Close`/`Flush`/`Commit` error is checked and returned. Detail:
  `references/errors-and-verification.md#errcheck-and-closeflushcommit`.
- `panic` marks a programmer error (impossible state, invariant violated); anything recoverable
  returns `error`. `must*` helpers live only in package-level `var` initialization.

```go
// BAD: chain severed, then text-matched, then swallowed
if err := repo.Create(ctx, u); err != nil {
    return fmt.Errorf("create user: %v", err)
}
if strings.Contains(err.Error(), "23505") { ... }
body, _ := json.Marshal(v)

// GOOD
if err := repo.Create(ctx, u); err != nil {
    return fmt.Errorf("create user %q: %w", u.ID, err)
}
if pgErr, ok := errors.AsType[interface{ error; SQLState() string }](err); ok && pgErr.SQLState() == uniqueViolation { ... }
body, err := json.Marshal(v)
if err != nil {
    return fmt.Errorf("encode %s: %w", r.URL, err)
}
```

### 2. Every Goroutine Has an Owner and an Exit

- The function that starts a goroutine also ends it: `wg.Go(fn)` (1.25+) or an `errgroup.Group`,
  waited on before the function returns. No goroutine in `init()`, none started from a constructor
  without a matching `Close`/`Shutdown`.
- Every blocking operation inside a goroutine selects on `ctx.Done()`: channel sends, semaphore
  acquires, `time.After`. A goroutine that cannot observe cancellation leaks.
- Gate before `go`, not inside it. Acquire the semaphore (or `errgroup.SetLimit`) before spawning so
  the number of goroutines is bounded, not just the number in flight.
- Directional channel parameters (`chan<- T`, `<-chan T`). Close a channel from the sender side
  only, once.
- `sync.Mutex` guards fields, never copied (`go vet copylocks`); `atomic.Int64` and friends over
  `atomic.AddInt64`. Share memory by communicating when a channel expresses the ownership handoff.

```go
// BAD: unbounded goroutines, acquire ignores ctx, wg.Add/Done boilerplate
for _, u := range urls {
    wg.Add(1)
    go func() {
        defer wg.Done()
        sem <- struct{}{}
        defer func() { <-sem }()
        fetch(ctx, u)
    }()
}

// GOOD: bounded, cancellable, errors propagated
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(maxConcurrent)
for _, u := range urls {
    g.Go(func() error {
        return fetch(ctx, u)
    })
}
return g.Wait()
```

### 3. Context Is the First Parameter

`ctx context.Context` first, on every function that does I/O, blocks, or calls one that does. Never
stored in a struct field, never `nil` (use `context.TODO()` while migrating). Requests use
`http.NewRequestWithContext`; database calls use the `*Context` variants; handlers pass
`r.Context()` down. `cancel()` from `context.WithCancel`/`WithTimeout` is deferred at the call site
(`go vet lostcancel`).

### 4. Interfaces Are Declared by the Consumer

- The package that _calls_ a method declares the interface, sized to the methods it calls — usually
  one to three.
- Accept interfaces, return concrete types. Constructors return `*Service`, not `ServiceInterface`.
- Add `var _ Repository = (*PostgresRepository)(nil)` only when no assignment or call already
  converts `*PostgresRepository` to `Repository`; otherwise the wiring site is the compile-time
  check.
- Functional options (`WithTimeout(time.Duration)`, `WithLogger(*slog.Logger)`) for optional
  dependencies a production caller would set; a config struct when there are many required ones. A
  knob only tests turn (`WithClock`) is not exported API — tests fake time with `testing/synctest`
  (1.25+).
- Generics only for code that would otherwise be duplicated per type (`slices.Contains`, a typed
  container). Behavior that branches on the type parameter is an interface.

### 5. Doc Comments Say What the Name Leaves Out

Go doc comments: `//` lines directly above the declaration, starting with the declared name (`//
Name does X.`). A package comment starts `// Package name` and lives in `doc.go` for a multi-file
package. Parameters, results, and errors are named in prose; Go has no `@param`-style tags.

- **Required:** every exported top-level identifier and every exported method. A `const` or `var`
  block takes one comment on the block. None is required on unexported identifiers.
- **Content:** what the name leaves out — a side effect, an invariant, a precondition, the error
  types returned, what a zero value or `nil` means. When the name of a required identifier says
  everything, the one-line name-first comment stands: the linter demands it, and padding it adds
  nothing.
- **Never required:** a comment on a struct field, on one constant inside a documented block, on an
  interface method, or on an unexported identifier. Each of these earns its place by carrying a fact
  the name and type do not. One that restates them is deleted, not reworded.

```go
type ToolMissingError struct {
    // BAD: restates the field name and type
    // InstallHint tells the user how to install the tool.
    InstallHint string

    // GOOD: says what the name cannot
    // Required names the checks that decide; when empty, every check decides.
    Required []string
}
```

A function you edit gets its doc comment brought to this shape even if you did not write it.

## Pitfalls

| Trap                                                                                | Instead                                                                                                                                                                                                                                       |
| ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `util`, `common`, `helpers`, `strutil`, `models` package                            | Unexported helper in its one consumer; a domain-named package (`slug.Make`) when shared                                                                                                                                                       |
| "Reusable" as the reason for a package                                              | Name it for what it provides. Reusability is not a package name                                                                                                                                                                               |
| A new package per layer or per type (`handlers`, `services`, `repository`, `types`) | Default is no new package — add a file to the existing one. Split only when the new package has its own one-word purpose; supporting packages start under `internal/`. A single command keeps `main.go` in the module root, not `cmd/<name>/` |
| Exported identifier outside the supported API                                       | `internal/` — exported is semver                                                                                                                                                                                                              |
| `user.UserService`, `fetch.FetchAll`                                                | `user.Service`, `fetch.All` — no stutter with the package name                                                                                                                                                                                |
| `userId`, `parseUrl`, `ServeHttp`                                                   | `userID`, `parseURL`, `ServeHTTP` — initialisms keep their case                                                                                                                                                                               |
| `len`, `error`, `new` as identifiers                                                | Names that do not shadow builtins                                                                                                                                                                                                             |
| Acquire on one line, `defer Close()` twenty lines later                             | `defer` on the line after the successful acquire (`resp.Body`, `rows`, `f`, `mu.Unlock`)                                                                                                                                                      |
| `for rows.Next() {}` with no `rows.Err()` after it                                  | Check `rows.Err()` — a truncated result set looks like a short page otherwise                                                                                                                                                                 |
| Discarded response body left unread                                                 | `io.Copy(io.Discard, resp.Body)` so the connection is reused                                                                                                                                                                                  |
| `io.ReadAll` on an untrusted body                                                   | `io.LimitReader` / `http.MaxBytesReader`                                                                                                                                                                                                      |
| `log.Printf`, `fmt.Println` inside a library                                        | Return the error; libraries do not log                                                                                                                                                                                                        |
| Log and return the same error                                                       | Log once with `slog.ErrorContext` where propagation stops (handler, worker); `slog.SetDefault` in `main`                                                                                                                                      |

## Modern Replacements

The compiler accepts every row on the left. `go fix ./...` (1.26+ toolchain) rewrites most of them;
the rest are review findings.

| Outdated                                    | Use instead                                              | Since |
| ------------------------------------------- | -------------------------------------------------------- | ----- |
| `interface{}`                               | `any`                                                    | 1.18  |
| `io/ioutil.*`                               | `os.*` / `io.*`                                          | 1.16  |
| `tt := tt` inside `for range`               | nothing — loop variables are per-iteration               | 1.22  |
| `for i := 0; i < n; i++`                    | `for i := range n`                                       | 1.22  |
| manual `min`/`max`/contains loops           | `min`, `max` builtins; `slices`, `maps` packages         | 1.21  |
| `sort.Slice`                                | `slices.SortFunc`                                        | 1.21  |
| `rand.Seed(...)`, `math/rand`               | `math/rand/v2` (auto-seeded); `crypto/rand.Text` (1.24)  | 1.22  |
| `github.com/pkg/errors`                     | `fmt.Errorf("%w")`, `errors.Is/As`, `errors.Join` (1.20) | 1.13  |
| `errors.As(err, &target)`                   | `target, ok := errors.AsType[T](err)`                    | 1.26  |
| `wg.Add(1)` + `go` + `defer wg.Done()`      | `wg.Go(func() { ... })`                                  | 1.25  |
| `x := v; p := &x`                           | `p := new(v)`                                            | 1.26  |
| third-party router for method + path params | `http.ServeMux` `"GET /users/{id}"`, `r.PathValue`       | 1.22  |
| `time.Now().Sub(t)` / `d.Sub(time.Now())`   | `time.Since(t)` / `time.Until(d)` (1.8)                  | 1.0   |
| `atomic.AddInt64(&n, 1)`                    | `atomic.Int64` methods                                   | 1.19  |
| `strings.Split` + index for one separator   | `strings.Cut`, `strings.CutPrefix` (1.20)                | 1.18  |
| `for _, s := range strings.Split(...)`      | `for s := range strings.SplitSeq(...)`                   | 1.24  |
| `encoding/json` for new code                | `encoding/json/v2`                                       | 1.27  |
| `github.com/golang/mock`                    | `go.uber.org/mock` (or a hand-written fake)              | 2023  |

## Rationalizations That Mean You're About to Fail

| Excuse                                                     | Reality                                                                         |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| "Don't over-engineer, just make it work"                   | `%w`, `ctx`, `defer Close()` cost nothing. Skipping them is the rework.         |
| "A body that can't be re-encoded isn't worth failing over" | That is a swallowed error. Return it; let `main` decide what to print.          |
| "Non-2xx is a result, the Status field is right there"     | The caller that forgets to check it exits 0 on a 404. Return the error.         |
| "The reviewer asked for interfaces so we can mock"         | Declare them at the consumer, sized to the calls. A five-method port is a mock. |
| "That was the reusability ask, so `strutil`"               | Reusable code gets a domain name. `strutil` is `util` with a prefix.            |
| "The driver only puts the code in the message"             | It implements `SQLState()`. Match the interface, never the text.                |

## Red Flags — Stop and Fix

STOP and re-check if you see any of these in Go code:

- `%v` inside `fmt.Errorf` that wraps an error — severs the chain (Rule 1)
- `err == ErrX` or `strings.Contains(err.Error(), ...)` — text/identity match on a wrapped error
  (Rule 1)
- `if err != nil` branch returning a zero value, `nil`, or a literal default — swallowed error
  (Rule 1)
- A `go` statement or `wg.Go` with no `Wait`/`errgroup` owning it — leaked goroutine (Rule 2)
- A blocking send or acquire inside a goroutine with no `ctx.Done()` select — uncancellable
  goroutine (Rule 2)
- A function doing I/O without `ctx context.Context` as the first parameter (Rule 3)
- `context.Context` stored in a struct field (Rule 3)
- An interface declared in the package that implements it — consumer declares interfaces (Rule 4)
- A new package named `util`, `common`, `helpers`, or `*util` (Pitfalls)
- An exported identifier with no doc comment, or a struct-field comment that repeats the field's
  name (Rule 5)

## Verification

Run the gates the project exposes — a `Taskfile`, `Makefile`, `justfile`, CI workflow, or pre-commit
config — and run the test suite separately from static checks. If the project exposes no gate, see
`references/errors-and-verification.md#verification-fallback-commands`. Every command exits 0 before
the task is complete.
