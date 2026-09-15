# Branch Flow — Entry Gate, Findings Fix, Ship, Squash Message

Mechanics for the plan branch. The rules live in `SKILL.md`; this file carries the commands.

## Entry gate (prologue, before the marker and Task 1)

```bash
branch=$(git branch --show-current)
git diff --quiet && git diff --cached --quiet    # index and working tree clean; untracked files are fine
```

| State                                       | Action                                                                           |
| ------------------------------------------- | -------------------------------------------------------------------------------- |
| Clean, on a branch that is not `plan/*`     | `~/.claude/scripts/plan-branch.sh create <slug>` — switches and records the base |
| Already on `plan/<slug>` (this plan's slug) | Resume — the branch is this run's earlier work                                   |
| Another plan's `plan/*`, or a dirty tree    | Halt (condition 4) naming the branch or the files                                |

`<slug>` is the plan file's slug (`plan-<slug>.md`). The branch name is the only place the slug
appears in git; task commit messages never carry it. The recorded base is what `/merge-plan`
squashes onto — `main` when you started there, a feature branch when you started on one; it lives in
`.git/config` and disappears with the branch. Wherever this file says `<base>`, read that value with
`~/.claude/scripts/plan-branch.sh base` — never by typing the config key; a mistyped key is a base
`/merge-plan` cannot find, and the script refuses rather than guessing `main`.

## Findings-fix phase (after the Final Task's `claim-reviewer` run)

1. Read the ledger. Take every entry marked `Confirmed` that is not `dismissed`.
2. For each, decide once: would the fix change behavior something depends on (search call sites and
   tests, `rules/decision-policy.md` exception 1)? Yes → mark the entry `needs decision` and leave
   it. No → it goes into the batch.
3. Dispatch **one** `/tdd` invocation carrying the batch, one behavior per finding, each worded as
   the outcome the fix restores plus the file. `--no-commit` runs pass `no-commit plan execution` as
   usual; otherwise `/tdd` commits per cycle on the branch.
4. Take the hashes. Entries in the batch lose their `Confirmed` mark and gain `fixed <hash>`.

## Ship phase (unless `--no-push`)

```bash
git_dir=$(git rev-parse --absolute-git-dir)
touch "$git_dir/fix-ci-active"                                   # marker: sanctions the branch push
~/.claude/scripts/fix-ci-push.sh -u origin plan/<slug>          # the only push path
sha=$(git rev-parse HEAD)
gh run list --commit "$sha" --json databaseId,status,conclusion --limit 5
```

- No run for `$sha` after two polls thirty seconds apart → record `no branch CI` on the ledger as a
  `Confirmed` finding (`.github/workflows — no push trigger for plan/** — the branch is unverified
  until the base's run`; you observed it directly), remove the marker, continue to the squash
  message.
- A run exists → watch it in the background, output redirected to a file under `<scratchpad>` (the
  session's scratchpad directory the harness names in its environment block). No pipe, no `tee`:

  ```bash
  gh run watch <run-id> --exit-status --interval 30 > <scratchpad>/plan-ci-watch.txt 2>&1
  ```

  Re-touch the marker on each poll; it expires after thirty minutes. The watch's exit code is a
  wake-up signal, nothing more — a piped `tee` returns 0 on any run, and `--exit-status` is not a
  gate you read. Never read the watch file as a result.
- On completion, pass the green gate — the only observation the word "green" names:

  ```bash
  gh run view <run-id> --json headSha,status,conclusion
  ```

  Green is exactly `status: completed`, `conclusion: success`, and `headSha` equal to the branch tip
  you pushed. Any other conclusion (`failure`, `cancelled`, `timed_out`, `action_required`) is red.
  This output in your context is what the Ship line `CI green (run <id>)` quotes; without it the
  line is a claim, not a result.
- Green → remove the marker, continue.
- Red → dispatch one `general-purpose` Agent (do not set `model`) with this prompt shape, then
  re-check the run for the new branch tip yourself:

  ```text
  Fix request: CI is red on branch plan/<slug> of <repo path>, head <sha>. Load Skill(fix-ci)
  and run its loop against that branch — this is a fix request, not a read-only ask: commit, push
  through the wrapper, and squash back per the skill. Report the final branch tip and its run's
  conclusion.
  ```

  The agent's own "confirm green" is its exit condition; your own green gate on the run for the new
  branch tip is the ship phase's gate — its report is not your observation. Agent hands back (stop
  condition) → halt 1 with its report. Green → remove the marker, continue.
- Every exit path removes the marker: `rm -f "$git_dir/fix-ci-active"`.

## Squash message

After CI is green (or skipped), load `Skill(write-commit)` and compose one conventional message for
the whole branch:

- Subject and body from the plan's **Goal** and `git diff <base>...HEAD --stat`.
- Body ends with an `Also fixes:` list when the findings-fix phase fixed anything — one line per
  finding, `path — what was wrong`, no hashes.
- No plan slug, no `.planning/` path, no task numbers, no process words (plan, task, cycle, review
  pass, agent, skill). `/merge-plan`'s script commits this file without any guard reading it, so the
  no-internal-words rule holds here by discipline, not by hook.

```bash
git_dir=$(git rev-parse --absolute-git-dir)      # set here too: --no-push skips the ship block above
mkdir -p "$git_dir/plan-squash"
# write the message to "$git_dir/plan-squash/<slug>.msg" with the Write tool
npx --no-install commitlint --edit "$git_dir/plan-squash/<slug>.msg"   # only when the repo has a commitlint config
```

The repo has a commitlint config when a `.commitlintrc*` or `commitlint.config.*` file exists or
`package.json` has a `commitlint` key. A commitlint refusal is a message fix, never a config change.

## `--no-push`

Skips the ship phase entirely: no marker, no push, no CI watch. The squash message is still written
and the Ship section still names the merge command, with `--force` appended.

`--no-commit` implies `--no-push`. The squash message is then composed from the working tree (`git
diff <base> --stat`, not `<base>...HEAD`), and the Ship line reads `uncommitted` in place of the CI
result, so the user knows to commit on the branch before merging.

## Ship section of the final report

```text
Ship: plan/<slug> → <base> — CI green (run <id>) | CI skipped (--no-push) | no branch CI | uncommitted
Merge: /merge-plan [--force]
Optional first: /preflight on the branch, commit its fixes, push again with
  ~/.claude/scripts/fix-ci-push.sh origin plan/<slug> under a fresh marker.
```

The merge line follows the CI result, not your judgment: `CI green` → `/merge-plan`; every other
result → `/merge-plan --force`. `merge-plan.sh` refuses a tip with no CI run, so a bare
`/merge-plan` after `no branch CI` is a command the user runs and watches fail.
