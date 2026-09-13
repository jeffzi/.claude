# shellcheck shell=bash
#
# Shared by hooks/git-guard.sh and hooks/git-lock-guard.sh, which both judge a
# raw command line against the repo and the arguments the command itself names
# before deciding whether to block or wait on it.
#
# Sourced, never executed: no `set -euo pipefail` here, since it would leak
# into whatever sourced it. Both callers set it themselves.

# Filled by git_parse_command for the command line it was last given:
#   GIT_SUBCMD       the subcommand, empty when the line invokes none
#   GIT_SUBCMD_ARGS  every word after the subcommand
#   GIT_REPO_ARGS    the -C / --git-dir options, values included, in order
GIT_SUBCMD=""
GIT_SUBCMD_ARGS=()
GIT_REPO_ARGS=()

# The one walk over a command line's global options. Words are split on
# whitespace and never globbed, so `git -C repo* commit` names a repo literally
# called `repo*` — every check that reads these globals agrees on that.
# Fails when the line invokes no git subcommand.
git_parse_command() {
	local cmd="$1" word pending="" in_git=false
	local IFS=$' \t\n'
	local -a words=()
	GIT_SUBCMD=""
	GIT_SUBCMD_ARGS=()
	GIT_REPO_ARGS=()

	# read -ra splits without letting a word glob; -d '' keeps the split
	# spanning newlines, as a raw multi-line command line needs.
	read -d '' -ra words <<<"$cmd" || true
	for word in ${words[@]+"${words[@]}"}; do
		if [[ -n "$GIT_SUBCMD" ]]; then
			GIT_SUBCMD_ARGS+=("$word")
			continue
		fi
		if [[ -n "$pending" ]]; then
			[[ "$pending" == repo ]] && GIT_REPO_ARGS+=("$word")
			pending=""
			continue
		fi
		if ! $in_git; then
			[[ "$word" == "git" ]] && in_git=true
			continue
		fi

		case "$word" in
		# Only these global options take their value as a separate word; every
		# other option, attached-value forms included, is a single word.
		-C | --git-dir)
			GIT_REPO_ARGS+=("$word")
			pending=repo
			;;
		-c | --work-tree | --namespace)
			pending=skip
			;;
		-C* | --git-dir=*)
			GIT_REPO_ARGS+=("$word")
			;;
		-*) ;;
		*)
			GIT_SUBCMD="$word"
			;;
		esac
	done
	[[ -n "$GIT_SUBCMD" ]]
}

# Prints the git subcommand $1 invokes; fails when it invokes none.
# Usage: subcmd=$(get_git_subcmd "$command")
get_git_subcmd() {
	git_parse_command "$1" || return 1
	printf '%s' "$GIT_SUBCMD"
}

# True when command $1 names a repo through -C or --git-dir.
git_names_repo() {
	git_parse_command "$1" || true
	((${#GIT_REPO_ARGS[@]} > 0))
}

# Prints path $2 as git resolves it for command $1: a relative path lands under
# the directory the command's -C options compose (each -C relative to the one
# before, an absolute one restarting), and an absolute path or a command with
# no -C leaves it untouched. --git-dir moves no working directory, so it is
# ignored here.
# Usage: path=$(git_command_path "$command" "$path")
git_command_path() {
	local cmd="$1" path="$2" base="" arg value pending=""
	git_parse_command "$cmd" || true
	for arg in ${GIT_REPO_ARGS[@]+"${GIT_REPO_ARGS[@]}"}; do
		if [[ -n "$pending" ]]; then
			value="$arg"
			[[ "$pending" == -C ]] || {
				pending=""
				continue
			}
			pending=""
		else
			case "$arg" in
			-C | --git-dir)
				pending="$arg"
				continue
				;;
			-C*) value="${arg#-C}" ;;
			*) continue ;;
			esac
		fi
		if [[ "$value" == /* ]]; then
			base="$value"
		else
			base="${base:+$base/}$value"
		fi
	done
	if [[ -n "$base" && "$path" != /* ]]; then
		path="$base/$path"
	fi
	printf '%s' "$path"
}

# Runs git with the remaining arguments against the repo command $1 names, or
# against the cwd's repo when it names none.
# Usage: git_on_target "$command" rev-parse --show-toplevel
git_on_target() {
	local cmd="$1"
	shift
	git_parse_command "$cmd" || true
	git --no-optional-locks ${GIT_REPO_ARGS[@]+"${GIT_REPO_ARGS[@]}"} "$@"
}

# Prints the absolute git dir command $1 targets: the repo its -C / --git-dir
# name, or the cwd's when it names none. Fails when that does not resolve to a
# git dir — callers then read no marker, lock, or dirty state at all, never the
# cwd's in its place.
git_target_dir() {
	git_on_target "$1" rev-parse --absolute-git-dir 2>/dev/null
}
