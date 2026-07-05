#!/usr/bin/env bash
set -euo pipefail

# Fires on Read|Bash. While a tdd-cycle agent is in its RED phase (marker file
# `$GIT_DIR/tdd-red-phase` exists, created/removed by the agent per agents/tdd-cycle.md),
# block reads of implementation source files — mechanical enforcement of the Phase 1
# access rules that were previously honor-system.
#
# Only the tdd-cycle agent is blocked: hook stdin carries `agent_type` for subagent
# calls, so the orchestrator (and anything else in the repo) reads freely during RED.
#
# ponytail: marker is per-repo, not per-session — two tdd-cycle agents in the same repo
# would share the guard (one's RED gates the other's GREEN reads). Per-session markers
# if that ever bites.

command -v jq >/dev/null || {
	printf "Error: jq is required\n" >&2
	exit 1
}

input=$(cat)

agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty')
[[ "$agent_type" == "tdd-cycle" ]] || exit 0

git_dir=$(git --no-optional-locks rev-parse --git-dir 2>/dev/null) || exit 0
[[ -f "$git_dir/tdd-red-phase" ]] || exit 0

# Allowed during RED: test files, stubs, interfaces, public API surface, anything
# under a test directory. Everything else with a source extension is impl source.
is_impl_source() {
	local path="$1" base
	base=$(basename "$path")

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
	printf "BLOCKED (TDD RED phase): reading implementation source '%s' is forbidden during Phase 1.\n" "$1" >&2
	printf "Use type stubs, __init__.py exports, interface files, or docs to understand the API.\n" >&2
	exit 2
}

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')

if [[ "$tool_name" == "Read" ]]; then
	file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
	[[ -n "$file_path" ]] && is_impl_source "$file_path" && block "$file_path"
	exit 0
fi

# Bash: scan read-type commands for impl-source file arguments.
# ponytail: word-scan, not a shell parser — catches `cat src/foo.py`, not exotic
# quoting/globs. The docs remain the rule; this catches the casual violations.
full_command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[[ -z "$full_command" ]] && exit 0

read_cmds="cat|head|tail|less|more|sed|awk|grep|rg|bat|nl|tac|cut|strings|python|python3|node"

while IFS= read -r subcmd; do
	subcmd="${subcmd#"${subcmd%%[![:space:]]*}"}"
	[[ -z "$subcmd" ]] && continue
	first_word="${subcmd%% *}"
	[[ "$(basename "$first_word")" =~ ^(${read_cmds})$ ]] || continue
	for word in $subcmd; do
		word="${word%\"}" word="${word#\"}" word="${word%\'}" word="${word#\'}"
		if is_impl_source "$word" && [[ -f "$word" ]]; then
			block "$word"
		fi
	done
done <<<"$(printf '%s' "$full_command" | awk '{gsub(/&&/,"\n"); gsub(/\|\|/,"\n"); gsub(/\|/,"\n"); gsub(/;/,"\n"); print}')"

exit 0
