# Errors and Verification — Extended Detail

## errcheck and Close/Flush/Commit

`defer resp.Body.Close()` and `defer rows.Close()` are bare: the house `.golangci.yml`
(`/setup-go`'s `references/golangci.yml`) exempts exactly `(io.ReadCloser).Close` and
`(*database/sql.Rows).Close` from errcheck; in a project whose config lacks those exemptions, check
the error.

Every other `Close`/`Flush`/`Commit` error is checked and returned — `*os.File` whether opened for
reading or writing, `bufio.Writer`, `gzip.Writer`, transactions.

## Verification fallback commands

When the project exposes no gate (`Taskfile`, `Makefile`, `justfile`, CI workflow, pre-commit
config), fall back to:

1. `gofumpt -l .` — must print nothing
2. `go vet ./...`
3. `go fix -diff ./...` (1.26+ toolchain) — must print nothing
4. `golangci-lint run ./...`
5. `go test -race -count=1 ./...`

Every command exits 0 before the task is complete.
