#!/usr/bin/env bash
set -euo pipefail

# Fires on Read|Bash. While a tdd-cycle agent is in its RED phase, block its reads of
# implementation source files — mechanical enforcement of the Phase 1 access rules in
# agents/tdd-cycle.md.
#
# Per-instance markers: the agent touches/removes `$GIT_DIR/tdd-red-phase` by that
# name, and this hook mirrors those touch/rm commands onto `tdd-red-phase.<agent_id>`
# (hook stdin carries a unique agent_id per subagent instance). The guard checks only
# the per-instance marker, so concurrent tdd-cycle agents in one repo gate themselves —
# one agent's RED never blocks another's GREEN reads. The un-suffixed file the agent's
# own command creates is inert here; the orchestrator sweeps all marker files after
# each wave. Without an agent_id the un-suffixed marker is the guard.
#
# Only tdd-cycle agents are affected: hook stdin carries agent_type for subagent calls,
# so the orchestrator (and anything else in the repo) reads freely during RED.

# `bash hook.sh` run from inside hooks/ leaves no slash to strip a directory at.
HOOK_SOURCE=${BASH_SOURCE[0]}
[[ "$HOOK_SOURCE" == */* ]] || HOOK_SOURCE="./$HOOK_SOURCE"
HOOK_DIR=$(cd "${HOOK_SOURCE%/*}" && pwd)
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=tdd-red-guard
sh_fail_closed

readonly READ_CMDS="cat|head|tail|less|more|sed|awk|grep|rg|bat|nl|tac|cut|strings|python|python3|node"

# Set by main for the invocation callback, which ils_each_invocation calls with
# the record fields only.
marker=""
toplevel=""

# Allowed during RED: test files, stubs, interfaces, public API surface, anything
# under a test directory. Everything else with a source extension is impl source.
is_impl_source() {
	local path="$1"
	local base="${path##*/}"

	[[ "$path" =~ (^|/)(tests?|__tests__|spec)(/|$) ]] && return 1

	case "$base" in
	test_*.py | *_test.py | conftest.py | __init__.py | *.pyi) return 1 ;;
	*.test.ts | *.spec.ts | *.test.tsx | *.spec.tsx | *.test.mts | *.spec.mts | *.test.cts | *.spec.cts | *.d.ts) return 1 ;;
	*_test.lua | *_spec.lua) return 1 ;;
	*Tests.swift) return 1 ;;
	esac

	case "$base" in
	*.py | *.ts | *.tsx | *.mts | *.cts | *.lua | *.swift) return 0 ;;
	esac
	return 1
}

block() {
	die "BLOCKED (TDD RED phase): reading implementation source '$1' is forbidden during Phase 1.
Use type stubs, __init__.py exports, interface files, or docs to understand the API."
}

# True when invocation words $@ (marked `=<literal>` or `?`) name the RED marker:
# a literal word holding its name, or — since a non-literal word's text is
# unknown — a non-literal word in a command whose text holds the name, the shape
# of `touch "$(git rev-parse --git-dir)/tdd-red-phase"`. A literal-only
# invocation such as `rm -f out.tmp` never qualifies, so a marker touch and an
# unrelated rm in one command cannot cancel each other.
names_marker() {
	local word
	for word; do
		case "$word" in
		=*tdd-red-phase*) return 0 ;;
		'?') [[ "$ils_command" == *tdd-red-phase* ]] && return 0 ;;
		esac
	done
	return 1
}

# Path $1 as is_impl_source should judge it: relative to the work tree when it
# lies inside, so a directory above the repository named like a test directory
# cannot exempt the whole repository. Its directory is made physical first, so
# the prefix matches git's physical --show-toplevel.
repo_relative() {
	local path="$1" dir
	if dir=$(cd "${path%/*}" 2>/dev/null && pwd -P); then
		path="$dir/${path##*/}"
	fi
	if [[ -n "$toplevel" && "$path" == "$toplevel"/* ]]; then
		printf '%s' "${path#"$toplevel"/}"
	else
		printf '%s' "$path"
	fi
}

# ils_each_invocation callback: mirrors a touch/rm of the RED marker onto the
# per-instance marker, then blocks a read command naming an implementation file.
check_invocation() {
	local dir="$4" name word path base_dir
	shift 4
	(($#)) || return 0
	[[ "$1" == =* ]] || return 0
	name="${1:1}"
	# Strip the directory with an expansion, never basename: a word can start
	# with a dash, which basename parses as a flag and dies on.
	name="${name##*/}"
	shift

	case "$name" in
	touch | rm)
		if names_marker "$@"; then
			if [[ "$name" == touch ]]; then
				touch "$marker"
			else
				rm -f "$marker"
			fi
			return 0
		fi
		;;
	esac

	[[ -f "$marker" ]] || return 0
	[[ "$name" =~ ^(${READ_CMDS})$ ]] || return 0

	base_dir="${dir:-$PWD}"
	for word; do
		[[ "$word" == =* ]] || continue
		word="${word:1}"
		[[ -n "$word" ]] || continue
		if [[ "$word" == /* ]]; then
			path="$word"
		else
			path="$base_dir/$word"
		fi
		if [[ -f "$path" ]] && is_impl_source "$(repo_relative "$path")"; then
			block "$word"
		fi
	done
}

main() {
	local input agent_type git_dir agent_id tool_name file_path

	input=$(cat)

	agent_type=$(sh_input_field "$input" '.agent_type // empty')
	[[ "$agent_type" == "tdd-cycle" ]] || exit 0

	git_dir=$(git --no-optional-locks rev-parse --git-dir 2>/dev/null) || exit 0

	agent_id=$(sh_input_field "$input" '.agent_id // empty')
	marker="$git_dir/tdd-red-phase${agent_id:+.$agent_id}"

	tool_name=$(sh_input_field "$input" '.tool_name // empty')
	toplevel=$(git --no-optional-locks rev-parse --show-toplevel 2>/dev/null) || toplevel=""

	if [[ "$tool_name" == "Read" ]]; then
		[[ -f "$marker" ]] || exit 0
		file_path=$(sh_input_field "$input" '.tool_input.file_path // empty')
		[[ -n "$file_path" ]] && is_impl_source "$(repo_relative "$file_path")" && block "$file_path"
		exit 0
	fi

	[[ "$tool_name" == "Bash" ]] || exit 0

	ils_each_invocation check_invocation <<<"$input"
}

main "$@"
