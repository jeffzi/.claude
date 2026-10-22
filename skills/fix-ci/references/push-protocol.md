# Push Protocol — Wrapper Contract, Marker TTL, Signing, Squash-Back

Read this before the first push of a fix request. Read-only asks never reach this file.

## The wrapper contract

Raw `git push` is permission-denied everywhere and never used. **The loop pushes through the
wrapper** `~/.claude/scripts/fix-ci-push.sh` — every `fix-ci/*` push and deletion, and every
squash-back except onto a target with an open pull request, which lands through `ils push` (§ Squash
back). The wrapper itself refuses to run without a fresh marker, accepts only
`-u`/`--set-upstream`/`--delete`, and rejects every force form and any deletion outside the
assistant's own namespaces, `fix-ci/*` and `plan/*`. The guard additionally allows `git branch -D`
in those two namespaces while the marker exists, and still blocks `--amend` and `--no-verify`. This
loop still deletes only its own `fix-ci/*` branches — `plan/*` is in the namespace for
`execute-plan`'s ship phase, never for this loop to delete.

## Marker TTL

The guard ignores and sweeps markers older than 30 minutes (abandonment fails closed), so re-`touch`
the marker each iteration to keep a long run alive.

## Signing warm-up — the FIRST action of any fix request

Before any `gh` call: when `git config commit.gpgsign` is true, trigger one signature immediately,
while the user is still at the keyboard to approve it — later unattended commits reuse the
authorization. Never for read-only asks (nothing will be committed).

```bash
git tag -s fix-ci-warmup -m warmup && git tag -d fix-ci-warmup
```

## Squash back when the branch's run is green

Message per `Skill(write-commit)`.

Before the branch-name rows, check whether the target has an open pull request against the trunk
(origin's default branch):

```bash
trunk=$(git ls-remote --symref origin HEAD | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2 }')
gh pr list --head <branch> --base "$trunk" --state open --json number,url
```

A non-empty list — a feature branch with a pull request, or a plan branch `execute-plan` shipped
from the trunk — takes the first row. An empty list, a `main`/`master` target, or a failed trunk
read falls through to the rows after it.

| Target branch                       | How                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| open pull request against the trunk | `git switch <branch>` → `git merge --squash fix-ci/<slug>` → commit → `ils push`, run bare: one Bash call, never piped, `tee`d, backgrounded, or behind `cd`. Exit 0 → the target tip's green gate; then `git branch -D fix-ci/<slug>` → `~/.claude/scripts/fix-ci-push.sh origin --delete fix-ci/<slug>`. Exit 4 → run `ils push` again. Exit 1, 2, 5, or any other code → hand back with `ils`'s output. Never `gh pr merge`: the merge is the user's. |
| main/master                         | `gh pr merge --squash --delete-branch` — server-side, no local push of main needed                                                                                                                                                                                                                                                                                                                                                                       |
| a feature branch                    | `git switch <branch>` → `git merge --squash fix-ci/<slug>` → commit → `~/.claude/scripts/fix-ci-push.sh origin <branch>` → `git branch -D fix-ci/<slug>` → `~/.claude/scripts/fix-ci-push.sh origin --delete fix-ci/<slug>`                                                                                                                                                                                                                              |
| `plan/<slug>`, no open pull request | Same as a feature branch: `git switch plan/<slug>` → `git merge --squash fix-ci/<slug>` → commit → `~/.claude/scripts/fix-ci-push.sh origin plan/<slug>` → `git branch -D fix-ci/<slug>` → `~/.claude/scripts/fix-ci-push.sh origin --delete fix-ci/<slug>`. Never its base: the plan branch reaches the branch it was created from only through the user's `/release merge`.                                                                            |

On every row but the first, then locate the run for the target branch's new tip (`gh run list
--commit $(git rev-parse HEAD)`, never `.[0]` of an unfiltered list), watch it, and pass the green
gate on it — this loop's exit condition. The squash push itself proves nothing; the report names
this run's id and conclusion. On the first row, `ils push`'s exit 0 is that gate, and the report
cites its output in place of a run id. When `execute-plan` dispatched the loop, its ship phase
re-checks the branch tip itself as the gate; report the final tip and its conclusion, or the exit
code of the last `ils push`, so it can.
