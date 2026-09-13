#!/usr/bin/env bash
set -euo pipefail

# Sweep Claude Code's per-session data older than a cutoff.
#
# Usage: cleanup-sessions.sh [days] [--execute]
#
# Dry-run by default: reports what would go and how much space it holds. Only
# --execute deletes.

# `die` and portable stat access.
# shellcheck source=SCRIPTDIR/sh-common.sh
. "${BASH_SOURCE[0]%/*}/sh-common.sh"
PROG=cleanup-sessions

readonly CLAUDE_DIR="$HOME/.claude"
readonly PROJECTS_DIR="$CLAUDE_DIR/projects"
readonly USAGE="usage: cleanup-sessions.sh [days] [--execute]"

# Prints $1 bytes as a human-readable size with one decimal, rounded half up.
# Integer arithmetic only: no bc, no float printf.
numfmt_bytes() {
	local bytes="$1" unit divisor tenths
	local -r GiB=1073741824 MiB=1048576 KiB=1024
	if ((bytes >= GiB)); then
		unit=GB divisor=$GiB
	elif ((bytes >= MiB)); then
		unit=MB divisor=$MiB
	elif ((bytes >= KiB)); then
		unit=KB divisor=$KiB
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

# Prints "<count> <bytes> <unmeasured>" for the files under $1 older than the
# cutoff (extra find predicates after $1 narrow the match), deleting them unless
# dry-run. A file stat cannot read — gone between find and stat, or unreadable —
# is counted but not measured, and reported as such rather than as zero bytes.
sweep_files() {
	local dir="$1"
	shift
	local count=0 bytes=0 unmeasured=0 file size
	[[ -d "$dir" ]] || {
		printf '0 0 0\n'
		return
	}
	while IFS= read -r -d '' file; do
		if size=$(sh_file_attr size "$file"); then
			bytes=$((bytes + size))
		else
			unmeasured=$((unmeasured + 1))
		fi
		count=$((count + 1))
		$dry_run || rm -f "$file"
	done < <(find "$dir" "$@" -type f -mtime +"$max_age_days" -print0)
	printf '%d %d %d\n' "$count" "$bytes" "$unmeasured"
}

# Prints "<dirs> <bytes> <unmeasured>" for the UUID session directories directly
# under $1 older than the cutoff, deleting them unless dry-run. A directory du
# cannot size is counted but not measured. `memory/` is never swept.
sweep_session_dirs() {
	local project_dir="$1"
	local dirs=0 bytes=0 unmeasured=0 dir dir_kb
	while IFS= read -r -d '' dir; do
		[[ "$(basename "$dir")" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || continue
		dir_kb=$(du -sk "$dir" 2>/dev/null | cut -f1) || dir_kb=""
		if [[ -n "$dir_kb" ]]; then
			bytes=$((bytes + dir_kb * 1024))
		else
			unmeasured=$((unmeasured + 1))
		fi
		dirs=$((dirs + 1))
		$dry_run || rm -rf "$dir"
	done < <(find "$project_dir" -maxdepth 1 -type d -mtime +"$max_age_days" -not -path "$project_dir" -print0)
	printf '%d %d %d\n' "$dirs" "$bytes" "$unmeasured"
}

# Sweeps $1 and prints a line for it under label $2 when anything matched.
# Accumulates into the caller's total_files, total_bytes, and total_unmeasured.
# The sweep runs in a process substitution, so its own failure cannot stop this
# script; an incomplete answer is caught here instead.
report_sweep() {
	local dir="$1" label="$2"
	shift 2
	local count bytes unmeasured
	read -r count bytes unmeasured < <(sweep_files "$dir" "$@")
	[[ -n "$unmeasured" ]] || die "sweeping $dir failed." 1
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
	read -r files bytes unmeasured < <(sweep_files "$project_dir" -maxdepth 1 -name "*.jsonl")
	[[ -n "$unmeasured" ]] || die "sweeping $project_dir failed." 1
	read -r dirs dir_bytes dirs_unmeasured < <(sweep_session_dirs "$project_dir")
	[[ -n "$dirs_unmeasured" ]] || die "sweeping session directories under $project_dir failed." 1
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
	local project_dir

	parse_args "$@"
	((${#SH_STAT_SIZE_FMT[@]})) ||
		die "stat answers neither BSD (-f %z) nor GNU (-c %s) format flags; sizes cannot be measured." 1

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
	report_sweep "$CLAUDE_DIR/debug" "debug/"
	report_sweep "$CLAUDE_DIR/shell-snapshots" "shell-snapshots/"
	report_sweep "$CLAUDE_DIR/file-history" "file-history/"
	report_sweep "$CLAUDE_DIR/todos" "todos/"
	report_sweep "$CLAUDE_DIR/plans" "plans/"
	report_sweep "$CLAUDE_DIR/tasks" "tasks/"
	report_sweep "$CLAUDE_DIR/paste-cache" "paste-cache/"
	report_sweep "$CLAUDE_DIR/image-cache" "image-cache/"
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
