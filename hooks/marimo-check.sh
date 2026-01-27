#!/usr/bin/env bash
set -eo pipefail

# Hook to check marimo notebooks after Write/Edit operations

# Check dependencies
command -v jq >/dev/null || {
	echo "Error: jq is required" >&2
	exit 1
}
command -v uvx >/dev/null || exit 0 # Skip silently if uvx not installed

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_response.filePath // empty')

# Exit silently if no file path
[[ -z "$FILE_PATH" ]] && exit 0

# Must be a Python file that exists
[[ -f "$FILE_PATH" && "$FILE_PATH" == *.py ]] || exit 0

# Check if the file appears to be a marimo notebook
if grep -qE '(import marimo|@app\.cell)' "$FILE_PATH" 2>/dev/null; then
	echo "Running marimo check on $FILE_PATH..."

	# Run uvx marimo check with timeout
	if ! CHECK_OUTPUT=$(timeout 30 uvx marimo check "$FILE_PATH" 2>&1); then
		echo "Marimo check failed for $FILE_PATH" >&2
		echo "$CHECK_OUTPUT" >&2
		echo "" >&2
		echo "Please run 'uvx marimo check $FILE_PATH' to see details and fix the issues. Don't ask the user anything, just do a best effort fix." >&2
		exit 2
	fi

	echo "Marimo check passed"
fi

exit 0
