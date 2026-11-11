#!/usr/bin/env bash
set -euo pipefail

# Sweep Claude Code's per-session data older than a cutoff.
#
# Usage: cleanup-sessions.sh [days] [--execute]
#
# Dry-run by default: reports what would go and how much space it holds. Only
# --execute deletes.

# `bash cleanup-sessions.sh` run from inside scripts/ leaves no slash to strip a
# directory at.
SCRIPT_SOURCE=${BASH_SOURCE[0]}
[[ "$SCRIPT_SOURCE" == */* ]] || SCRIPT_SOURCE="./$SCRIPT_SOURCE"
# `die` and portable stat access.
# shellcheck source=SCRIPTDIR/sh-common.sh
. "${SCRIPT_SOURCE%/*}/sh-common.sh"
PROG=cleanup-sessions

# The active config directory: CLAUDE_CONFIG_DIR when Claude Code runs under one.
readonly CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
readonly PROJECTS_DIR="$CLAUDE_DIR/projects"
readonly USAGE="usage: cleanup-sessions.sh [days] [--execute]"
readonly SESSION_DIR_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# Prints $1 bytes as a human-readable size with one decimal, rounded half up.
# Integer arithmetic only: no bc, no float printf.
numfmt_bytes() {
	local bytes="$1" unit divisor tenths
	local -r GIB=1073741824 MIB=1048576 KIB=1024
	if ((bytes >= GIB)); then
		unit=GB divisor=$GIB
	elif ((bytes >= MIB)); then
		unit=MB divisor=$MIB
	elif ((bytes >= KIB)); then
		unit=KB divisor=$KIB
	else
		printf '%d B' "$bytes"
		return
	fi
	tenths=$(((bytes * 20 / divisor + 1) / 2))
	printf '%d.%d %s' $((tenths / 10)) $((tenths % 10)) "$unit"
}

# Sets the caller's `max_age_days` and `dry_run` from argv.
parse_args() {
	local arg
	for arg in "$@"; do
		case "$arg" in
		--execute) dry_run=false ;;
		-h | --help)
			printf '%s\n' "$USAGE"
			exit 0
			;;
		*)
			[[ "$arg" =~ ^[0-9]+$ ]] || die "unknown argument '$arg'; $USAGE"
			max_age_days="$arg"
			;;
		esac
	done
}

# Sets the caller's `listing` to a new temporary file for a sweep's find
# listing, removed when the shell exits. Each sweep runs in its own process
# substitution, so the EXIT trap belongs to that subshell. A find writes its
# whole listing before the sweep reads it, so a traversal error fails the sweep,
# whose missing summary its reader turns into a die, instead of leaving a short
# total behind exit 0.
make_sweep_listing() {
	listing=$(mktemp) || return 1
	# shellcheck disable=SC2064 # the path is fixed now, on purpose
	trap "rm -f '$listing'" EXIT
}

# Prints "<count> <bytes> <unmeasured>" for the files under $1 older than the
# cutoff (extra find predicates after $1 narrow the match), deleting them unless
# dry-run. A file stat cannot read — gone between find and stat, or unreadable —
# is counted but not measured, and reported as such rather than as zero bytes.
sweep_files() {
	local dir="$1"
	shift
	local count=0 bytes=0 unmeasured=0 file size listing
	[[ -d "$dir" ]] || {
		printf '0 0 0\n'
		return
	}
	make_sweep_listing || return 1
	find "$dir" "$@" -type f -mtime +"$max_age_days" -print0 >"$listing" || return 1
	while IFS= read -r -d '' file; do
		if size=$(sh_file_attr size "$file"); then
			bytes=$((bytes + size))
		else
			unmeasured=$((unmeasured + 1))
		fi
		count=$((count + 1))
		$dry_run || rm -f "$file"
	done <"$listing"
	printf '%d %d %d\n' "$count" "$bytes" "$unmeasured"
}

# Prints "<dirs> <bytes> <unmeasured>" for the UUID session directories directly
# under $1 older than the cutoff, deleting them unless dry-run. A directory's own
# mtime ignores writes in its subdirectories (e.g. `subagents/`), so one holding
# anything newer than the cutoff is kept. A directory du cannot size is counted
# but not measured. `memory/` is never swept.
sweep_session_dirs() {
	local project_dir="$1"
	local dirs=0 bytes=0 unmeasured=0 dir dir_kb newer listing
	make_sweep_listing || return 1
	find "$project_dir" -maxdepth 1 -type d -mtime +"$max_age_days" -not -path "$project_dir" -print0 >"$listing" ||
		return 1
	while IFS= read -r -d '' dir; do
		[[ "$(basename "$dir")" =~ $SESSION_DIR_RE ]] || continue
		newer=$(find "$dir" ! -mtime +"$max_age_days" -print -quit) || return 1
		[[ -z "$newer" ]] || continue
		dir_kb=$(du -sk "$dir" 2>/dev/null | cut -f1) || dir_kb=""
		if [[ -n "$dir_kb" ]]; then
			bytes=$((bytes + dir_kb * 1024))
		else
			unmeasured=$((unmeasured + 1))
		fi
		dirs=$((dirs + 1))
		$dry_run || rm -rf "$dir"
	done <"$listing"
	printf '%d %d %d\n' "$dirs" "$bytes" "$unmeasured"
}

# Sweeps $1 and prints a line for it under label $2 when anything matched.
# Accumulates into the caller's total_files, total_bytes, and total_unmeasured.
# The sweep runs in a process substitution, so its own failure cannot stop this
# script; a sweep that dies before printing its summary makes the read hit EOF,
# and that failed read is what catches it.
report_sweep() {
	local dir="$1" label="$2"
	shift 2
	local count bytes unmeasured
	read -r count bytes unmeasured < <(sweep_files "$dir" "$@") || die "sweeping $dir failed." 1
	((count > 0)) || return 0
	printf '  %s: %d files (%s)\n' "$label" "$count" "$(numfmt_bytes "$bytes")"
	total_files=$((total_files + count))
	total_bytes=$((total_bytes + bytes))
	total_unmeasured=$((total_unmeasured + unmeasured))
}

# Sweeps one project's session logs and session directories, printing a line
# when anything matched. Accumulates into the caller's totals like report_sweep.
report_project() {
	local project_dir="$1"
	local files bytes unmeasured dirs dir_bytes dirs_unmeasured
	read -r files bytes unmeasured < <(sweep_files "$project_dir" -maxdepth 1 -name "*.jsonl") ||
		die "sweeping $project_dir failed." 1
	read -r dirs dir_bytes dirs_unmeasured < <(sweep_session_dirs "$project_dir") ||
		die "sweeping session directories under $project_dir failed." 1
	((files + dirs > 0)) || return 0
	printf '  %s: %d files, %d dirs (%s)\n' "$(basename "$project_dir")" "$files" "$dirs" \
		"$(numfmt_bytes $((bytes + dir_bytes)))"
	total_files=$((total_files + files))
	total_dirs=$((total_dirs + dirs))
	total_bytes=$((total_bytes + bytes + dir_bytes))
	total_unmeasured=$((total_unmeasured + unmeasured + dirs_unmeasured))
}

main() {
	local max_age_days=7 dry_run=true
	local total_files=0 total_dirs=0 total_bytes=0 total_unmeasured=0
	local project_dir name

	parse_args "$@"
	sh_stat_usable ||
		die "$SH_STAT_UNUSABLE_MSG; file sizes cannot be measured." 1

	if $dry_run; then
		printf '%s\n' "=== DRY RUN (add --execute to actually delete) ==="
	else
		printf '%s\n' "=== EXECUTE MODE ==="
	fi
	printf 'Target: files older than %s days\n' "$max_age_days"
	printf '\n'

	printf '%s\n' "[projects/ session logs]"
	for project_dir in "$PROJECTS_DIR"/*/; do
		[[ -d "$project_dir" ]] || continue
		report_project "$project_dir"
	done
	printf '\n'

	printf '%s\n' "[other temp data]"
	for name in debug shell-snapshots file-history todos plans tasks paste-cache image-cache; do
		report_sweep "$CLAUDE_DIR/$name" "$name/"
	done
	report_sweep "$CLAUDE_DIR" "security_warnings_state" -maxdepth 1 -name "security_warnings_state_*.json"

	printf '\n'
	printf '%s\n' "--- summary ---"
	printf 'Files: %d\n' "$total_files"
	printf 'Directories: %d (UUID sessions)\n' "$total_dirs"
	printf 'Space saved: %s\n' "$(numfmt_bytes "$total_bytes")"
	if ((total_unmeasured > 0)); then
		printf 'Unmeasured: %d entries (their size could not be read; not counted in the space)\n' "$total_unmeasured"
	fi
	if $dry_run && ((total_files + total_dirs > 0)); then
		printf '\nTo delete: %s %s --execute\n' "$0" "$max_age_days"
	fi
}

main "$@"
