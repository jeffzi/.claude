#!/usr/bin/env bash
set -euo pipefail

# Squash a green plan branch into the branch it was started from, from the
# message the plan run wrote.
#
# Usage: merge-plan.sh [plan/<slug>] [--force]
#
# The user runs this through /merge-plan, which raises the
# `$GIT_DIR/merge-plan-active` marker this script requires. Its `git commit` on
# the base branch would be invisible to the Bash guard's subcommand parser, so the guard
# gates invocations on the same marker — two layers over the same hole.
#
# Every precondition is checked before anything is changed: a refusal (exit 2)
# leaves the repo exactly as it was found. Once the squash commit exists, a
# later failure (exit 1, a rejected push) keeps the commit, the branch, and the
# message file, so the run can be retried after the cause is fixed.

# Marker freshness shared with the guard that gates invocations of this script,
# the planBase config key, the clean-tree precondition, and help handling.
# shellcheck source=SCRIPTDIR/branch-policy.sh
. "${BASH_SOURCE[0]%/*}/branch-policy.sh"
PROG=merge-plan

readonly USAGE="usage: merge-plan.sh [plan/<slug>] [--force]"

# Sets the caller's `branch` and `force` from argv; `branch` stays empty for
# "use the current one".
parse_args() {
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
resolve_branch() {
	local branch="$1"
	if [[ -z "$branch" ]]; then
		branch=$(git symbolic-ref --quiet --short HEAD) ||
			die "HEAD is detached; name the branch, as in 'merge-plan.sh plan/<slug>'."
	fi
	[[ "$branch" == "$PLAN_BRANCH_PREFIX"* ]] ||
		die "'$branch' is not a plan branch; only plan/* branches are squashed."
	git show-ref --quiet --verify "refs/heads/$branch" ||
		die "'$branch' is not a local branch."
	printf '%s' "$branch"
}

# Prints the branch the plan lands on: the base recorded by the run that created
# the plan branch, and nothing else. A missing or unusable record is a refusal
# rather than a fall back to the trunk, which would land a plan on a branch it
# was never cut from. The record must name a local branch, since the squash
# commit is made on it here.
resolve_base_branch() {
	local branch="$1" key recorded
	key="branch.$branch.$PLAN_BASE_CONFIG_KEY"
	recorded=$(git config --get "$key") || recorded=""
	[[ -n "$recorded" ]] ||
		die "$key is unset, so there is no recorded base to squash '$branch' onto; branches from 'plan-branch.sh create' carry it, or record one with 'git config $key <branch>'."
	git show-ref --quiet --verify "refs/heads/$recorded" ||
		die "'$branch' records '$recorded' as its base, but that is not a local branch; restore it, or re-record one with 'git config $key <branch>'."
	printf '%s' "$recorded"
}

# The marker proves the run came through /merge-plan; a stale or future-dated one
# proves nothing and reads as absent, exactly as the fix-ci marker does.
require_merge_marker() {
	local marker="$1/$MERGE_PLAN_MARKER" status=0
	marker_fresh "$marker" || status=$?
	die_if_stat_unusable "$status"
	((status == 0)) ||
		die "no fresh marker at $marker; this script runs only through /merge-plan, which the user invokes."
}

require_message_file() {
	local msg_file="$1"
	[[ -f "$msg_file" ]] ||
		die "no squash message at $msg_file; the plan run writes it when CI goes green."
	[[ -s "$msg_file" ]] ||
		die "the squash message at $msg_file is empty."
}

# Refuses unless the local base branch is exactly its origin counterpart, so the
# squash lands on a base nobody else has moved.
require_base_in_sync() {
	local base_branch="$1" local_base remote_base
	git fetch --quiet origin "$base_branch" ||
		die "'git fetch origin $base_branch' failed; fix the remote, then re-run."
	local_base=$(git rev-parse --verify --quiet "refs/heads/$base_branch") ||
		die "this repo has no local '$base_branch' branch."
	remote_base=$(git rev-parse --verify FETCH_HEAD) ||
		die "origin has no '$base_branch' branch."
	[[ "$local_base" == "$remote_base" ]] ||
		die "local $base_branch ($(git rev-parse --short "$local_base")) differs from origin/$base_branch ($(git rev-parse --short "$remote_base")); sync it first."
}

# Refuses unless the base is an ancestor of the branch tip, which is what makes
# the squash commit's tree the branch tip's tree rather than a merge of the two.
require_branch_contains_base() {
	local branch="$1" base_branch="$2"
	git merge-base --is-ancestor "$base_branch" "$branch" ||
		die "'$branch' does not contain $base_branch; rebase the branch onto $base_branch, then re-run."
}

# Refuses unless the newest run gh reports for the branch tip concluded success.
# `--force` skips this gate only; the tree, message, and base checks always run.
require_ci_success() {
	local branch="$1" tip="$2" summary
	command -v gh >/dev/null ||
		die "gh is not installed; re-run with --force to merge without the CI check."
	summary=$(gh run list --commit "$tip" --limit 1 --json status,conclusion \
		--jq '.[0] | if . == null then "none" else "\(.status) \(.conclusion)" end') ||
		die "'gh run list' failed for $tip; re-run with --force to merge without the CI check."
	[[ "$summary" != "none" ]] ||
		die "no CI run found for $branch tip $tip; push the branch, or re-run with --force."
	[[ "$summary" == *" success" ]] ||
		die "the latest CI run for $branch tip $tip is '$summary'; merge only a green branch."
}

# Leaves the squash commit on the base; every later step is cleanup that keeps it.
squash_onto_base() {
	local branch="$1" base_branch="$2" msg_file="$3"
	git switch --quiet "$base_branch" ||
		die "could not switch to $base_branch." 1
	git merge --squash "$branch" >/dev/null ||
		die "squash-merging $branch into $base_branch failed." 1
	git commit --quiet --file "$msg_file" ||
		die "committing the squash of $branch onto $base_branch failed." 1
}

# Drops the branch here and on origin (when origin has it) and the message file.
# Runs only after origin has the squash commit, so nothing unpushed is lost.
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

main() {
	local git_dir branch force base_branch msg_file tip
	exit_if_help_requested "$@"
	git_dir=$(policy_git_dir) || exit $?
	require_merge_marker "$git_dir"

	parse_args "$@"
	branch=$(resolve_branch "$branch")
	base_branch=$(resolve_base_branch "$branch")
	msg_file="$git_dir/plan-squash/${branch#"$PLAN_BRANCH_PREFIX"}.msg"
	tip=$(git rev-parse --verify "refs/heads/$branch")

	require_clean_worktree
	require_message_file "$msg_file"
	require_base_in_sync "$base_branch"
	require_branch_contains_base "$branch" "$base_branch"
	if ! $force; then
		require_ci_success "$branch" "$tip"
	fi

	squash_onto_base "$branch" "$base_branch" "$msg_file"
	git push --quiet origin "$base_branch" ||
		die "pushing $base_branch to origin failed; the squash commit, $branch, and $msg_file are kept." 1
	clean_up_branch "$branch" "$base_branch" "$msg_file"

	printf "merge-plan: %s squashed onto %s and pushed.\n" "$branch" "$base_branch"
}

main "$@"
