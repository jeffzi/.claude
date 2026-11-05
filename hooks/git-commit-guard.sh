#!/usr/bin/env bash
set -euo pipefail

# git-commit-guard.sh — PreToolUse Bash hook: blocks git commit messages that
# contain internal tooling references (plan IDs, TDD process labels, internal paths).
# The title and body of `gh pr create` and `gh pr edit` get the same scan: a
# squash merge turns them into the commit message.
#
# Which invocations are commits or pull requests, and which words they carry,
# comes from scripts/ils-invocations.sh — wherever the invocation hides in the
# command — so a command that only mentions those words is never scanned. A
# command whose invocations cannot be read blocks: the guard cannot vouch for
# what it did not see.
#
# Input: PreToolUse JSON on stdin (.tool_input.command, .cwd)
# Exit: 0 to allow, 2 to block

HOOK_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=git-commit-guard

# Each check pairs a grep invocation (flags + pattern) with its block reason.
check_flags=(-qE -qE -qiE -qE -qE)
check_patterns=(
	'\([0-9]+\.?[0-9]*-[0-9]+\)'
	'\([0-9]{2,}-[a-z][a-z-]*\)'
	'(RED-GREEN|TDD RED|TDD GREEN|RED phase|GREEN phase|REFACTOR phase)'
	'\.planning/'
	'[0-9]{2,}-[0-9]+-SUMMARY\.md'
)
check_reasons=(
	"Commit scope contains an internal phase ID (e.g. 05-01). Use a module name instead."
	"Commit scope contains a phase slug (e.g. 05-layout-transitions). Use a module name instead."
	"Commit message contains a TDD process label. Describe what was built, not the cycle."
	"Commit message references an internal .planning/ path."
	"Commit message references an internal SUMMARY file. Describe the effect instead."
)

# Print the reason of the first check matching $1; print nothing when it is clean.
scan_text() {
	local text="$1" i
	for i in "${!check_patterns[@]}"; do
		if printf '%s' "$text" | grep "${check_flags[$i]}" "${check_patterns[$i]}"; then
			printf '%s' "${check_reasons[$i]}"
			return 0
		fi
	done
	return 0
}

# Prints, one per line, every message file path that words $3.. give to short
# flag $1 or long flag $2, spelled `<flag> <path>` or `<flag>=<path>`. Words are
# marked as the record format in scripts/ils-invocations.sh marks them: a path
# that is not a literal word is skipped, and so is the word after it, which is
# not the path.
message_file_args() {
	local short="$1" long="$2" word next flag
	shift 2
	while (($#)); do
		word="$1"
		shift
		for flag in "$short" "$long"; do
			if [[ "$word" == "=$flag" ]]; then
				next="${1-}"
				(($#)) && shift
				[[ "$next" == =* ]] && printf '%s\n' "${next:1}"
			elif [[ "$word" == "=$flag="* ]]; then
				printf '%s\n' "${word#"=$flag="}"
			fi
		done
	done
}

scanned=0
message_files=()

# ils_each_invocation callback: notes a commit or a pull request create/edit,
# and collects its message files resolved against the directory $4 it runs in.
# "-" is stdin, already covered by the command-text scan of the heredoc; a
# relative path whose directory is unknown cannot be resolved and is skipped.
collect_message_files() {
	local tool="$1" subcommand="$3" dir="$4" path
	shift 4
	local -a flags
	if [[ "$tool" == git && "$subcommand" == commit ]]; then
		flags=(-F --file)
	elif [[ "$tool" == gh && "${1-}" == =gh && "${2-}" == =pr &&
		("${3-}" == =create || "${3-}" == =edit) ]]; then
		flags=(-F --body-file)
	else
		return 0
	fi
	scanned=1

	while IFS= read -r path; do
		[[ -n "$path" && "$path" != - ]] || continue
		if [[ "$path" != /* ]]; then
			[[ -n "$dir" ]] || continue
			path="$dir/$path"
		fi
		message_files+=("$path")
	done < <(message_file_args "${flags[@]}" "$@")
}

ils_each_invocation collect_message_files
((scanned)) || exit 0

# Do not extract only -m "...": heredoc and -F commits would be missed.
reason=$(scan_text "$ILS_COMMAND")

# A message file keeps the message out of the command text, so scan each file
# too; one that is missing or unreadable leaves the command text to decide.
for message_file in ${message_files[@]+"${message_files[@]}"}; do
	[[ -z "$reason" ]] || break
	if [[ -f "$message_file" && -r "$message_file" ]]; then
		reason=$(scan_text "$(cat -- "$message_file")")
	fi
done

if [[ -n "$reason" ]]; then
	jq -n --arg r "BLOCKED: $reason" '{ "decision": "block", "reason": $r }'
	exit 2
fi
