#!/usr/bin/env bash
set -euo pipefail

readonly CLAUDE_DIR="$HOME/.claude"
readonly PROJECTS_DIR="$CLAUDE_DIR/projects"
max_age_days=7
dry_run=true

numfmt_bytes() {
	local bytes=$1
	local -r GiB=1073741824 MiB=1048576 KiB=1024
	if [[ "$bytes" -ge "$GiB" ]]; then
		printf "%.1f GB" "$(echo "$bytes / $GiB" | bc -l)"
	elif [[ "$bytes" -ge "$MiB" ]]; then
		printf "%.1f MB" "$(echo "$bytes / $MiB" | bc -l)"
	elif [[ "$bytes" -ge "$KiB" ]]; then
		printf "%.1f KB" "$(echo "$bytes / $KiB" | bc -l)"
	else
		printf "%d B" "$bytes"
	fi
}

# Discovers whether stat speaks BSD (-f%z) or GNU (-c%s), testing against this
# script itself (guaranteed to exist). Probing once and caching the working
# format avoids forking twice per file in the loops below.
detect_stat_size_fmt() {
	if stat -f%z "$0" >/dev/null 2>&1; then
		printf -- '-f%%z'
	elif stat -c%s "$0" >/dev/null 2>&1; then
		printf -- '-c%%s'
	fi
}
STAT_SIZE_FMT=$(detect_stat_size_fmt)
readonly STAT_SIZE_FMT

file_size() {
	[[ -n "$STAT_SIZE_FMT" ]] || {
		printf '0'
		return
	}
	# shellcheck disable=SC2086 # deliberate unquoted expansion of a single-token format string
	stat $STAT_SIZE_FMT "$1" 2>/dev/null || printf '0'
}

cleanup_find() {
	local dir="$1" label="$2"
	shift 2
	local size
	count=0 bytes=0
	[[ -d "$dir" ]] || return 0
	while IFS= read -r -d '' file; do
		size=$(file_size "$file")
		bytes=$((bytes + size))
		count=$((count + 1))
		$dry_run || rm -f "$file"
	done < <(find "$dir" "$@" -type f -mtime +"$max_age_days" -print0)
	if [[ -n "$label" && "$count" -gt 0 ]]; then
		printf '  %s: %d files (%s)\n' "$label" "$count" "$(numfmt_bytes "$bytes")"
		total_files=$((total_files + count))
		total_bytes=$((total_bytes + bytes))
	fi
}

for arg in "$@"; do
	[[ "$arg" == "--execute" ]] && dry_run=false
	[[ "$arg" =~ ^[0-9]+$ ]] && max_age_days="$arg"
done

$dry_run && printf '%s\n' "=== DRY RUN (add --execute to actually delete) ===" ||
	printf '%s\n' "=== EXECUTE MODE ==="
printf 'Target: files older than %s days\n' "$max_age_days"
printf '\n'

total_files=0
total_dirs=0
total_bytes=0

printf '%s\n' "[projects/ session logs]"
for project_dir in "$PROJECTS_DIR"/*/; do
	[[ -d "$project_dir" ]] || continue
	project_name=$(basename "$project_dir")
	project_files=0 project_dirs=0 project_bytes=0

	cleanup_find "$project_dir" "" -maxdepth 1 -name "*.jsonl"
	project_files=$((project_files + count))
	project_bytes=$((project_bytes + bytes))

	while IFS= read -r -d '' dir; do
		dirname=$(basename "$dir")
		[[ "$dirname" == "memory" ]] && continue
		if [[ "$dirname" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
			size=$(du -sk "$dir" 2>/dev/null | cut -f1)
			project_bytes=$((project_bytes + size * 1024))
			project_dirs=$((project_dirs + 1))
			$dry_run || rm -rf "$dir"
		fi
	done < <(find "$project_dir" -maxdepth 1 -type d -mtime +"$max_age_days" -not -path "$project_dir" -print0)

	if [[ $((project_files + project_dirs)) -gt 0 ]]; then
		printf '  %s: %d files, %d dirs (%s)\n' "$project_name" "$project_files" "$project_dirs" "$(numfmt_bytes "$project_bytes")"
		total_files=$((total_files + project_files))
		total_dirs=$((total_dirs + project_dirs))
		total_bytes=$((total_bytes + project_bytes))
	fi
done
printf '\n'

printf '%s\n' "[other temp data]"
cleanup_find "$CLAUDE_DIR/debug" "debug/"
cleanup_find "$CLAUDE_DIR/shell-snapshots" "shell-snapshots/"
cleanup_find "$CLAUDE_DIR/file-history" "file-history/"
cleanup_find "$CLAUDE_DIR/todos" "todos/"
cleanup_find "$CLAUDE_DIR/plans" "plans/"
cleanup_find "$CLAUDE_DIR/tasks" "tasks/"
cleanup_find "$CLAUDE_DIR/paste-cache" "paste-cache/"
cleanup_find "$CLAUDE_DIR/image-cache" "image-cache/"
cleanup_find "$CLAUDE_DIR" "security_warnings_state" -maxdepth 1 -name "security_warnings_state_*.json"

printf '\n'
printf '%s\n' "--- summary ---"
printf 'Files: %d\n' "$total_files"
printf 'Directories: %d (UUID sessions)\n' "$total_dirs"
printf 'Space saved: %s\n' "$(numfmt_bytes "$total_bytes")"
$dry_run && [[ $((total_files + total_dirs)) -gt 0 ]] && printf '\nTo delete: %s %s --execute\n' "$0" "$max_age_days"
