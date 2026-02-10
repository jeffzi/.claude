#!/usr/bin/env bash
set -eo pipefail

# ╭────────────────────────────────────────────────────────╮
# │                   Marimo Check Hook                    │
# ╰────────────────────────────────────────────────────────╯
# Validates marimo notebooks before git commit

# Skip silently if uvx not installed
command -v uvx >/dev/null || exit 0

# Get staged Python files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.py$' || true)

[[ -z "$STAGED_FILES" ]] && exit 0

FAILED=0
for FILE_PATH in $STAGED_FILES; do
	[[ -f "$FILE_PATH" ]] || continue

	# Check if the file appears to be a marimo notebook
	if grep -qE '(import marimo|@app\.cell)' "$FILE_PATH" 2>/dev/null; then
		echo "Running marimo check on $FILE_PATH..."

		if ! CHECK_OUTPUT=$(timeout 30 uvx marimo check "$FILE_PATH" 2>&1); then
			echo "Marimo check failed for $FILE_PATH" >&2
			echo "$CHECK_OUTPUT" >&2
			echo "" >&2
			FAILED=1
		else
			echo "Marimo check passed for $FILE_PATH"
		fi
	fi
done

if [[ $FAILED -eq 1 ]]; then
	echo "Please fix the marimo issues before committing." >&2
	exit 2
fi

exit 0
