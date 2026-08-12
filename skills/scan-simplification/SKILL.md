---
name: scan-simplification
description: >
  Use when reviewing code exclusively for over-engineering — reinvented standard library,
  unneeded dependencies, speculative abstractions, dead flexibility, single-use layers. Finds
  what to delete; never fixes. Dispatched as harden's simplification lens, or standalone for
  "what can we delete" / "is this over-engineered" requests. Not for correctness bugs — use
  scan-bug. Not for applying the cleanup — use distill-code.
argument-hint: "[files or directory]"
allowed-tools: Read, Glob, Grep, Bash(grep:*), Bash(rg:*), Bash(wc:*), Bash(find:*)
---

# Simplification Scan

**Target:** $ARGUMENTS

Review code for unnecessary complexity. One line per finding: location, what to cut, what replaces
it. The diff's best outcome is getting shorter. You find cuts; you do not apply them.

## When you are invoked

You receive a list of **files** to review, and optionally a **tier** (per-area when unstated):

- **Per-area** — you see one slice of the repo. Flag what the slice shows; never assert a repo-wide
  fact. A "dead" function may have callers outside your slice — report it as "no caller in reviewed
  files".
- **Global** — you own whole-caller-graph claims: dead code and single-use abstractions whose lone
  caller sits elsewhere. Search every reference path before claiming.

## Format

`L<line>: <tag> <what>. <replacement>.`, or `<file>:L<line>: ...` across files.

Tags:

- `delete:` dead code, unused flexibility, speculative feature. Replacement: nothing.
- `stdlib:` hand-rolled thing the standard library ships. Name the function.
- `native:` dependency or code doing what the platform already does. Name the feature.
- `yagni:` abstraction with one implementation, config nobody sets, layer with one caller.
- `shrink:` same logic, fewer lines. Show the shorter form.

## Examples

✅ `L12-38: stdlib: 27-line validator. "@" in email, 1 line; real check is the confirmation mail.`

✅ `L4: native: moment.js imported for one format call. Intl.DateTimeFormat, 0 deps.`

✅
`repo.py:L88: yagni: AbstractRepository with one implementation. Inline it until a second one exists.`

✅ `L52-71: delete: retry wrapper around an idempotent local call. Nothing replaces it.`

✅ `L30-44: shrink: manual loop builds dict. dict(zip(keys, values)), 1 line.`

❌ "This EmailValidator class might be more complex than necessary, have you considered whether all
these validation rules are needed at this stage?"

## Scoring

End with the only metric that matters: `net: -<N> lines possible.`

If there is nothing to cut, say `Lean already.` and stop.

## Boundaries

- Over-engineering and complexity only. Correctness bugs and security holes → `scan-bug`; style and
  idiom → the `vet-code` agent. Both out of scope here.
- A single smoke test or `assert`-based self-check is the minimum, not bloat — never flag it for
  deletion.

## Common mistakes

- **Flagging safety as bloat.** Input validation, error handling that prevents data loss, security
  measures, and accessibility are never "unneeded flexibility" — even when they look verbose.
- **Claiming "dead code" in per-area tier.** A function with no caller in your slice may have
  callers elsewhere — qualify as "no caller in reviewed files", never "dead".
