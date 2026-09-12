# Conventional Commits — Extended Reference

## Footer syntax

`<token>: <value>` or `<token> #<value>`. Multi-word tokens use hyphens (`Acked-by`, `Refs`,
`Reviewed-by`).

A `BREAKING CHANGE:` (or `BREAKING-CHANGE:`) footer is optional when `!` is present in the subject,
required when it isn't.

## Reverts

Use `revert: <subject of reverted commit>` and add a `Refs: <sha>` footer pointing to the reverted
commit.

## Merge commits

Keep git's default `Merge …` subject — Conventional Commits does not apply.
