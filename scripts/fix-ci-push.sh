#!/usr/bin/env bash
set -euo pipefail

# Sanctioned push door for the fix-ci loop.
#
# Plain `git push` is denied outright by permission rules. This wrapper is the
# single exception, and it is strictly narrower than the command it fronts:
#
#   - It only runs while a fix-ci loop is live in the current repo, proven by a
#     fresh `$GIT_DIR/fix-ci-active` marker.
#   - Flags are whitelisted, not blocklisted. Only `-u`, `--set-upstream`, and
#     `--delete` get through, so every force spelling — `-f`, `--force`,
#     `--force-with-lease`, the `-fu`/`-uf` clusters, `--mirror` — is refused by
#     construction rather than by enumeration.
#   - Deletions stay inside the assistant's own branch namespaces, `fix-ci/*`
#     (a CI-fix loop's throwaway branches) and `plan/*` (branches older plan
#     runs left behind, kept so they can still be cleaned up).
#   - Every ref it touches is named in the argv. A push that names no refspec
#     lets git fall back to `remote.<name>.push` and `push.default` — repo
#     config the wrapper never vetted, which can carry a '+' force prefix or a
#     deleting ':main' — so it is refused rather than guessed at.
#   - A deletion that lands on the remote also deletes the local branch of the
#     same name, force-deleted because a squash-merged branch shares no
#     ancestry with HEAD. Only the refs the namespace check vetted are touched,
#     and only once the push has succeeded: a failed remote delete keeps them.
#
# Anything refused exits 2 with a reason on stderr and pushes nothing. A local
# branch that is checked out cannot be deleted; the remote deletion stands, the
# branch is kept, and the wrapper exits 2 naming it.

# `die` and portable stat access, from a sibling file. The wrapper never
# changes directory, so $BASH_SOURCE resolves the same way the invocation did.
# Trimmed with an expansion rather than `dirname` so that a PATH without git in
# it still reaches the check below and gets told what is missing, instead of
# dying on a missing `dirname`.
# shellcheck source=SCRIPTDIR/sh-common.sh
. "${BASH_SOURCE[0]%/*}/sh-common.sh"
PROG=fix-ci-push

# The marker file in the git dir. The fix-ci skill raises and drops it by this
# same name.
readonly FIX_CI_MARKER=fix-ci-active

# A live loop refreshes its marker's mtime each iteration, so only a marker
# abandoned by an interrupted session ages out.
readonly MARKER_TTL_SECONDS=1800

# A namespace of the assistant's own branches, alongside fix-ci/*.
readonly PLAN_BRANCH_PREFIX=plan/

# Dies naming stat when marker_fresh's status $1 says no stat dialect answered;
# returns otherwise. Exit 1: a broken tool, not a refusal of the run.
die_if_stat_unusable() {
	(($1 != SH_STAT_UNUSABLE)) ||
		die "stat answers neither BSD nor GNU format flags; marker age cannot be read." 1
}

# Prints the absolute git dir of the repo the caller runs in, or dies. git's own
# stderr is left visible on purpose: a safe.directory refusal and a corrupt repo
# both surface as this failure and need telling apart.
policy_git_dir() {
	command -v git >/dev/null || die "git is not installed."
	git rev-parse --absolute-git-dir || die "not inside a usable git repository."
}

# True when the marker at $1 proves a run is live right now. Only a regular file
# counts. The window is bounded on both sides: a marker aged past the TTL, dated
# ahead of now by a skewed clock or by hand, or whose mtime cannot be read proves
# nothing either way, and every one of those reads as absent (exit 1). A stat
# that answers no dialect at all exits SH_STAT_UNUSABLE instead: the marker may
# be perfectly live, so a caller must neither sweep it nor report it stale.
marker_fresh() {
	local marker="$1" mtime now status=0
	[[ -f "$marker" ]] || return 1
	mtime=$(sh_file_attr mtime "$marker") || status=$?
	((status == SH_STAT_UNUSABLE)) && return "$status"
	((status == 0)) || return 1
	now=$(date +%s)
	((now >= mtime && now - mtime <= MARKER_TTL_SECONDS))
}

# Refs a push actually deletes, one per line. Under --delete every refspec is a
# deletion; without it, only a leading-colon refspec such as ':main' deletes on
# its own. Recognising --delete is the caller's job — pass its verdict as $1.
push_deleted_refs() {
	local delete_mode="$1"
	shift
	local ref
	for ref in "$@"; do
		if [[ "$delete_mode" == true ]]; then
			printf '%s\n' "$ref"
		elif [[ "$ref" == :* ]]; then
			printf '%s\n' "${ref#:}"
		fi
	done
}

# True when a ref belongs to a namespace whose branches are the assistant's own
# and disposable — the only refs it may delete, locally or on a remote.
# `fix-ci/*` holds a CI-fix loop's throwaway branches; `plan/*` is kept for
# branches that older plan runs left behind, so they can still be cleaned up.
ref_in_own_namespace() {
	local ref="${1#refs/heads/}"
	[[ "$ref" == fix-ci/* || "$ref" == "$PLAN_BRANCH_PREFIX"* ]]
}

# The refs this push deletes, filled by require_allowed_args once each one has
# passed the namespace check. The local cleanup reads nothing else, so it can
# never reach a ref the check did not see.
DELETED_REFS=()

# Refuse unless the current repo has a marker touched within the TTL
require_active_marker() {
	local git_dir marker status=0
	git_dir=$(policy_git_dir) || exit $?
	marker="$git_dir/$FIX_CI_MARKER"
	[[ -f "$marker" ]] ||
		die "no fix-ci loop is active in this repo ($marker is absent)."
	marker_fresh "$marker" || status=$?
	die_if_stat_unusable "$status"
	((status == 0)) ||
		die "the fix-ci marker is not from the last ${MARKER_TTL_SECONDS}s; the loop is over."
}

# Refuse any argument outside the whitelist, and any deletion that reaches
# beyond the assistant's own namespaces, `fix-ci/*` and `plan/*`. `--delete`
# deletes every refspec it is given; without it, a leading-colon refspec such as
# ':main' deletes on its own.
require_allowed_args() {
	local -a refs=()
	local arg ref delete_mode=false seen_remote=false

	for arg in "$@"; do
		case "$arg" in
		-u | --set-upstream) continue ;;
		--delete)
			delete_mode=true
			continue
			;;
		-*) die "flag '$arg' is not allowed; only -u, --set-upstream and --delete are." ;;
		+*) die "refspec '$arg' forces the update; the fix-ci loop never rewrites history." ;;
		esac
		# The first bare word is the remote; the rest are refspecs.
		if ! $seen_remote; then
			seen_remote=true
			continue
		fi
		refs+=("$arg")
	done

	# Naming no ref hands the choice to `remote.<name>.push` / `push.default`,
	# which the wrapper never vetted; with --delete it would also leave nothing
	# to prove the deletion stays in namespace.
	[[ ${#refs[@]} -gt 0 ]] ||
		die "no refspec named; push the ref explicitly, as in 'origin fix-ci/lint'."

	while IFS= read -r ref; do
		ref_in_own_namespace "$ref" ||
			die "'$ref' is outside fix-ci/* and plan/*; only the assistant's own branches may be deleted."
		DELETED_REFS+=("$ref")
	done < <(push_deleted_refs "$delete_mode" "${refs[@]}")
}

# Delete the local branch behind every ref in DELETED_REFS, skipping any that
# does not exist here. The branch checked out in this worktree is kept — git
# refuses to delete it — and named, so the caller knows what to switch away
# from.
delete_local_branches() {
	local ref name current kept=""
	current=$(git symbolic-ref --quiet --short HEAD) || current=""
	for ref in ${DELETED_REFS[@]+"${DELETED_REFS[@]}"}; do
		name="${ref#refs/heads/}"
		git show-ref --quiet --verify "refs/heads/$name" || continue
		if [[ "$name" == "$current" ]]; then
			kept="$name"
			continue
		fi
		git branch --quiet -D "$name"
	done
	[[ -z "$kept" ]] ||
		die "'$kept' was deleted from the remote but is checked out here, so the local branch is kept; switch away from '$kept', then delete it."
}

main() {
	require_active_marker
	require_allowed_args "$@"
	git push "$@"
	delete_local_branches
}

main "$@"
