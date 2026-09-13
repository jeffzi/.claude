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
	local word
	local -a words=()

	# read -ra splits on whitespace without letting a word glob; -d '' keeps
	# the split spanning newlines, as a raw multi-line command line needs.
	read -d '' -ra words <<<"$cmd" || true
	for word in ${words[@]+"${words[@]}"}; do
		if $skip_next; then
			skip_next=false
			continue
		fi

		if ! $in_git; then
			[[ "$word" == "git" ]] && in_git=true
			continue
		fi

		case "$word" in
		# Only these global options take their value as a separate word; every
		# other option, attached-value forms included, is a single word.
		-C | -c | --git-dir | --work-tree | --namespace)
			skip_next=true
			continue
			;;
		-*)
			continue
			;;
		*)
			printf '%s' "$word"
			return 0
			;;
		esac
	done
	return 1
}
