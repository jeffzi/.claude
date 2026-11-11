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

# `bash hook.sh` run from inside hooks/ leaves no slash to strip a directory at.
HOOK_SOURCE=${BASH_SOURCE[0]}
[[ "$HOOK_SOURCE" == */* ]] || HOOK_SOURCE="./$HOOK_SOURCE"
HOOK_DIR=$(cd "${HOOK_SOURCE%/*}" && pwd)
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=git-commit-guard
sh_fail_closed

# Each check pairs a grep invocation (flags + pattern) with its block reason.
readonly CHECK_FLAGS=(-qE -qE -qiE -qE -qE)
readonly CHECK_PATTERNS=(
	'\([0-9]+\.?[0-9]*-[0-9]+\)'
	'\([0-9]{2,}-[a-z][a-z-]*\)'
	'(RED-GREEN|TDD RED|TDD GREEN|RED phase|GREEN phase|REFACTOR phase)'
	'\.planning/'
	'[0-9]{2,}-[0-9]+-SUMMARY\.md'
)
readonly CHECK_REASONS=(
	"Commit scope contains an internal phase ID (e.g. 05-01). Use a module name instead."
	"Commit scope contains a phase slug (e.g. 05-layout-transitions). Use a module name instead."
	"Commit message contains a TDD process label. Describe what was built, not the cycle."
	"Commit message references an internal .planning/ path."
	"Commit message references an internal SUMMARY file. Describe the effect instead."
)

# Print the reason of the first check matching $1; print nothing when it is clean.
scan_text() {
	local text="$1" i
	for i in "${!CHECK_PATTERNS[@]}"; do
		if grep "${CHECK_FLAGS[$i]}" -- "${CHECK_PATTERNS[$i]}" <<<"$text"; then
			printf '%s' "${CHECK_REASONS[$i]}"
			return 0
		fi
	done
	return 0
}

# Prints, one per line, every message file path that words $5.. give to short
# flag $1 or long flag $2. The long flag is spelled `<flag> <path>` or
# `<flag>=<path>`. The short flag is spelled `<flag> <path>`, `<flag><path>`,
# or as the last letter of a cluster of flags that take no value, whose letters
# are $3 (`-aF <path>`, `-aF<path>`).
#
# $4 names the parser that reads `-F=<path>`, which tools disagree on:
#
# - `git` reads it as the path `=<path>`.
# - `pflag` (spf13/pflag, gh's parser) drops the `=` and reads `<path>`.
#
# Words are marked as the record format in scripts/ils-invocations.sh marks
# them: a path that is not a literal word is skipped, and so is the word after
# it, which is not the path.
message_file_args() {
	local short="${1#-}" long="$2" plain_flags="$3" parser="$4" word next value
	local cluster="^=-[${plain_flags}]*${short}"
	shift 4
	while (($#)); do
		word="$1"
		shift
		if [[ "$word" == "=$long="* ]]; then
			printf '%s\n' "${word#"=$long="}"
		elif [[ "$word" == "=$long" || "$word" =~ ${cluster}$ ]]; then
			next="${1-}"
			(($#)) && shift
			[[ "$next" == =* ]] && printf '%s\n' "${next:1}"
		elif [[ "$word" =~ ${cluster}(.+)$ ]]; then
			value="${BASH_REMATCH[1]}"
			# pflag keeps a lone `=` as the value: only `=` with text after it is dropped.
			[[ "$parser" == pflag && "$value" == =?* ]] && value="${value:1}"
			printf '%s\n' "$value"
		fi
	done
}

has_message_invocation=0
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
		flags=(-F --file "$ILS_GIT_COMMIT_PLAIN_SHORTS" git)
	elif [[ "$tool" == gh && "${1-}" == =gh && "${2-}" == =pr &&
		("${3-}" == =create || "${3-}" == =edit) ]]; then
		flags=(-F --body-file defw pflag)
	else
		return 0
	fi
	has_message_invocation=1

	while IFS= read -r path; do
		[[ -n "$path" && "$path" != - ]] || continue
		if [[ "$path" != /* ]]; then
			[[ -n "$dir" ]] || continue
			path="$dir/$path"
		fi
		message_files+=("$path")
	done < <(message_file_args "${flags[@]}" "$@")
}

main() {
	local reason message_file

	ils_each_invocation collect_message_files
	((has_message_invocation)) || exit 0

	# Do not extract only -m "...": heredoc and -F commits would be missed.
	reason=$(scan_text "$ils_command")

	# A message file keeps the message out of the command text, so scan each file
	# too; one that is missing or unreadable leaves the command text to decide.
	for message_file in ${message_files[@]+"${message_files[@]}"}; do
		[[ -z "$reason" ]] || break
		if [[ -f "$message_file" && -r "$message_file" ]]; then
			reason=$(scan_text "$(<"$message_file")")
		fi
	done

	[[ -z "$reason" ]] || die "BLOCKED: $reason"
}

main "$@"
