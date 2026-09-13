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
#     (a CI-fix loop's throwaway branches) and `plan/*` (a plan run's branch).
#   - Every ref it touches is named in the argv. A push that names no refspec
#     lets git fall back to `remote.<name>.push` and `push.default` — repo
#     config the wrapper never vetted, which can carry a '+' force prefix or a
#     deleting ':main' — so it is refused rather than guessed at.
#
# Anything refused exits 2 with a reason on stderr and pushes nothing.
#
# The marker and namespace rules are shared with hooks/git-guard.sh, which
# guards the same loop from the other side.

# Sibling file. The wrapper never changes directory, so $BASH_SOURCE resolves
# the same way the invocation did. Trimmed with an expansion rather than
# `dirname` so that a PATH without git in it still reaches the check below and
# gets told what is missing, instead of dying on a missing `dirname`.
# shellcheck source=SCRIPTDIR/branch-policy.sh
. "${BASH_SOURCE[0]%/*}/branch-policy.sh"
PROG=fix-ci-push

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
	done < <(push_deleted_refs "$delete_mode" "${refs[@]}")
}

main() {
	require_active_marker
	require_allowed_args "$@"
	exec git push "$@"
}

main "$@"
