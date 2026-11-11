#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │                   Bash Exit Guard                          │
# ╰────────────────────────────────────────────────────────────╯
# PostToolUse hook: blocks Claude from proceeding when a Bash
# command fails. Outputs JSON { decision: "block", reason: ... }
# which forces Claude to acknowledge the error before continuing.
#
# Skip list: a command that is a single invocation of a probe
# routinely using non-zero exit for control flow (grep no-match,
# diff file-differs, etc.) passes; chained with anything else, it
# blocks, since the failure may be the other command's.

# `bash hook.sh` run from inside hooks/ leaves no slash to strip a directory at.
HOOK_SOURCE=${BASH_SOURCE[0]}
[[ "$HOOK_SOURCE" == */* ]] || HOOK_SOURCE="./$HOOK_SOURCE"
HOOK_DIR=$(cd "${HOOK_SOURCE%/*}" && pwd)
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=bash-exit-guard
sh_fail_closed

# ils reports a landing's outcome through its exit code: 4 means
# CI is still pending, 5 means delivered but not green. Each
# names a next step the ils workflow already handles, so neither
# is a failure to block on. Every other ils exit still blocks.
readonly ILS_EXIT_PENDING=4
readonly ILS_EXIT_NOT_GREEN=5

# Succeeds when a command whose single invocation has words $3.. — marked
# `=<text>` for a literal word, as scripts/ils-invocations.sh yields them — and
# tool $2 exited $1 as a normal answer rather than a failure: a probe on the
# skip list, or an ils verdict. A git invocation's words are its arguments, so
# `git diff test` never reads as `test`. `[[` appears only through the
# first-word fallback: ils parse reads it as no invocation at all.
is_control_flow() {
	local exit_code="$1" tool="$2" name="${3:-}" arg="${4:-}"
	[[ "$tool" != git ]] || return 1
	case "$name" in
	=grep | =rg | =diff | =test | =which | =false | =true | "=[" | "=[[") return 0 ;;
	=command) [[ "$arg" == =-v ]] ;;
	=ils) [[ "$exit_code" == "$ILS_EXIT_PENDING" || "$exit_code" == "$ILS_EXIT_NOT_GREEN" ]] ;;
	*) return 1 ;;
	esac
}

# Reads the records on stdin and sets INVOCATION_COUNT to how many invocations
# they hold, and INVOCATION_TOOL and INVOCATION_WORDS to the last one's.
read_invocations() {
	local git_dir subcommand dir count word i
	INVOCATION_COUNT=0
	INVOCATION_TOOL=""
	INVOCATION_WORDS=()
	while IFS= read -r -d '' INVOCATION_TOOL && IFS= read -r -d '' git_dir &&
		IFS= read -r -d '' subcommand && IFS= read -r -d '' dir &&
		IFS= read -r -d '' count; do
		INVOCATION_COUNT=$((INVOCATION_COUNT + 1))
		INVOCATION_WORDS=()
		for ((i = 0; i < count; i++)); do
			IFS= read -r -d '' word && INVOCATION_WORDS+=("$word")
		done
	done
}

# Succeeds when command $2, run from $3, failed with exit $1 only as a normal
# answer: it is a single invocation that is_control_flow accepts. A command ils
# cannot parse yields no invocation and falls back to its first word. When ils
# or jq is missing, or ils parse fails any other way, nothing is known about the
# command, so it is never skipped.
skips_failure() {
	local exit_code="$1" cmd="$2" cwd="$3" records first second
	records=$(mktemp)
	sh_remove_on_exit "$records"
	ils_invocations "$cwd" "$cmd" >"$records" || return 1
	read_invocations <"$records"
	case "$INVOCATION_COUNT" in
	0)
		read -r first second _ <<<"$cmd" || true
		is_control_flow "$exit_code" "" "=${first:-}" "=${second:-}"
		;;
	1) is_control_flow "$exit_code" "$INVOCATION_TOOL" ${INVOCATION_WORDS[@]+"${INVOCATION_WORDS[@]}"} ;;
	*) return 1 ;;
	esac
}

main() {
	local input tool_name exit_code cmd cwd
	input=$(cat)
	tool_name=$(sh_input_field "$input" '.tool_name // empty')
	[[ "$tool_name" == "Bash" ]] || exit 0

	exit_code=$(sh_input_field "$input" '.tool_response.exit_code // 0')
	[[ "$exit_code" != "0" ]] || exit 0

	cmd=$(sh_input_field "$input" '.tool_input.command // empty')
	cwd=$(sh_input_field "$input" '.cwd // empty')
	skips_failure "$exit_code" "$cmd" "${cwd:-$PWD}" && exit 0

	jq -n \
		--arg reason "COMMAND FAILED (exit code $exit_code). Fix this error or surface it to the user before proceeding. Do NOT switch to a different file, config, or approach to avoid the error." \
		'{ "decision": "block", "reason": $reason }'
	exit 0
}

main "$@"
