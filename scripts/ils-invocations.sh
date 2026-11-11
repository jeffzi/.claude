# shellcheck shell=bash
#
# The one reader of shell commands for the PreToolUse Bash hooks: `ils parse`
# finds every invocation in a command line, wherever it hides (after `cd x &&`,
# behind `-C`, inside `$(…)` or `bash -c '…'`), so no hook parses git commands
# itself.
#
# Sourced, never executed: no `set -euo pipefail` here, since it would leak
# into whatever sourced it.
#
# Record format — every field ends in a NUL byte, so a field may hold any
# character a command word can, spaces and newlines included:
#
#   tool  git-dir  subcommand  dir  count  word…
#
# - tool        `git`, `gh` or `ils`; empty for any other command
# - git-dir     the git dir a git invocation targets; empty for any other
#               command, and empty when the invocation runs outside any
#               repository or its git dir cannot be known — the caller has no
#               repository to read
# - subcommand  the git subcommand; empty for any other command, for a git
#               invocation with none, and for one whose subcommand is not a
#               literal word
# - dir         the directory the shell runs the invocation in (after `cd x &&`,
#               not after git's own `-C`); empty when it cannot be known
# - count       how many word fields follow
# - word…       git: the arguments after the subcommand
#               any other command: the words of the invocation, its name
#               included
#               Every word is kept and marked: `=<text>` for a literal word, `?`
#               alone for one that is not (`"$f"`, `$(…)`), whose text is not
#               known until the shell runs it but whose place among the words is.
#
# A caller reads the stream field by field:
#
#   while IFS= read -r -d '' tool && IFS= read -r -d '' git_dir \
#       && IFS= read -r -d '' subcommand && IFS= read -r -d '' dir \
#       && IFS= read -r -d '' count; do
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
def counted: (length | tostring), .[];
def marked: [.[] | if .literal then "=" + .text else "?" end];
def git_dir: if .git_dir_unknown then "" else .git_dir // "" end;
def subcommand: .subcommand | if . != null and .literal then .text else "" end;
.payload.parse.invocations[]
| if .tool == "git" then
	[
		"git",
		(.git | git_dir),
		(.git | subcommand),
		.dir // "",
		((.git.args // []) | marked | counted)
	]
else
	[.tool // "", "", "", .dir // "", ((.words // []) | marked | counted)]
end
| .[]
| . + "\u0000"
'

# `git commit` short options by arity: those that take no value, those whose
# value may be the next word (`-m msg`, `-mmsg`), and those whose value must be
# attached (`-uno`, `-Skey`). Every short option of `git commit` is in exactly
# one, so a short-option cluster can be split the way git splits it.
# shellcheck disable=SC2034 # read by the sourcing hooks
readonly ILS_GIT_COMMIT_PLAIN_SHORTS=aeinopqsvz
# shellcheck disable=SC2034 # read by the sourcing hooks
readonly ILS_GIT_COMMIT_VALUE_SHORTS=CcmFt
# shellcheck disable=SC2034 # read by the sourcing hooks
readonly ILS_GIT_COMMIT_ATTACHED_SHORTS=uS

# Succeeds when git arguments $4.. turn on an option before `--` ends the
# options: one of the long spellings in $3 (space-separated), or short letter
# $1 alone or inside a short-option cluster. A cluster ends at the first letter
# in $2, an option that takes the rest of the word as its value (`-ma` is the
# message "a", not -m and -a).
ils_git_has_option() {
	local short="$1" value_shorts="$2" longs=" $3 " word
	shift 3
	for word; do
		case "$word" in
		--) return 1 ;;
		--*) [[ "$longs" == *" $word "* ]] && return 0 ;;
		-?*)
			word="${word#-}"
			word="${word%%["$value_shorts"]*}"
			[[ "$word" == *"$short"* ]] && return 0
			;;
		esac
	done
	return 1
}

ils_invocations_fail() { printf 'ils_invocations: %s\n' "$1" >&2; }

# Prints a record for every invocation in command $2 run from
# directory $1. Prints nothing and succeeds when the command does not parse
# (`ils parse` exit 1). Fails with the reason on stderr when ils or jq is
# missing, `ils parse` exits with anything else, or its output cannot be read.
ils_invocations() {
	local cwd="$1" command_line="$2" json status=0 tool
	for tool in ils jq; do
		command -v "$tool" >/dev/null || {
			ils_invocations_fail "$tool is not on PATH"
			return 1
		}
	done

	json=$(ils parse --json --cwd "$cwd" -- "$command_line") || status=$?
	case "$status" in
	0) ;;
	1) return 0 ;;
	*)
		ils_invocations_fail "ils parse exited $status"
		return 1
		;;
	esac

	jq -j "$ILS_INVOCATIONS_FILTER" <<<"$json" || {
		ils_invocations_fail "jq could not read the ils parse output"
		return 1
	}
}

# The loop every PreToolUse Bash hook shares. Reads the hook payload
# (.tool_input.command, .cwd) from stdin, leaves the command in ils_command, and
# calls "$1" once for each invocation, in the calling shell, so the callback may
# `exit` to block:
#
#   "$1" tool git-dir subcommand dir [word…]
#
# with the fields and marked words of the record format above. The callback
# keeps the hook's stdin: the records are read on fd 3, which the callback does
# not inherit, so a callback that reads stdin cannot swallow the records after
# its own. Returns 0 without calling anything when the payload holds no
# command. Dies (exit 2) when jq is missing or the invocations of the command
# cannot be read.
#
# Needs `die`, `sh_input_field` and `sh_remove_on_exit` from sh-common.sh, which
# the caller sources; the temporary record file is removed on exit through the
# shared EXIT trap, so it composes with sh_fail_closed.
ils_each_invocation() {
	local callback="$1" input cwd records tool git_dir subcommand dir count word i
	local -a words
	input=$(</dev/stdin)
	# `|| exit` carries sh_input_field's refusal out of the command substitution
	# for a caller that runs without `set -e`.
	# shellcheck disable=SC2034 # read by the sourcing hook
	ils_command=$(sh_input_field "$input" '.tool_input.command // empty') || exit
	cwd=$(sh_input_field "$input" '.cwd // empty') || exit
	[[ -n "$ils_command" ]] || return 0

	records=$(mktemp)
	sh_remove_on_exit "$records"
	ils_invocations "${cwd:-$PWD}" "$ils_command" >"$records" ||
		die "cannot read the invocations of the command"

	while IFS= read -r -u 3 -d '' tool && IFS= read -r -u 3 -d '' git_dir &&
		IFS= read -r -u 3 -d '' subcommand && IFS= read -r -u 3 -d '' dir &&
		IFS= read -r -u 3 -d '' count; do
		words=()
		for ((i = 0; i < count; i++)); do
			IFS= read -r -u 3 -d '' word && words+=("$word")
		done
		"$callback" "$tool" "$git_dir" "$subcommand" "$dir" ${words[@]+"${words[@]}"} 3<&-
	done 3<"$records"
}

# ils_each_invocation callback for ils_each_git_invocation: passes a git
# invocation whose git dir is known on to ils_git_callback with its literal
# arguments only, and skips every other invocation.
ils_call_git_callback() {
	local tool="$1" git_dir="$2" subcommand="$3" word
	local -a literals=()
	shift 4
	[[ "$tool" == git && -n "$git_dir" ]] || return 0
	for word; do
		[[ "$word" != =* ]] || literals+=("${word:1}")
	done
	"$ils_git_callback" "$git_dir" "$subcommand" ${literals[@]+"${literals[@]}"}
}

# The loop for a hook that reads git invocations only. Calls "$1" once for each
# git invocation whose git dir is known, in the calling shell, so the callback
# may `exit` to block:
#
#   "$1" git-dir subcommand [word…]
#
# with the literal arguments after the subcommand; an argument that is not a
# literal word is left out. Returns and dies as ils_each_invocation does.
ils_each_git_invocation() {
	ils_git_callback="$1"
	ils_each_invocation ils_call_git_callback
}
