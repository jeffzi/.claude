---
name: release
description: >
  Drive a release branch by hand: cut it, see where it stands, land plan branches on it, and ship
  it onto main with a tag. User-invoked only; the assistant never runs release.sh on its own.
argument-hint: "start <X.Y.Z> [--adopt] | status | merge [--force] | finish [--force] [--gh-release]"
disable-model-invocation: true
allowed-tools:
  - Bash(~/.claude/scripts/release.sh *)
  - Bash(touch *release-active)
  - Bash(rm -f *release-active)
  - Bash(git branch --show-current)
  - Bash(git log *)
  - Bash(git rev-parse *)
  - Bash(git status *)
  - Bash(git diff *)
  - Bash(git config --get *)
  - Bash(git tag -s release-warmup *)
  - Bash(git tag -d release-warmup)
  - Bash(gh run *)
  - Bash(~/.claude/scripts/plan-branch.sh base*)
  - Bash(mkdir -p *plan-squash)
  - Bash(ls *)
  - Read
  - Write
---

# Release

**Arguments:** $ARGUMENTS

One release is one branch, `vX.Y`, cut from `main` and known by `git config branch.vX.Y.release`.
Plan branches land on it; when it is done it fast-forwards `main` with a tag on the tip. The script
does every git write; this skill raises the marker that lets it run, runs it, and reports what it
said.

## Context

- Branch: !`git branch --show-current 2>/dev/null || true`
- Release: !`~/.claude/scripts/release.sh status 2>/dev/null | grep -m1 . || echo "(no repo)"`
- Squash message: !`ls "$(git rev-parse --absolute-git-dir 2>/dev/null)/plan-squash/" 2>/dev/null ||
  echo "(none)"`
- Commit signing: !`git config --get commit.gpgsign 2>/dev/null || echo "false"`

## Subcommand

The first word of `$ARGUMENTS` picks one of four. No word, or any other word: print these four lines
and stop — no marker, no script call.

| Subcommand                        | What it does                                                                   |
| --------------------------------- | ------------------------------------------------------------------------------ |
| `start <X.Y.Z> [--adopt]`         | Cut `vX.Y` from `main` and push it; `--adopt` marks the current branch instead |
| `status`                          | Where the release stands — no marker, read-only                                |
| `merge [--force]`                 | Land the current `plan/*` branch on its recorded base                          |
| `finish [--force] [--gh-release]` | Release commit, tag, CI, fast-forward `main`, delete the branch                |

## The three-call shape

Every subcommand but `status` runs the script inside a marker. Three **separate** Bash calls, in
this order; the guard inspects each call before it runs, so the marker must already be on disk when
the script call reaches it — one combined call is blocked.

```bash
git_dir=$(git rev-parse --absolute-git-dir) && touch "$git_dir/release-active"   # call 1
~/.claude/scripts/release.sh <subcommand and its arguments>                     # call 2
rm -f "$(git rev-parse --absolute-git-dir)/release-active"                       # call 3 — ALWAYS
```

The script checks every precondition before it writes anything and refuses with a reason (exit 2)
when one fails. A refusal is the answer: report it verbatim and end the turn. No retry, no fixing
the tree, no re-run with `--force` on your own initiative — the user reads the reason and decides. A
failure after a write (exit 1) names what was kept; report it the same way.

## `status`

Run `~/.claude/scripts/release.sh status` with no marker and print its output. It is the answer to
"where are we": the open release and its version, the commits it carries beyond `main`, the plan
branches still to land, and whether the branch or `main` has moved.

## `start`

`start X.Y.Z` through the three calls. The script wants a clean `main` equal to `origin/main` and no
release already open; it cuts `vX.Y`, records the version, pushes with upstream set, and ends on the
branch. `start X.Y.Z --adopt` records the version on the branch you are on instead, cutting and
pushing nothing. Report the script's line.

## `merge`

Off a `plan/*` branch (Context shows another branch): report the branch and stop. No marker.

Before call 1, when the branch holds `fixup!` commits and Context shows commit signing on, run the
signing warm-up so the rebase does not stall on its first prompt:

```bash
base=$(~/.claude/scripts/plan-branch.sh base)
git log --format=%s "$base..HEAD"          # any line starting with "fixup! " means a fold
git tag -s release-warmup -m warmup && git tag -d release-warmup
```

Say first that one signing prompt per replayed release commit is expected. Then the three calls with
`merge` and, when given, `--force`. With fixups the script folds each into the release commit it
names, squashes the rest as one commit, and force-pushes the release branch under a lease; without
them it squashes onto the base as before. Both end on the base with the plan branch gone.

### `--force`

The user's word for "merge what is on the branch". It does two things and nothing else:

1. **CI gate off.** The script skips the CI check; every other refusal still stands.
2. **Missing message written.** When Context shows `(none)` for the squash message and the branch
   has commits that are not `fixup!` (the `git log` above), write it before call 1: load
   `Skill(write-commit)`, compose one conventional message for the whole branch from the plan's
   **Goal** in `.planning/` and `git diff <base>...HEAD --stat`, `mkdir -p "$git_dir/plan-squash"`,
   and Write it to `$git_dir/plan-squash/<slug>.msg`. No plan slug, no `.planning/` path, no process
   words. A message that already exists is never rewritten; an all-`fixup!` branch needs none.

Without `--force` a missing message is a refusal to report, exactly as the script says.

## `finish`

Three script calls around the release commit, each inside its own three-call shape. `--force` and
`--gh-release` pass through to `--publish` only.

1. **`finish --check`.** A refusal ends the turn. Success prints `version: X.Y.Z`; keep it.
2. **`Skill(write-release)` with that version** and nothing else — never `--gh-release`, since its
   own GitHub step would create the tag on the remote before the branch carries it. Its two
   confirmations (the bump list, the staged files) are the user's; wait for each. It leaves the
   release commit `chore: release vX.Y.Z` and the tag `vX.Y.Z` on the release branch.
3. **`finish --push`.** A refusal ends the turn. Success prints `commit: <sha>`; keep the sha.
4. **Watch CI for that sha** — skipped when `--force` was given:

   ```bash
   gh run list --commit "<sha>" --json databaseId,status,conclusion --limit 5
   ```

   No run after two polls thirty seconds apart: report `no branch CI` and end the turn; nothing is
   published. A run: watch it in the background, output to a file under the session scratchpad, no
   pipe, no `tee`:

   ```bash
   gh run watch <run-id> --exit-status --interval 30 > <scratchpad>/release-ci-watch.txt 2>&1
   ```

   The watch's exit code is a wake-up signal, nothing more. On completion the only observation that
   means green is `gh run view <run-id> --json headSha,status,conclusion` showing `status:
   completed`, `conclusion: success`, and `headSha` equal to the pushed sha. Anything else is red:
   report the run's conclusion and end the turn; nothing is published.
5. **`finish --publish`**, with `--force` and `--gh-release` when given. The script re-checks CI
   (unless `--force`), fast-forwards `main`, pushes `main` and the tag, deletes the branch locally
   and on origin, and ends on `main`. Report its line.

## Report

One line on success: the script's success line, plus for `merge` the base's new commit (`git log -1
--oneline <base>`). On refusal or failure: the script's reason verbatim, and stop. Nothing else.

## Bright lines

- **One run.** A refusal is the answer, not a retry prompt. Never fix the tree, rewrite the message
  file, tag by hand, or re-run with `--force` on your own initiative.
- **No git writes here.** No `git commit`, `merge`, `push`, `branch`, `switch`, `tag` beyond the
  warm-up pair — the script owns them. This skill's own git use is the read-only Context and the
  `git log` that looks for fixups.
- **The marker lives only around a script call.** Touched immediately before, removed immediately
  after, on every exit path — never left up across `write-release`'s confirmations or the CI watch,
  never raised outside this skill, not by `execute-plan`, not for a "quick manual merge".
- **Green is an observation.** `CI green` is `gh run view` output in your context, never a watch's
  exit code, never a guess from a quiet log.

| Excuse                                               | Reality                                                      |
| ---------------------------------------------------- | ------------------------------------------------------------ |
| "CI is just slow — skip it this once"                | `--force` is the user's word, passed in. Never added.        |
| "The message file is missing, I'll write one"        | Only under `--force`. Otherwise missing → report.            |
| "`--force` means merge no matter what"               | CI and the message only. Dirty tree, stale base → refusal.   |
| "The tree is dirty with one obvious file, commit it" | Refusal. The user decides what that file is.                 |
| "The refusal is a precondition, fix it and re-run"   | One run. Report the reason; the next run is the user's call. |
| "Leave the marker up, the next call needs it anyway" | A lingering marker lets the script run outside this skill.   |
| "`write-release --gh-release` saves a step"          | It pushes the tag before CI ran on it. `--publish` does it.  |
| "The watch exited 0, so CI is green"                 | Green is `gh run view` showing `conclusion: success`.        |
