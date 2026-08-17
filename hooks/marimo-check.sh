#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────╮
# │                   Marimo Check Hook                    │
# ╰────────────────────────────────────────────────────────╯
# Validates marimo notebooks before git commit

command -v uvx >/dev/null || exit 0

staged_files=$(git --no-optional-locks diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.py$' || true)

[[ -z "$staged_files" ]] && exit 0

failed=0
while IFS= read -r file_path; do
	[[ -f "$file_path" ]] || continue

	if grep -qE '(import marimo|@app\.cell)' "$file_path" 2>/dev/null; then
		printf "Running marimo check on %s...\n" "$file_path"

		if ! check_output=$(timeout 30 uvx marimo check "$file_path" 2>&1); then
			printf "Marimo check failed for %s\n" "$file_path" >&2
			printf "%s\n" "$check_output" >&2
			printf "\n" >&2
			failed=1
		else
			printf "Marimo check passed for %s\n" "$file_path"
		fi
	fi
done <<<"$staged_files"

if [[ $failed -eq 1 ]]; then
	printf "Please fix the marimo issues before committing.\n" >&2
	exit 2
fi

exit 0
