# Push Protocol — Wrapper Contract, Marker TTL, Signing, Squash-Back

Read this before the first push of a fix request. Read-only asks never reach this file.

## The wrapper contract

Raw `git push` is permission-denied everywhere and never used. **The loop's only push path is the
wrapper** `~/.claude/scripts/fix-ci-push.sh`, which itself refuses to run without a fresh marker,
accepts only `-u`/`--set-upstream`/`--delete`, and rejects every force form and any deletion outside
the assistant's own namespaces, `fix-ci/*` and `plan/*`. The guard additionally allows `git branch
-D` in those two namespaces while the marker exists, and still blocks `--amend` and `--no-verify`.
This loop still deletes only its own `fix-ci/*` branches — `plan/*` is in the namespace for
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

Message per `Skill(write-commit)`:

| Target branch    | How                                                                                                                                                                                                                                                                                                                                                                           |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| main/master      | `gh pr merge --squash --delete-branch` — server-side, no local push of main needed                                                                                                                                                                                                                                                                                            |
| a feature branch | `git switch <branch>` → `git merge --squash fix-ci/<slug>` → commit → `~/.claude/scripts/fix-ci-push.sh origin <branch>` → `git branch -D fix-ci/<slug>` → `~/.claude/scripts/fix-ci-push.sh origin --delete fix-ci/<slug>`                                                                                                                                                   |
| `plan/<slug>`    | Same as a feature branch: `git switch plan/<slug>` → `git merge --squash fix-ci/<slug>` → commit → `~/.claude/scripts/fix-ci-push.sh origin plan/<slug>` → `git branch -D fix-ci/<slug>` → `~/.claude/scripts/fix-ci-push.sh origin --delete fix-ci/<slug>`. Never its base: the plan branch reaches the branch it was created from only through the user's `/release merge`. |

Then locate the run for the target branch's new tip (`gh run list --commit $(git rev-parse HEAD)`,
never `.[0]` of an unfiltered list), watch it, and pass the green gate on it — this loop's exit
condition. The squash push itself proves nothing; the report names this run's id and conclusion.
When `execute-plan` dispatched the loop, its ship phase re-checks the run for the branch tip itself
as the gate; report the final tip and its conclusion so it can.
