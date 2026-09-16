#!/usr/bin/env bash
set -euo pipefail

# Drive a release branch: cut it from main, report where it stands, land plan
# branches on it, and ship it.
#
# Usage: release.sh start <X.Y.Z> [--adopt]
#        release.sh status
#        release.sh merge [plan/<slug>] [--force]
#        release.sh finish (--check|--push|--publish) [--force] [--gh-release]
#
# The user runs this through /release, which raises the
# `$GIT_DIR/release-active` marker every subcommand but `status` requires. The
# writes here — a branch cut, a squash, a fast-forward of main — would be
# invisible to the Bash guard's subcommand parser, so the guard gates
# invocations on the same marker; two layers over the same hole.
#
# Which branch is the release is read from `branch.<name>.release`, never
# guessed from a name, so a repo with a `v1.2` branch nobody opened stays alone.
#
# Every precondition is checked before anything is changed: a refusal (exit 2)
# leaves the repo exactly as it was found. Once something is written, a later
# failure (exit 1, a rejected push) keeps it and names what was kept, so the run
# can be retried after the cause is fixed.

# Marker freshness shared with the guard that gates invocations of this script,
# the release and planBase config keys, the clean-tree precondition, and help
# handling.
# shellcheck source=SCRIPTDIR/branch-policy.sh
. "${BASH_SOURCE[0]%/*}/branch-policy.sh"
PROG=release

readonly USAGE="usage: release.sh start <X.Y.Z> [--adopt]
       release.sh status
       release.sh merge [plan/<slug>] [--force]
       release.sh finish (--check|--push|--publish) [--force] [--gh-release]"

# The branch every release is cut from and lands back on.
readonly TRUNK=main

# The file `finish --gh-release` reads the release body out of, at the repo root.
readonly CHANGELOG_FILE=CHANGELOG.md

# ── Shared helpers ───────────────────────────────────────────────────────────

# The marker proves the run came through /release; a stale or future-dated one
# proves nothing and reads as absent, exactly as the fix-ci marker does.
require_release_marker() {
	local marker="$1/$RELEASE_MARKER" status=0
	marker_fresh "$marker" || status=$?
	die_if_stat_unusable "$status"
	((status == 0)) ||
		die "no fresh marker at $marker; this script runs only through /release, which the user invokes."
}

# Prints the checked-out branch, or a phrase naming the detached state — either
# way a refusal can quote it back.
current_branch() {
	git symbolic-ref --quiet --short HEAD || printf 'a detached HEAD'
}

# A diagnostic the run survives. Refusals and failures use die; this is for what
# the user should know about a step that still did its job.
warn() {
	printf '%s: %s\n' "$PROG" "$1" >&2
}

# Switches to $1, or dies naming it; $2 sets die's exit status, defaulting the
# same way die itself does, and $3 names what the failure keeps for callers that
# switch after a write. Shared by merge and finish, which both rewrite a branch
# only after landing on it.
switch_or_die() {
	local branch="$1" status="${2:-}" kept="${3:-nothing changed}"
	git switch --quiet "$branch" || die "could not switch to $branch; $kept." "$status"
}

# Prints "<branch> <version>" for the branch carrying the release key, and
# nothing when no release is open. The key is what opens a release, so only one
# branch may hold it; the first match answers.
open_release() {
	local entry key branch version
	entry=$(git config --get-regexp "^branch\..+\.$RELEASE_KEY\$") || return 0
	entry=${entry%%$'\n'*}
	key=${entry%% *}
	version=${entry#* }
	branch=${key#branch.}
	branch=${branch%".$RELEASE_KEY"}
	printf '%s %s' "$branch" "$version"
}

# Refuses while any branch carries the release key: a second open release would
# leave `status` and the guard picking one of them arbitrarily.
require_no_open_release() {
	local open="$1"
	[[ -z "$open" ]] ||
		die "'${open%% *}' already carries the $RELEASE_KEY key (${open#* }); finish that release before starting another."
}

# ── start ────────────────────────────────────────────────────────────────────

# Sets the caller's `version` and `adopt` from argv.
parse_start_args() {
	local arg
	version=""
	adopt=false
	for arg in "$@"; do
		case "$arg" in
		--adopt) adopt=true ;;
		-*) die "unknown option '$arg'; $USAGE" ;;
		*)
			[[ -z "$version" ]] ||
				die "unexpected argument '$arg'; start takes one version, and already has '$version'."
			version="$arg"
			;;
		esac
	done
	[[ -n "$version" ]] ||
		die "start needs a version, as in 'release.sh start 1.2.0'; $USAGE"
	[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
		die "'$version' is not a version; start takes X.Y.Z, as in 1.2.0."
}

# Records the version on the branch already checked out, which the user cut and
# pushed by hand. Nothing is created or pushed, so the only preconditions are
# the ones that make the branch a plausible release: it is not the trunk, and it
# holds everything the trunk holds.
adopt_current_branch() {
	local branch="$1" version="$2"
	[[ "$branch" != "$TRUNK" ]] ||
		die "--adopt records the $RELEASE_KEY key on the branch you are on, and $TRUNK is never the release branch."
	git merge-base --is-ancestor "$TRUNK" "$branch" ||
		die "'$branch' does not contain $TRUNK; rebase it onto $TRUNK, then re-run."

	git config "branch.$branch.$RELEASE_KEY" "$version"
	printf 'release: %s adopted as the release branch for %s.\n' "$branch" "$version"
}

# Pushes $1 to origin with upstream tracking, or dies naming what a rejected
# push keeps: the branch and its RELEASE_KEY key, already written by both
# cut_release_branch and resume_cut before this runs.
push_release_branch() {
	local release_branch="$1"
	git push --quiet --set-upstream origin "$release_branch" ||
		die "pushing $release_branch to origin failed; the branch and its $RELEASE_KEY key are kept, so re-run once the remote is reachable." 1
}

# Cuts vX.Y from the trunk and pushes it. The branch is created before the push,
# so a rejected push keeps it and its key rather than unwinding a branch the
# user may already be working on.
cut_release_branch() {
	local branch="$1" version="$2" release_branch="$3" local_trunk remote_trunk
	[[ "$branch" == "$TRUNK" ]] ||
		die "release start cuts the branch from $TRUNK; you are on '$branch'."
	require_clean_worktree
	! git show-ref --quiet --verify "refs/heads/$release_branch" ||
		die "$release_branch already exists; that minor is already cut."
	git fetch --quiet origin "$TRUNK" ||
		die "'git fetch origin $TRUNK' failed; fix the remote, then re-run."
	local_trunk=$(git rev-parse --verify "refs/heads/$TRUNK")
	remote_trunk=$(git rev-parse --verify FETCH_HEAD)
	[[ "$local_trunk" == "$remote_trunk" ]] ||
		die "local $TRUNK ($(git rev-parse --short "$local_trunk")) differs from origin/$TRUNK ($(git rev-parse --short "$remote_trunk")); sync it first."

	git switch --quiet -c "$release_branch" "$TRUNK"
	git config "branch.$release_branch.$RELEASE_KEY" "$version"
	push_release_branch "$release_branch"
	printf 'release: %s cut from %s for %s and pushed.\n' "$release_branch" "$TRUNK" "$version"
}

# Finishes a cut whose push failed: the branch and its key are already there, so
# the push is all that is left. Origin having the branch already means the cut
# went through and this is a second start, not a resume, and is refused as one.
resume_cut() {
	local release_branch="$1" version="$2" status=0
	require_clean_worktree
	git ls-remote --exit-code --heads origin "$release_branch" >/dev/null || status=$?
	case "$status" in
	2) ;;
	0) die "'$release_branch' already carries the $RELEASE_KEY key ($version) and origin has it; the cut is done, so plan onto it or finish it." ;;
	*) die "'git ls-remote origin $release_branch' failed; fix the remote, then re-run." ;;
	esac

	switch_or_die "$release_branch"
	push_release_branch "$release_branch"
	printf 'release: %s was already cut for %s and is now pushed.\n' "$release_branch" "$version"
}

cmd_start() {
	local version adopt branch open release_branch
	parse_start_args "$@"
	branch=$(current_branch)
	open=$(open_release)
	release_branch="v${version%.*}"

	if ! $adopt && [[ "$open" == "$release_branch $version" ]]; then
		resume_cut "$release_branch" "$version"
		return
	fi
	require_no_open_release "$open"

	if $adopt; then
		adopt_current_branch "$branch" "$version"
	else
		cut_release_branch "$branch" "$version" "$release_branch"
	fi
}

# ── status ───────────────────────────────────────────────────────────────────

# Prints "<label>: none", or the label with $2's lines listed under it.
print_list() {
	local label="$1" lines="$2" line
	if [[ -z "$lines" ]]; then
		printf '%s: none\n' "$label"
		return
	fi
	printf '%s:\n' "$label"
	while IFS= read -r line; do
		printf '  %s\n' "$line"
	done <<<"$lines"
}

# Prints the plan branches recording $1 as their base that $1 does not already
# contain, one per line.
unmerged_plan_branches() {
	local release_branch="$1" plan recorded
	while IFS= read -r plan; do
		recorded=$(git config --get "branch.$plan.$PLAN_BASE_CONFIG_KEY") || continue
		[[ "$recorded" == "$release_branch" ]] || continue
		git merge-base --is-ancestor "$plan" "$release_branch" || printf '%s\n' "$plan"
	done < <(git for-each-ref --format='%(refname:short)' "refs/heads/$PLAN_BRANCH_PREFIX*")
}

# Prints how $1 stands against its origin counterpart, read from the local
# remote-tracking ref. status never fetches — it must stay usable offline and
# mid-conflict — so this reports what the last fetch or push recorded.
origin_standing() {
	local branch="$1" behind ahead
	git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null || {
		printf 'absent'
		return 0
	}
	read -r behind ahead <<<"$(git rev-list --left-right --count "origin/$branch...$branch")"
	printf '%s ahead, %s behind' "$ahead" "$behind"
}

# Read-only, and the one subcommand that runs without the marker: a skill reads
# the first line to learn the open release without touching git config itself.
cmd_status() {
	local open branch version arg
	for arg in "$@"; do
		case "$arg" in
		-*) die "unknown option '$arg'; $USAGE" ;;
		*) die "unexpected argument '$arg'; status takes none; $USAGE" ;;
		esac
	done
	open=$(open_release)
	if [[ -z "$open" ]]; then
		printf 'release: none\n'
		return
	fi
	branch=${open%% *}
	version=${open#* }

	printf 'release: %s %s\n' "$branch" "$version"
	print_list "commits beyond $TRUNK" "$(git log --format='%h %s' "$TRUNK..$branch")"
	print_list "unmerged plan branches" "$(unmerged_plan_branches "$branch")"
	printf 'origin/%s: %s\n' "$branch" "$(origin_standing "$branch")"
	if git merge-base --is-ancestor "$TRUNK" "$branch"; then
		printf '%s: is an ancestor of %s\n' "$TRUNK" "$branch"
	else
		printf '%s: has moved past the fork point\n' "$TRUNK"
	fi
}

# ── merge ────────────────────────────────────────────────────────────────────

# Sets the caller's `branch` and `force` from argv; `branch` stays empty for
# "use the branch that is checked out".
parse_merge_args() {
	local arg
	branch=""
	force=false
	for arg in "$@"; do
		case "$arg" in
		--force) force=true ;;
		-*) die "unknown option '$arg'; $USAGE" ;;
		*)
			[[ -z "$branch" ]] || die "only one branch may be named, got '$branch' and '$arg'."
			branch="$arg"
			;;
		esac
	done
}

# Prints the plan branch: $1 when argv named one, else HEAD's branch. Rejects
# anything outside plan/*.
resolve_plan_branch() {
	local branch="$1"
	if [[ -z "$branch" ]]; then
		branch=$(git symbolic-ref --quiet --short HEAD) ||
			die "HEAD is detached; name the branch, as in 'release.sh merge plan/<slug>'."
	fi
	[[ "$branch" == "$PLAN_BRANCH_PREFIX"* ]] ||
		die "'$branch' is not a plan branch; only plan/* branches are merged."
	git show-ref --quiet --verify "refs/heads/$branch" ||
		die "'$branch' is not a local branch."
	printf '%s' "$branch"
}

# Prints the branch the plan lands on: the base recorded by the run that created
# the plan branch, and nothing else. A missing or unusable record is a refusal
# rather than a fall back to the trunk, which would land a plan on a branch it
# was never cut from. The record must name a local branch, since the commits are
# made on it here.
resolve_base_branch() {
	local branch="$1" key recorded
	key="branch.$branch.$PLAN_BASE_CONFIG_KEY"
	recorded=$(git config --get "$key") || recorded=""
	[[ -n "$recorded" ]] ||
		die "$key is unset, so there is no recorded base to merge '$branch' onto; branches from 'plan-branch.sh create' carry it, or record one with 'git config $key <branch>'."
	git show-ref --quiet --verify "refs/heads/$recorded" ||
		die "'$branch' records '$recorded' as its base, but that is not a local branch; restore it, or re-record one with 'git config $key <branch>'."
	printf '%s' "$recorded"
}

require_message_file() {
	local msg_file="$1"
	[[ -f "$msg_file" ]] ||
		die "no squash message at $msg_file; the plan run writes it when CI goes green."
	[[ -s "$msg_file" ]] ||
		die "the squash message at $msg_file is empty."
}

# "1 commit" or "N commits", for a message counting how far two tips stand apart.
commits_phrase() {
	local count="$1"
	if ((count == 1)); then
		printf '1 commit'
	else
		printf '%s commits' "$count"
	fi
}

# Says which side of $1 holds what the other lacks — $2 commits local-only, $3
# origin-only — and the way back. $4 is appended to the behind case's pull, for
# a caller whose own branch has to follow the one it is updating.
out_of_sync_detail() {
	local branch="$1" ahead="$2" behind="$3" follow_up="${4:-}"
	if ((ahead > 0 && behind > 0)); then
		printf '%s has %s origin lacks and origin/%s has %s the local branch lacks. Reconcile the branch with origin, then re-run.' \
			"$branch" "$(commits_phrase "$ahead")" "$branch" "$(commits_phrase "$behind")"
	elif ((ahead > 0)); then
		printf "%s has %s origin lacks. Push it with 'git push origin %s', then re-run." \
			"$branch" "$(commits_phrase "$ahead")" "$branch"
	else
		printf "origin/%s has %s the local branch lacks. Update it with 'git pull --ff-only origin %s'%s, then re-run." \
			"$branch" "$(commits_phrase "$behind")" "$branch" "$follow_up"
	fi
}

# Refuses unless the local branch is exactly its origin counterpart, so the work
# lands on something nobody else has moved; prints the sha origin answered with,
# which the fold later takes its push lease against. $2 is handed to
# out_of_sync_detail for the behind case.
require_branch_in_sync() {
	local branch="$1" follow_up="${2:-}" local_sha remote_sha ahead behind
	git fetch --quiet origin "$branch" ||
		die "'git fetch origin $branch' failed; fix the remote, then re-run."
	local_sha=$(git rev-parse --verify --quiet "refs/heads/$branch") ||
		die "this repo has no local '$branch' branch."
	remote_sha=$(git rev-parse --verify FETCH_HEAD) ||
		die "origin has no '$branch' branch."
	if [[ "$local_sha" != "$remote_sha" ]]; then
		read -r ahead behind <<<"$(git rev-list --left-right --count "$local_sha...$remote_sha")"
		die "local $branch ($(git rev-parse --short "$local_sha")) differs from origin/$branch ($(git rev-parse --short "$remote_sha")): $(out_of_sync_detail "$branch" "$ahead" "$behind" "$follow_up")"
	fi
	printf '%s' "$remote_sha"
}

# Refuses while origin carries a copy of the plan branch at another commit: the
# squash would land a tip nobody else has seen, and the CI gate would judge a
# tip origin never ran. Read from the remote-tracking ref a fetch or a push of
# the branch leaves behind, so a tip origin never had — the ordinary
# never-pushed branch — merges, and a tracking ref left behind by someone else's
# push is a refusal the user clears with a fetch.
require_plan_branch_matches_origin() {
	local branch="$1" tip="$2" remote_sha
	remote_sha=$(git rev-parse --verify --quiet "refs/remotes/origin/$branch") || return 0
	[[ "$remote_sha" == "$tip" ]] ||
		die "origin/$branch ($(git rev-parse --short "$remote_sha")) differs from local $branch ($(git rev-parse --short "$tip")); push $branch, or fetch it if origin's copy is the newer one, then re-run."
}

# Refuses unless the base is an ancestor of the branch tip, which is what makes
# the squash commit's tree the branch tip's tree rather than a merge of the two.
require_branch_contains_base() {
	local branch="$1" base_branch="$2"
	git merge-base --is-ancestor "$base_branch" "$branch" ||
		die "'$branch' does not contain $base_branch; rebase the branch onto $base_branch, then re-run."
}

# Refuses unless the newest run gh reports for the branch tip concluded success.
# `--force` skips this gate only; every other check always runs. Both the merge
# and the publish stand on it, so the reasons name neither.
require_ci_success() {
	local branch="$1" tip="$2" summary
	command -v gh >/dev/null ||
		die "gh is not installed; re-run with --force to act without the CI check."
	summary=$(gh run list --commit "$tip" --limit 1 --json status,conclusion \
		--jq '.[0] | if . == null then "none" else "\(.status) \(.conclusion)" end') ||
		die "'gh run list' failed for $tip; re-run with --force to act without the CI check."
	[[ "$summary" != "none" ]] ||
		die "no CI run found for $branch tip $tip; push the branch, or re-run with --force."
	[[ "$summary" == *" success" ]] ||
		die "the latest CI run for $branch tip $tip is '$summary'; only a green branch is landed or released."
}

# Prefix `git commit --fixup` gives a commit's subject; shared by every check
# that tells a fixup from a plain commit.
readonly FIXUP_PREFIX='fixup! '

# The other two subjects autosquash acts on, from `git commit --squash` and
# `--fixup=amend:`. Both stop an interactive rebase for an editor, which the
# scripted replay answers with `:` — it would take the message git offers,
# silently, so the fold refuses them instead of guessing.
readonly SQUASH_PREFIX='squash! '
readonly AMEND_PREFIX='amend! '

# Refuses while $1..$2 holds a commit the replay cannot carry: a merge commit,
# whose second parent a rebase drops, or a squash!/amend! commit. Runs before
# anything is written, so either is the ordinary "nothing changed" refusal.
require_replayable_history() {
	local base_branch="$1" branch="$2" merge sha subject
	merge=$(git rev-list --merges --max-count=1 "$base_branch..$branch")
	[[ -z "$merge" ]] ||
		die "'$branch' holds the merge commit $(git log -1 --format='%h %s' "$merge"); a fold replays only linear fixup! and ordinary commits, so rebase '$branch' onto $base_branch, then re-run."
	while read -r sha subject; do
		case "$subject" in
		"$SQUASH_PREFIX"* | "$AMEND_PREFIX"*)
			die "'$branch' holds $sha $subject; a fold replays only linear fixup! and ordinary commits, so reword it or apply it by hand, then re-run."
			;;
		esac
	done < <(git log --format='%h %s' "$base_branch..$branch")
}

# Where HEAD points, in the form return_to_head_position puts it back: a branch
# name, or the sha HEAD is detached at.
head_position() {
	git symbolic-ref --quiet --short HEAD || git rev-parse HEAD
}

# Puts HEAD back on the position head_position printed, detaching again when
# that position is a sha. $2 names what a failed switch leaves behind and $3 is
# the exit status it reports.
return_to_head_position() {
	local position="$1" kept="${2:-nothing changed}" status="${3:-}"
	if git show-ref --quiet --verify "refs/heads/$position"; then
		switch_or_die "$position" "$status" "$kept"
	else
		git switch --detach --quiet "$position" ||
			die "could not put HEAD back on $position; $kept." "$status"
	fi
}

# Subjects of the fixup commits $2 carries beyond $1, one per line.
fixup_subjects() {
	local subject
	while IFS= read -r subject; do
		if [[ "$subject" == "$FIXUP_PREFIX"* ]]; then
			printf '%s\n' "$subject"
		fi
	done < <(git log --format=%s "$1..$2")
}

# How many commits $2 carries beyond $1 are not fixups. This decides whether the
# fold needs a squash commit — and so a message file — at all; where the base
# ends after the replay is counted on the rewritten branch instead, since the
# replay may drop a commit it finds empty.
plain_commit_count() {
	local subject count=0
	while IFS= read -r subject; do
		if [[ "$subject" != "$FIXUP_PREFIX"* ]]; then
			count=$((count + 1))
		fi
	done < <(git log --format=%s "$1..$2")
	printf '%d' "$count"
}

# Commits in $1..$2 whose subject is exactly $3, as "<short sha> <subject>" lines.
commits_with_subject() {
	local range_start="$1" range_end="$2" want="$3" sha subject
	while read -r sha subject; do
		if [[ "$subject" == "$want" ]]; then
			printf '%s %s\n' "$sha" "$subject"
		fi
	done < <(git log --format='%h %s' "$range_start..$range_end")
}

# Refuses unless folding the plan branch's fixups into $2 is safe: only a release
# branch is rewritten, every fixup names exactly one commit the release carries,
# and nothing else is pinned to the base a fold rewrites.
require_foldable() {
	local branch="$1" base_branch="$2" fork="$3" subject target matches other recorded
	git config --get "branch.$base_branch.$RELEASE_KEY" >/dev/null ||
		die "'$branch' holds fixup! commits, but '$base_branch' carries no $RELEASE_KEY key; folding rewrites the base, so it is offered on a release branch only."

	while IFS= read -r subject; do
		target=${subject#"$FIXUP_PREFIX"}
		matches=$(commits_with_subject "$fork" "$base_branch" "$target")
		[[ -n "$matches" ]] ||
			die "'$subject' names no commit on $base_branch since it forked from $TRUNK; fix the subject, then re-run."
		[[ "$matches" != *$'\n'* ]] ||
			die "'$subject' names two commits on $base_branch — ${matches//$'\n'/ and } — and autosquash would silently fold into one of them; reword one of the two, then re-run."
	done < <(fixup_subjects "$base_branch" "$branch")

	while IFS= read -r other; do
		[[ "$other" != "$branch" ]] || continue
		recorded=$(git config --get "branch.$other.$PLAN_BASE_CONFIG_KEY") || continue
		[[ "$recorded" == "$base_branch" ]] || continue
		die "'$other' also records $base_branch as its base, and the fold rewrites $base_branch out from under it; land or re-base '$other' first."
	done < <(git for-each-ref --format='%(refname:short)' "refs/heads/$PLAN_BRANCH_PREFIX*")
}

# Whether branch $1 points at $2.
branch_at() {
	local sha
	sha=$(git rev-parse --verify --quiet "refs/heads/$1") || return 1
	[[ "$sha" == "$2" ]]
}

# Forces branch $1 back to $2, writing nothing when it is already there: what
# failed may be the very write that would have moved it, and that write can have
# failed because this ref is one git cannot update at all.
restore_branch() {
	local branch="$1" want="$2"
	branch_at "$branch" "$want" || git branch --force "$branch" "$want"
}

# Drops what the run staged and wrote, leaving HEAD's commit as the tree again.
# A failed commit keeps the squash in the index, where the next run reads it as
# the user's own work and refuses; discarding it is safe because the run gates on
# a clean worktree before it writes anything, so all there is to drop is its own.
discard_uncommitted() {
	git reset --quiet --hard
}

# How a restore of $1 (pre-fold $2) and $3 (pre-fold $4) describes itself: only
# the branches the fold actually moved are named, and the tree, which comes back
# with them. Read before the restore runs, since after it every branch is back at
# its sha.
restored_phrase() {
	local base_branch="$1" base_before="$2" branch="$3" plan_before="$4" moved=()
	branch_at "$base_branch" "$base_before" || moved+=("$base_branch")
	branch_at "$branch" "$plan_before" || moved+=("$branch")
	case "${#moved[@]}" in
	0) printf '%s and %s are as the run found them' "$base_branch" "$branch" ;;
	1) printf '%s was restored to its pre-fold tip, and the tree with it' "${moved[0]}" ;;
	*) printf '%s, %s and the tree were restored to their pre-fold tips' "${moved[0]}" "${moved[1]}" ;;
	esac
}

# Puts $1 back at $2 — and $3 back at $4, when a plan branch was rewritten too;
# pass an empty $3 when it was not — then returns HEAD to the position $5. The
# tree goes first, since a squash left in the index would otherwise ride the
# switch across; HEAD is detached next because a checked-out branch cannot be
# force-updated at all. Answers non-zero when a step fails, leaving the caller
# with only the shas to offer the user.
restore_branches() {
	local base_branch="$1" base_before="$2" branch="$3" plan_before="$4" start="$5"
	discard_uncommitted || return 1
	git switch --detach --quiet "$base_before" || return 1
	[[ -z "$branch" ]] || restore_branch "$branch" "$plan_before" || return 1
	restore_branch "$base_branch" "$base_before" || return 1
	return_to_head_position "$start" "the branches are back where the run found them" 1
}

# Puts the fold back where it found the two branches and then fails with $1,
# naming the restore. A restore that fails itself leaves the two shas as the
# only way back, so they are printed with the commands that use them. $2 is the
# exit status of the ordinary path: a refusal before the base moved, 1 once
# something was written.
#
# The shas come from the caller, captured before the rebase ran: the replay
# rewrites ORIG_HEAD as it goes, so by the time a push is rejected it no longer
# points at the branch the run started with.
restore_fold_or_die() {
	local reason="$1" status="$2" branch="$3" base_branch="$4" plan_before="$5" base_before="$6" start="$7"
	local restored
	restored=$(restored_phrase "$base_branch" "$base_before" "$branch" "$plan_before")
	restore_branches "$base_branch" "$base_before" "$branch" "$plan_before" "$start" ||
		die "$reason, and restoring the branches failed; recover with 'git branch -f $base_branch $base_before' and 'git branch -f $branch $plan_before'." 1
	die "$reason; $restored." "$status"
}

# Replays the plan branch from the release branch's fork point with autosquash,
# so each fixup lands in the commit it names, then moves the base onto the
# replayed release commits and sets the caller's `fold_remaining` to how many
# commits the plan branch keeps above them.
#
# The base ends where the release commits end, counted: the replay may drop a
# commit whose change the fold already put in the base, and two release commits
# may share a subject, so neither the plan branch's own commit count nor any
# subject locates it. Leaves HEAD on the plan branch.
fold_fixups() {
	local branch="$1" base_branch="$2" fork="$3" release_count="$4" plan_before="$5" base_before="$6" start="$7"
	local culprit aborted=true total
	switch_or_die "$branch"
	if ! GIT_SEQUENCE_EDITOR=: git rebase --interactive --autosquash --empty=drop "$fork" >/dev/null 2>&1; then
		culprit=$(git log -1 --format='%h %s' REBASE_HEAD 2>/dev/null) || culprit="an unknown commit"
		git rebase --abort >/dev/null 2>&1 || aborted=false
		$aborted ||
			die "replaying $branch over $base_branch stopped on $culprit, and 'git rebase --abort' failed too; the repo is mid-rebase." 1
		return_to_head_position "$start"
		die "replaying $branch over $base_branch stopped on $culprit; the rebase was aborted, so $branch and $base_branch are as they were. Resolve that conflict on $branch, then re-run."
	fi
	total=$(git rev-list --count "$fork..$branch")
	((total >= release_count)) ||
		restore_fold_or_die "the fold left $total commits above the fork point, fewer than the $release_count $base_branch carried, so a fixup cancels a release commit out and the fold would drop it" \
			2 "$branch" "$base_branch" "$plan_before" "$base_before" "$start"
	fold_remaining=$((total - release_count))
	git branch --force "$base_branch" "$branch~$fold_remaining" ||
		restore_fold_or_die "moving $base_branch onto the folded commits failed" 1 \
			"$branch" "$base_branch" "$plan_before" "$base_before" "$start"
}

# Leaves the squash commit on the base; every later step is cleanup that keeps
# it. Answers with the reason to fail with on stdout and a status telling the
# two kinds of failure apart — 2 while nothing is written yet, 1 once the squash
# has touched the index — because what a failure leaves behind differs between
# the callers: the fold has a rewritten base and plan branch to put back, the
# plain squash has written nothing of its own.
squash_onto_base() {
	local branch="$1" base_branch="$2" msg_file="$3"
	git switch --quiet "$base_branch" || {
		printf 'could not switch to %s' "$base_branch"
		return 2
	}
	git merge --squash "$branch" >/dev/null || {
		printf 'squash-merging %s into %s failed' "$branch" "$base_branch"
		return 1
	}
	git commit --quiet --file "$msg_file" || {
		printf 'committing the squash of %s onto %s failed' "$branch" "$base_branch"
		return 1
	}
}

# Pushes the rewritten base under a lease on the sha origin answered the opening
# fetch with, so a base someone else moved in between is rejected rather than
# overwritten.
#
# Whether that is what happened is read from origin itself rather than from
# git's rejection text: a lease refused against the stale remote-tracking ref
# reads "stale info", one refused by the receiving end reads "incorrect old
# value provided", and only origin's current sha separates either from a remote
# that is simply unreachable.
#
# A moved origin is not fixed by a fetch alone: the restore puts $1 back at its
# pre-fold tip, which a bare re-run then refuses as differing from origin, so
# the reason names the update and the replay that make a re-run land. $3 is the
# plan branch and $4 the base's pre-fold tip, which is where $3 forks from once
# the restore has run.
#
# Answers non-zero with git's own output on stderr and the reason to refuse with
# on stdout: the caller owns what happens to the fold, which has to come back
# before the run exits either way.
push_folded_base() {
	local base_branch="$1" origin_sha="$2" branch="$3" base_before="$4" output status=0 remote_sha
	output=$(git push --quiet --force-with-lease="$base_branch:$origin_sha" origin "$base_branch" 2>&1) || status=$?
	((status != 0)) || return 0
	printf '%s\n' "$output" >&2
	remote_sha=$(git ls-remote origin "refs/heads/$base_branch" 2>/dev/null | cut -f1) || remote_sha=""
	if [[ -n "$remote_sha" && "$remote_sha" != "$origin_sha" ]]; then
		printf "pushing %s to origin was rejected: origin/%s moved since this run fetched it. Catch %s up and replay %s on it with 'git switch %s && git pull --ff-only origin %s' and 'git rebase --onto %s %s %s', then re-run; fetching alone leaves %s behind origin, which a re-run refuses" \
			"$base_branch" "$base_branch" "$base_branch" "$branch" "$base_branch" \
			"$base_branch" "$base_branch" "$base_before" "$branch" "$base_branch"
	else
		printf "pushing %s to origin failed, so run 'git fetch origin %s' and re-run once the remote is reachable" \
			"$base_branch" "$base_branch"
	fi
	return 1
}

# Drops the branch here and on origin (when origin has it) and the message file.
# Runs only after origin has the new base, so nothing unpushed is lost.
# `ls-remote --exit-code` answers 2 for "no such ref"; any other failure is the
# remote itself, which must not read as "nothing to delete".
clean_up_branch() {
	local branch="$1" base_branch="$2" msg_file="$3" status=0
	git ls-remote --exit-code --heads origin "$branch" >/dev/null || status=$?
	case "$status" in
	0)
		git push --quiet origin --delete "$branch" ||
			die "deleting $branch from origin failed; $base_branch is already pushed." 1
		;;
	2) ;;
	*)
		die "'git ls-remote origin $branch' failed; $base_branch is already pushed, $branch was not deleted." 1
		;;
	esac
	git branch --quiet -D "$branch" ||
		die "deleting the local $branch failed; $base_branch is already pushed." 1
	rm -f "$msg_file"
}

# A plan branch lands one of two ways. With no fixups it is squashed onto its
# base and pushed plainly, whatever the base is. With fixups it is replayed over
# a release branch so each fixup joins the commit it amends, which rewrites the
# release branch and so pushes under a lease; the base's pre-fold tip is printed,
# since that sha is all a recovery needs.
cmd_merge() {
	local git_dir="$1"
	shift
	local branch force base_branch slug msg_file tip origin_sha fixups fork plain_count
	local start base_before release_count fold_remaining reason squash_status
	parse_merge_args "$@"
	branch=$(resolve_plan_branch "$branch")
	base_branch=$(resolve_base_branch "$branch")
	slug=${branch#"$PLAN_BRANCH_PREFIX"}
	msg_file="$git_dir/plan-squash/$slug.msg"
	tip=$(git rev-parse --verify "refs/heads/$branch")
	start=$(head_position)

	require_clean_worktree
	require_branch_contains_base "$branch" "$base_branch"
	require_replayable_history "$base_branch" "$branch"
	origin_sha=$(require_branch_in_sync "$base_branch" " and rebase $branch onto it")
	require_plan_branch_matches_origin "$branch" "$tip"
	$force || require_ci_success "$branch" "$tip"

	fixups=$(fixup_subjects "$base_branch" "$branch")
	plain_count=$(plain_commit_count "$base_branch" "$branch")
	base_before=$(git rev-parse --verify "refs/heads/$base_branch")
	if [[ -z "$fixups" ]]; then
		require_message_file "$msg_file"
		squash_status=0
		reason=$(squash_onto_base "$branch" "$base_branch" "$msg_file") || squash_status=$?
		if ((squash_status != 0)); then
			# Status 2 never reached the index; 1 has the squash sitting in it, and
			# "nothing here changed" holds again only once that squash is gone.
			if ((squash_status != 2)); then
				discard_uncommitted
				return_to_head_position "$start" "$base_branch and $branch are untouched" 1
			fi
			die "$reason; nothing here changed." "$squash_status"
		fi
		git push --quiet origin "$base_branch" || {
			restore_branches "$base_branch" "$base_before" "" "" "$start" ||
				die "pushing $base_branch to origin failed, and restoring $base_branch failed too; recover with 'git branch -f $base_branch $base_before'." 1
			die "pushing $base_branch to origin failed; $base_branch was restored to its pre-squash tip, and $branch and $msg_file are untouched, so re-run once the remote is reachable." 1
		}
		clean_up_branch "$branch" "$base_branch" "$msg_file"
		printf 'release: %s squashed onto %s and pushed.\n' "$branch" "$base_branch"
		return
	fi

	fork=$(git merge-base "$TRUNK" "$base_branch") ||
		die "'$base_branch' shares no history with $TRUNK, so there is no range for the fold to replay."
	require_foldable "$branch" "$base_branch" "$fork"
	((plain_count == 0)) || require_message_file "$msg_file"

	release_count=$(git rev-list --count "$fork..$base_branch")
	fold_fixups "$branch" "$base_branch" "$fork" "$release_count" "$tip" "$base_before" "$start"
	if ((fold_remaining > 0)); then
		reason=$(squash_onto_base "$branch" "$base_branch" "$msg_file") ||
			restore_fold_or_die "$reason" 1 "$branch" "$base_branch" "$tip" "$base_before" "$start"
	else
		git switch --quiet "$base_branch" ||
			restore_fold_or_die "could not switch to $base_branch" 1 "$branch" "$base_branch" "$tip" "$base_before" "$start"
	fi
	reason=$(push_folded_base "$base_branch" "$origin_sha" "$branch" "$base_before") ||
		restore_fold_or_die "$reason" 1 "$branch" "$base_branch" "$tip" "$base_before" "$start"
	clean_up_branch "$branch" "$base_branch" "$msg_file"

	printf 'release: %s folded into %s and pushed; %s was %s before the fold (git branch -f %s %s undoes it).\n' \
		"$branch" "$base_branch" "$base_branch" "$base_before" "$base_branch" "$base_before"
}

# ── finish ───────────────────────────────────────────────────────────────────

# Sets the caller's `mode`, `force`, and `gh_release` from argv. The three modes
# are the three steps of shipping, one per run, so the user sees what each one
# did before the next; the two modifiers belong to --publish alone, which is the
# only step with a CI gate to skip and a release to create.
parse_finish_args() {
	local arg
	mode=""
	force=false
	gh_release=false
	for arg in "$@"; do
		case "$arg" in
		--check | --push | --publish)
			[[ -z "$mode" ]] ||
				die "finish takes one of --check, --push, or --publish, and already has --$mode; $USAGE"
			mode="${arg#--}"
			;;
		--force) force=true ;;
		--gh-release) gh_release=true ;;
		-*) die "unknown option '$arg'; $USAGE" ;;
		*) die "unexpected argument '$arg'; finish takes none; $USAGE" ;;
		esac
	done
	[[ -n "$mode" ]] ||
		die "finish needs one of --check, --push, or --publish; $USAGE"
	[[ "$mode" == publish ]] || {
		! $force ||
			die "--force skips the CI gate, which only --publish has; drop it, or run --publish."
		! $gh_release ||
			die "--gh-release creates the GitHub release, which only --publish does; drop it, or run --publish."
	}
}

# Prints the version recorded for the checked-out branch, or refuses. finish
# only ever ships the branch the user stands on: acting on a release open
# elsewhere would move main from under a branch they are not looking at.
release_version() {
	local branch="$1" version
	version=$(git config --get "branch.$branch.$RELEASE_KEY") ||
		die "not on a release branch: '$branch' carries no $RELEASE_KEY key; switch to the branch 'release.sh status' names."
	printf '%s' "$version"
}

# Refuses while a plan branch still records the release as its base: publishing
# retires that base, stranding the branch pinned to it.
require_no_pending_plans() {
	local release_branch="$1" pending
	pending=$(unmerged_plan_branches "$release_branch")
	[[ -z "$pending" ]] ||
		die "'${pending%%$'\n'*}' still records $release_branch as its base; merge it with 'release.sh merge' first."
}

# Refuses unless the trunk can fast-forward onto the release branch, which is
# what makes publishing a branch move rather than a merge commit on main.
require_trunk_fast_forwards() {
	local release_branch="$1"
	git merge-base --is-ancestor "$TRUNK" "$release_branch" ||
		die "$TRUNK is not an ancestor of $release_branch, so $TRUNK cannot fast-forward onto it; rebase the release branch onto $TRUNK, then re-run."
}

# Refuses unless the tip is the release commit: the version's tag points at it
# and its subject is the one `write-release` makes. Both, because a tag alone
# would ship a branch whose release commit is buried under later work.
require_release_commit_at_tip() {
	local release_branch="$1" version="$2" tag="v$2" tags subject
	local want="chore: release $tag"
	tags=$(git tag --points-at HEAD)
	[[ $'\n'"$tags"$'\n' == *$'\n'"$tag"$'\n'* ]] ||
		die "the tip of $release_branch carries no $tag tag; tag the release commit, then re-run."
	subject=$(git log -1 --format=%s HEAD)
	[[ "$subject" == "$want" ]] ||
		die "the tip of $release_branch is '$subject', not '$want'; the release commit is what gets pushed."
}

# Refuses unless the version's tag names the exact commit being published, so
# the tag origin ends up with is the one main is moved to.
require_tag_at_tip() {
	local tag="$1" tip="$2" tagged
	tagged=$(git rev-parse --verify --quiet "refs/tags/$tag^{commit}") ||
		die "this repo has no $tag tag; tag the release commit, then re-run."
	[[ "$tagged" == "$tip" ]] ||
		die "$tag points at $(git rev-parse --short "$tagged"), not at the commit being published; move the tag, then re-run."
}

# Everything that must hold before the release commit is written: the branch is
# the user's to finish, nothing else is pinned to it, and it is exactly what
# origin and the trunk expect.
finish_check() {
	local release_branch="$1" version="$2"
	require_clean_worktree
	require_no_pending_plans "$release_branch"
	require_branch_in_sync "$release_branch" >/dev/null
	require_branch_in_sync "$TRUNK" >/dev/null
	require_trunk_fast_forwards "$release_branch"
	printf 'release: %s is ready to release.\nversion: %s\n' "$release_branch" "$version"
}

# Appends the release commit to origin's copy of the branch. A plain push: the
# commit is new work on top, and a branch that needs force here is a branch
# whose history someone else has moved.
finish_push() {
	local release_branch="$1" version="$2" tip
	require_release_commit_at_tip "$release_branch" "$version"
	tip=$(git rev-parse --verify "refs/heads/$release_branch")
	git push --quiet origin "$release_branch" ||
		die "pushing $release_branch to origin failed; nothing here changed, so re-run once origin takes it." 1
	printf 'release: %s pushed.\ncommit: %s\n' "$release_branch" "$tip"
}

# Moves the trunk onto the release tip and puts it, with the tag, on origin.
# --ff-only from the trunk keeps this a fast-forward: the release branch already
# contains the trunk, so no merge commit is ever written.
publish_to_trunk() {
	local release_branch="$1" tip="$2" tag="$3"
	switch_or_die "$TRUNK"
	git merge --quiet --ff-only "$tip" ||
		die "fast-forwarding $TRUNK onto $release_branch failed; $TRUNK is checked out and unchanged, $release_branch and its tag are kept." 1
	git push --quiet origin "$TRUNK" "$tag" ||
		die "pushing $TRUNK and $tag to origin failed; $TRUNK is fast-forwarded locally and $release_branch is kept, so re-run once origin takes them." 1
}

# Drops the finished branch here and on origin, and the key that made it the
# release, leaving the trunk the only place the work lives. Runs after the push,
# so nothing unpushed is dropped.
retire_release_branch() {
	local release_branch="$1" kept="$2" key="branch.$1.$RELEASE_KEY"
	git push --quiet origin --delete "$release_branch" ||
		die "deleting $release_branch from origin failed; $kept." 1
	git branch --quiet -D "$release_branch" ||
		die "deleting the local $release_branch failed; $kept." 1
	# `git branch -D` drops the whole branch.<name> section, key included; this
	# clears the key in a git that ever stops doing so.
	if git config --get "$key" >/dev/null; then
		git config --unset "$key" ||
			die "clearing $key failed; $kept." 1
	fi
}

# Prints the changelog section for version $1 out of $2 — the lines under its
# `## [X.Y.Z]` heading, up to the next `## ` heading — and nothing at all when
# the file or the section is missing. Neither absence refuses the run: the
# release it would describe is already tagged and pushed by the time this runs,
# and a body is editable in the web UI afterwards.
release_notes() {
	local version="$1" file="$2" section
	if [[ ! -f "$file" ]]; then
		warn "no $file here, so the GitHub release gets an empty body."
		return 0
	fi
	section=$(awk -v heading="## [$version]" '
		substr($0, 1, length(heading)) == heading { found = 1; next }
		found && /^## / { exit }
		found && !body && /^[[:space:]]*$/ { next }
		found { body = 1; print }
	' "$file")
	[[ -n "$section" ]] ||
		warn "$file has no '## [$version]' section, so the GitHub release gets an empty body."
	printf '%s' "$section"
}

# Path the release notes are written to for `gh release create --notes-file`;
# global so the exit trap clears it however the run ends.
RELEASE_NOTES_FILE=""
remove_release_notes() {
	[[ -z "$RELEASE_NOTES_FILE" ]] || rm -f "$RELEASE_NOTES_FILE"
}

# Creates the GitHub release for the tag already on origin. Last step of the
# publish on purpose: the tag it names must be pushed first, and a release that
# is already there is reported rather than recreated, so a re-run after a failed
# step is safe.
create_github_release() {
	local version="$1" root="$2" tag="v$1"
	command -v gh >/dev/null || {
		warn "gh is not installed, so no GitHub release was created for $tag; create it by hand."
		return 0
	}
	if gh release view "$tag" >/dev/null 2>&1; then
		printf 'release: the GitHub release %s already exists and was left alone.\n' "$tag"
		return 0
	fi
	RELEASE_NOTES_FILE=$(mktemp) ||
		die "could not open a temporary file for the release notes; $tag is pushed, so create the release by hand." 1
	release_notes "$version" "$root/$CHANGELOG_FILE" >"$RELEASE_NOTES_FILE"
	gh release create "$tag" --title "$tag" --notes-file "$RELEASE_NOTES_FILE" ||
		die "'gh release create $tag' failed; $tag is pushed, so create the release by hand." 1
	printf 'release: GitHub release %s created.\n' "$tag"
}

# The last step, and the only one that moves main. Everything is checked before
# anything is written; after the push, each cleanup failure names what is
# already on origin, since a re-run picks up from there.
finish_publish() {
	local release_branch="$1" version="$2" force="$3" gh_release="$4"
	local tag="v$2" tip root
	tip=$(git rev-parse --verify "refs/heads/$release_branch")
	root=$(git rev-parse --show-toplevel)
	require_clean_worktree
	require_no_pending_plans "$release_branch"
	$force || require_ci_success "$release_branch" "$tip"
	require_branch_in_sync "$TRUNK" >/dev/null
	require_trunk_fast_forwards "$release_branch"
	require_tag_at_tip "$tag" "$tip"
	require_branch_in_sync "$release_branch" >/dev/null

	publish_to_trunk "$release_branch" "$tip" "$tag"
	if $gh_release; then
		create_github_release "$version" "$root"
	fi
	retire_release_branch "$release_branch" "$TRUNK and $tag are on origin"
	printf 'release: %s released as %s; %s is at %s and the branch is gone.\n' \
		"$release_branch" "$tag" "$TRUNK" "$tip"
}

# Shipping is three runs, not one: --check says whether the release is ready,
# --push puts the release commit on origin for CI to judge, --publish moves the
# trunk onto it once CI is green.
cmd_finish() {
	local mode force gh_release branch version
	parse_finish_args "$@"
	branch=$(current_branch)
	version=$(release_version "$branch")

	case "$mode" in
	check) finish_check "$branch" "$version" ;;
	push) finish_push "$branch" "$version" ;;
	publish) finish_publish "$branch" "$version" "$force" "$gh_release" ;;
	esac
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

main() {
	local git_dir subcommand
	trap remove_release_notes EXIT
	exit_if_help_requested "$@"
	git_dir=$(policy_git_dir) || exit $?

	subcommand="${1:-}"
	[[ -n "$subcommand" ]] || die "no subcommand given; $USAGE"
	shift
	case "$subcommand" in
	start | status | merge | finish) ;;
	*) die "unknown subcommand '$subcommand'; $USAGE" ;;
	esac
	[[ "$subcommand" == status ]] || require_release_marker "$git_dir"

	case "$subcommand" in
	start) cmd_start "$@" ;;
	status) cmd_status "$@" ;;
	merge) cmd_merge "$git_dir" "$@" ;;
	finish) cmd_finish "$@" ;;
	esac
}

main "$@"
