#!/usr/bin/env bash
set -euo pipefail

# Create the branch a plan run works on, and read back where it came from.
#
# Usage: plan-branch.sh create <slug> | base [plan/<slug>]
#
# `create` switches to plan/<slug> and records the branch it started from under
# `branch.plan/<slug>.planBase`; `base` prints that record. merge-plan.sh
# squashes onto the recorded branch and refuses without it, so a plan branch
# created by hand cannot be merged until the record is written.
#
# Every precondition is checked before anything is changed: a refusal (exit 2)
# leaves the repo exactly as it was found.

# The plan/* prefix, the planBase config key, the repo probe, the clean-tree
# precondition, and help handling.
# shellcheck source=SCRIPTDIR/branch-policy.sh
. "${BASH_SOURCE[0]%/*}/branch-policy.sh"
PROG=plan-branch

readonly USAGE="usage: plan-branch.sh create <slug> | base [plan/<slug>]"

# Dies unless git can answer for the repo the caller runs in; the git dir itself
# is of no use here, only the refusal it fails with.
require_git_repo() {
	policy_git_dir >/dev/null
}

# Switches to plan/<slug> and records the branch left behind as its base.
# Starting from a plan branch would record one plan's branch as another's base,
# so the squash chain ends up landing on a branch that is already gone.
create_plan_branch() {
	local slug="${1:-}" plan_branch branch
	[[ -n "$slug" ]] || die "no slug given; $USAGE"
	(($# <= 1)) || die "only one slug may be given, got '$slug' and '$2'."
	plan_branch="$PLAN_BRANCH_PREFIX$slug"

	require_clean_worktree
	branch=$(git symbolic-ref --quiet --short HEAD) ||
		die "HEAD is detached; switch to the branch this plan should land on first."
	[[ "$branch" != "$PLAN_BRANCH_PREFIX"* ]] ||
		die "'$branch' is itself a plan branch; start a plan from the branch it lands on."
	! git show-ref --quiet --verify "refs/heads/$plan_branch" ||
		die "branch $plan_branch already exists; pick another slug, or switch to it."

	git switch --quiet --create "$plan_branch" || die "creating $plan_branch failed." 1
	git config "branch.$plan_branch.$PLAN_BASE_CONFIG_KEY" "$branch" ||
		die "recording '$branch' as the base of $plan_branch failed." 1
	printf '%s (base %s)\n' "$plan_branch" "$branch"
}

# Prints the base recorded for the plan branch $1, or for HEAD's branch when
# argv named none.
print_plan_base() {
	local branch="${1:-}" key recorded
	(($# <= 1)) || die "only one branch may be named, got '$branch' and '$2'."
	if [[ -z "$branch" ]]; then
		branch=$(git symbolic-ref --quiet --short HEAD) ||
			die "HEAD is detached; name the branch, as in 'plan-branch.sh base plan/<slug>'."
	fi
	[[ "$branch" == "$PLAN_BRANCH_PREFIX"* ]] ||
		die "'$branch' is not a plan branch; only plan/* branches record a base."

	key="branch.$branch.$PLAN_BASE_CONFIG_KEY"
	recorded=$(git config --get "$key") || recorded=""
	[[ -n "$recorded" ]] ||
		die "$key is unset; '$branch' was not created by 'plan-branch.sh create'."
	printf '%s\n' "$recorded"
}

main() {
	exit_if_help_requested "$@"

	local subcommand=""
	if (($#)); then
		subcommand="$1"
		shift
	fi
	case "$subcommand" in
	create)
		require_git_repo
		create_plan_branch "$@"
		;;
	base)
		require_git_repo
		print_plan_base "$@"
		;;
	"") die "no subcommand given; $USAGE" ;;
	*) die "unknown subcommand '$subcommand'; $USAGE" ;;
	esac
}

main "$@"
