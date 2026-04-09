#!/bin/bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"
MAX_AGE_DAYS=7
DRY_RUN=true

numfmt_bytes() {
	local bytes=$1
	if [ "$bytes" -ge 1073741824 ]; then
		printf "%.1f GB" "$(echo "$bytes / 1073741824" | bc -l)"
	elif [ "$bytes" -ge 1048576 ]; then
		printf "%.1f MB" "$(echo "$bytes / 1048576" | bc -l)"
	elif [ "$bytes" -ge 1024 ]; then
		printf "%.1f KB" "$(echo "$bytes / 1024" | bc -l)"
	else
		printf "%d B" "$bytes"
	fi
}

cleanup_files() {
	local dir="$1" pattern="$2" label="$3"
	local count=0 bytes=0
	[ -d "$dir" ] || return 0
	while IFS= read -r -d '' file; do
		local size
		size=$(stat -f%z "$file" 2>/dev/null || echo 0)
		bytes=$((bytes + size))
		count=$((count + 1))
		$DRY_RUN || rm -f "$file"
	done < <(find "$dir" -maxdepth 1 -name "$pattern" -type f -mtime +"$MAX_AGE_DAYS" -print0)
	if [ "$count" -gt 0 ]; then
		echo "  $label: ${count} files ($(numfmt_bytes "$bytes"))"
		total_files=$((total_files + count))
		total_bytes=$((total_bytes + bytes))
	fi
}

cleanup_dir_contents() {
	local dir="$1" label="$2"
	local count=0 bytes=0
	[ -d "$dir" ] || return 0
	while IFS= read -r -d '' file; do
		local size
		size=$(stat -f%z "$file" 2>/dev/null || echo 0)
		bytes=$((bytes + size))
		count=$((count + 1))
		$DRY_RUN || rm -f "$file"
	done < <(find "$dir" -type f -mtime +"$MAX_AGE_DAYS" -print0)
	if [ "$count" -gt 0 ]; then
		echo "  $label: ${count} files ($(numfmt_bytes "$bytes"))"
		total_files=$((total_files + count))
		total_bytes=$((total_bytes + bytes))
	fi
}

for arg in "$@"; do
	[[ "$arg" == "--execute" ]] && DRY_RUN=false
	[[ "$arg" =~ ^[0-9]+$ ]] && MAX_AGE_DAYS="$arg"
done

$DRY_RUN && echo "=== DRY RUN (add --execute to actually delete) ===" ||
	echo "=== EXECUTE MODE ==="
echo "Target: files older than ${MAX_AGE_DAYS} days"
echo ""

total_files=0
total_dirs=0
total_bytes=0

echo "[projects/ session logs]"
for project_dir in "$PROJECTS_DIR"/*/; do
	[ -d "$project_dir" ] || continue
	project_name=$(basename "$project_dir")
	project_files=0 project_dirs=0 project_bytes=0

	while IFS= read -r -d '' file; do
		size=$(stat -f%z "$file" 2>/dev/null || echo 0)
		project_bytes=$((project_bytes + size))
		project_files=$((project_files + 1))
		$DRY_RUN || rm -f "$file"
	done < <(find "$project_dir" -maxdepth 1 -name "*.jsonl" -type f -mtime +"$MAX_AGE_DAYS" -print0)

	while IFS= read -r -d '' dir; do
		dirname=$(basename "$dir")
		[[ "$dirname" == "memory" ]] && continue
		if [[ "$dirname" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
			size=$(du -sk "$dir" 2>/dev/null | cut -f1)
			project_bytes=$((project_bytes + size * 1024))
			project_dirs=$((project_dirs + 1))
			$DRY_RUN || rm -rf "$dir"
		fi
	done < <(find "$project_dir" -maxdepth 1 -type d -mtime +"$MAX_AGE_DAYS" -not -path "$project_dir" -print0)

	if [ $((project_files + project_dirs)) -gt 0 ]; then
		echo "  $project_name: ${project_files} files, ${project_dirs} dirs ($(numfmt_bytes $project_bytes))"
		total_files=$((total_files + project_files))
		total_dirs=$((total_dirs + project_dirs))
		total_bytes=$((total_bytes + project_bytes))
	fi
done
echo ""

echo "[other temp data]"
cleanup_dir_contents "$CLAUDE_DIR/debug" "debug/"
cleanup_dir_contents "$CLAUDE_DIR/shell-snapshots" "shell-snapshots/"
cleanup_dir_contents "$CLAUDE_DIR/file-history" "file-history/"
cleanup_dir_contents "$CLAUDE_DIR/todos" "todos/"
cleanup_dir_contents "$CLAUDE_DIR/plans" "plans/"
cleanup_dir_contents "$CLAUDE_DIR/tasks" "tasks/"
cleanup_dir_contents "$CLAUDE_DIR/paste-cache" "paste-cache/"
cleanup_dir_contents "$CLAUDE_DIR/image-cache" "image-cache/"
cleanup_files "$CLAUDE_DIR" "security_warnings_state_*.json" "security_warnings_state"

echo ""
echo "--- summary ---"
echo "Files: ${total_files}"
echo "Directories: ${total_dirs} (UUID sessions)"
echo "Space saved: $(numfmt_bytes $total_bytes)"
$DRY_RUN && [ $((total_files + total_dirs)) -gt 0 ] && echo "" && echo "To delete: $0 ${MAX_AGE_DAYS} --execute"
