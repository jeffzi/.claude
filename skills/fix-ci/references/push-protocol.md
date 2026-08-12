# Push Protocol — Wrapper Contract, Marker TTL, Signing, Squash-Back

Read this before the first push of a fix request. Read-only asks never reach this file.

## The wrapper contract

Raw `git push` is permission-denied everywhere and never used. **The loop's only push path is the
wrapper** `~/.claude/scripts/fix-ci-push.sh`, which itself refuses to run without a fresh marker,
accepts only `-u`/`--set-upstream`/`--delete`, and rejects every force form and any deletion outside
`fix-ci/*`. The guard additionally allows `git branch -D` scoped to `fix-ci/*` while the marker
exists, and still blocks `--amend` and `--no-verify`.

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

| Target branch    | How                                                                                                                                                                                                                         |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| main/master      | `gh pr merge --squash --delete-branch` — server-side, no local push of main needed                                                                                                                                          |
| a feature branch | `git switch <branch>` → `git merge --squash fix-ci/<slug>` → commit → `~/.claude/scripts/fix-ci-push.sh origin <branch>` → `git branch -D fix-ci/<slug>` → `~/.claude/scripts/fix-ci-push.sh origin --delete fix-ci/<slug>` |

Then confirm the target branch's own new run goes green.
