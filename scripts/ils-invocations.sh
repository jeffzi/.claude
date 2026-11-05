# shellcheck shell=bash
#
# The one reader of shell commands for the PreToolUse Bash hooks: `ils parse`
# finds every git and gh invocation in a command line, wherever it hides
# (after `cd x &&`, behind `-C`, inside `$(…)` or `bash -c '…'`), so no hook
# parses git commands itself.
#
# Sourced, never executed: no `set -euo pipefail` here, since it would leak
# into whatever sourced it.
#
# Record format — every field ends in a NUL byte, so a field may hold any
# character a command word can, spaces and newlines included:
#
#   tool  git-dir  subcommand  count  word…
#
# - tool        `git` or `gh`
# - git-dir     the git dir a git invocation targets; empty for gh, and empty
#               when the invocation runs outside any repository or its git dir
#               cannot be known — the caller has no repository to read
# - subcommand  the git subcommand; empty for gh, for a git invocation with
#               none, and for one whose subcommand is not a literal word
# - count       how many word fields follow
# - word…       git: the literal arguments after the subcommand
#               gh:  the literal words of the invocation, `gh` included
#
# A word that is not a literal (`"$f"`, `$(…)`) is left out: its text is not
# known until the shell runs it.
#
# A caller reads the stream field by field:
#
#   while IFS= read -r -d '' tool && IFS= read -r -d '' git_dir \
#       && IFS= read -r -d '' subcommand && IFS= read -r -d '' count; do
#       words=()
#       for ((i = 0; i < count; i++)); do
#           IFS= read -r -d '' word && words+=("$word")
#       done
#       …
#   done <"$records_file"

# A second load in one shell is a no-op, which keeps the `readonly` below from
# tripping.
[[ -n "${ILS_INVOCATIONS_SOURCED:-}" ]] && return 0
ILS_INVOCATIONS_SOURCED=1

# Every field the record format above names, NUL-terminated, in order.
readonly ILS_INVOCATIONS_FILTER='
def literal_texts: [.[] | select(.literal) | .text];
def counted: (length | tostring), .[];
.payload.parse.invocations[]
| if .tool == "git" then
	.git
	| [
		"git",
		(if .git_dir_unknown then "" else .git_dir // "" end),
		(.subcommand | if . != null and .literal then .text else "" end),
		((.args // []) | literal_texts | counted)
	]
elif .tool == "gh" then
	["gh", "", "", ((.words // []) | literal_texts | counted)]
else
	empty
end
| .[]
| . + "\u0000"
'

# Prints a record for every git and gh invocation in command $2 run from
# directory $1. Prints nothing and succeeds when the command does not parse
# (`ils parse` exit 1). Fails with the reason on stderr when ils or jq is
# missing, `ils parse` exits with anything else, or its output cannot be read.
ils_invocations() {
	local cwd="$1" command="$2" json status=0 tool
	for tool in ils jq; do
		command -v "$tool" >/dev/null || {
			printf 'ils_invocations: %s is not on PATH\n' "$tool" >&2
			return 1
		}
	done

	json=$(ils parse --json --cwd "$cwd" -- "$command") || status=$?
	case "$status" in
	0) ;;
	1) return 0 ;;
	*)
		printf 'ils_invocations: ils parse exited %d\n' "$status" >&2
		return 1
		;;
	esac

	jq -j "$ILS_INVOCATIONS_FILTER" <<<"$json" || {
		printf 'ils_invocations: jq could not read the ils parse output\n' >&2
		return 1
	}
}
