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
#   tool  git-dir  subcommand  dir  count  word…
#
# - tool        `git` or `gh`
# - git-dir     the git dir a git invocation targets; empty for gh, and empty
#               when the invocation runs outside any repository or its git dir
#               cannot be known — the caller has no repository to read
# - subcommand  the git subcommand; empty for gh, for a git invocation with
#               none, and for one whose subcommand is not a literal word
# - dir         the directory the shell runs the invocation in (after `cd x &&`,
#               not after git's own `-C`); empty when it cannot be known
# - count       how many word fields follow
# - word…       git: the arguments after the subcommand
#               gh:  the words of the invocation, `gh` included
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
elif .tool == "gh" then
	["gh", "", "", .dir // "", ((.words // []) | marked | counted)]
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

# The loop every PreToolUse Bash hook shares. Reads the hook payload
# (.tool_input.command, .cwd) from stdin, leaves the command in ILS_COMMAND, and
# calls "$1" once for each git and gh invocation, in the calling shell, so the
# callback may `exit` to block:
#
#   "$1" tool git-dir subcommand dir [word…]
#
# with the fields and marked words of the record format above. Returns 0 without
# calling anything when the payload holds no command. Dies (exit 2) when jq is
# missing or the git and gh invocations of the command cannot be read.
#
# Needs `die` from sh-common.sh, which the caller sources. Installs an EXIT trap
# that removes the temporary record file.
ils_each_invocation() {
	local callback="$1" input cwd records tool git_dir subcommand dir count word i
	local -a words
	input=$(</dev/stdin)
	command -v jq >/dev/null || die "jq is not on PATH; cannot read the hook input"
	# shellcheck disable=SC2034 # read by the sourcing hook
	ILS_COMMAND=$(jq -r '.tool_input.command // empty' <<<"$input")
	cwd=$(jq -r '.cwd // empty' <<<"$input")
	[[ -n "$ILS_COMMAND" ]] || return 0

	records=$(mktemp)
	# shellcheck disable=SC2064 # the path is fixed now, on purpose
	trap "rm -f '$records'" EXIT
	ils_invocations "${cwd:-$PWD}" "$ILS_COMMAND" >"$records" ||
		die "cannot read the git and gh invocations of the command"

	while IFS= read -r -d '' tool && IFS= read -r -d '' git_dir &&
		IFS= read -r -d '' subcommand && IFS= read -r -d '' dir &&
		IFS= read -r -d '' count; do
		words=()
		for ((i = 0; i < count; i++)); do
			IFS= read -r -d '' word && words+=("$word")
		done
		"$callback" "$tool" "$git_dir" "$subcommand" "$dir" ${words[@]+"${words[@]}"}
	done <"$records"
}

# ils_each_invocation callback for ils_each_git_invocation: passes a git
# invocation whose git dir is known on to ILS_GIT_CALLBACK with its literal
# arguments only, and skips every other invocation.
ils_call_git_callback() {
	local tool="$1" git_dir="$2" subcommand="$3" word
	local -a literals=()
	shift 4
	[[ "$tool" == git && -n "$git_dir" ]] || return 0
	for word; do
		[[ "$word" != =* ]] || literals+=("${word:1}")
	done
	"$ILS_GIT_CALLBACK" "$git_dir" "$subcommand" ${literals[@]+"${literals[@]}"}
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
	ILS_GIT_CALLBACK="$1"
	ils_each_invocation ils_call_git_callback
}
