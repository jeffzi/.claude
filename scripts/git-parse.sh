# shellcheck shell=bash
#
# Shared by hooks/git-guard.sh and hooks/git-lock-guard.sh, which both need to
# identify the git subcommand a raw command line invokes before deciding
# whether to block or wait on it.
#
# Sourced, never executed: no `set -euo pipefail` here, since it would leak
# into whatever sourced it. Both callers set it themselves.

# Extract git subcommand, handling global options like -C path
# Usage: subcmd=$(get_git_subcmd "$command")
get_git_subcmd() {
	local cmd="$1"
	local in_git=false
	local skip_next=false

	for word in $cmd; do
		if $skip_next; then
			skip_next=false
			continue
		fi

		# Wait for 'git'
		if ! $in_git; then
			[[ "$word" == "git" ]] && in_git=true
			continue
		fi

		case "$word" in
		-C | -c | --git-dir | --work-tree | --namespace)
			skip_next=true
			continue
			;;
		-C* | -c*)
			# -C and -c can have value attached (-Cpath)
			continue
			;;
		--*=* | -*)
			# Long option with value or other short option
			continue
			;;
		*)
			# First non-option word is the subcommand
			printf '%s' "$word"
			return 0
			;;
		esac
	done
	return 1
}
