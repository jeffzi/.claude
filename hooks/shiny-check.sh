#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────╮
# │                   Shiny Check Hook                     │
# ╰────────────────────────────────────────────────────────╯
# Smoke-tests staged Shiny apps before git commit.
# Starts each app, waits for "Application startup complete",
# then kills the server. Catches import errors, broken
# templates, and runtime init failures that tests alone miss.

# Skip silently if uv not installed
command -v uv >/dev/null || exit 0

# Get staged Python files
staged_files=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.py$' || true)

[[ -z "$staged_files" ]] && exit 0

pid=""
output_file=""

# shellcheck disable=SC2329
cleanup() {
	if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	[[ -n "$output_file" && -f "$output_file" ]] && rm -f "$output_file"
}
trap cleanup EXIT

failed=0
while IFS= read -r file_path; do
	[[ -f "$file_path" ]] || continue

	# Detect Shiny app entry points only — skip module/helper files
	if grep -qE 'from shiny\.express import' "$file_path" 2>/dev/null; then
		: # Express mode app
	elif grep -qE 'from shiny import' "$file_path" 2>/dev/null &&
		grep -qE 'App\(' "$file_path" 2>/dev/null; then
		: # Core mode app with App()
	else
		continue
	fi

	printf "Running Shiny smoke test on %s...\n" "$file_path"

	output_file=$(mktemp)
	uv run shiny run "$file_path" --port 0 >"$output_file" 2>&1 &
	pid=$!

	# Wait up to 30s for startup or process exit
	success=false
	for ((i = 0; i < 30; i++)); do
		if ! kill -0 "$pid" 2>/dev/null; then
			break
		fi
		if grep -q "Application startup complete" "$output_file" 2>/dev/null; then
			success=true
			break
		fi
		sleep 1
	done

	# Kill server if still running
	if kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	pid=""

	if $success; then
		printf "Shiny smoke test passed for %s\n" "$file_path"
	else
		printf "Shiny smoke test failed for %s\n" "$file_path" >&2
		cat "$output_file" >&2
		printf "\n" >&2
		failed=1
	fi

	rm -f "$output_file"
	output_file=""
done <<<"$staged_files"

if [[ $failed -eq 1 ]]; then
	printf "Please fix the Shiny issues before committing.\n" >&2
	exit 2
fi

exit 0
