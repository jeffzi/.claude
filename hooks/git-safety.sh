#!/usr/bin/env bash
set -eo pipefail

# Git Safety Hook - Prevents committing plan files and auto-pushing

# Check dependencies
command -v jq >/dev/null || {
	echo "Error: jq is required" >&2
	exit 1
}

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Exit if no command found
[[ -z "$command" ]] && exit 0

# Patterns for grep (basic regex)
PLAN_PATTERNS_GREP=('\.claude/plans/' 'docs/plans/')

check_plan_files() {
	local files="$1"
	[[ -z "$files" ]] && return 0
	for pattern in "${PLAN_PATTERNS_GREP[@]}"; do
		if echo "$files" | grep -q "$pattern"; then
			echo "Error: Cannot stage/commit plan files matching '$pattern'. These are temporary analysis files." >&2
			return 1
		fi
	done
	return 0
}

# Block push operations
if [[ "$command" =~ git[[:space:]]+push ]]; then
	echo "Error: Automatic git push is not allowed. Review and push manually." >&2
	exit 2
fi

# Block git add with explicit plan file paths
if [[ "$command" =~ git[[:space:]]+add ]]; then
	for pattern in "${PLAN_PATTERNS_GREP[@]}"; do
		if [[ "$command" == *"$pattern"* ]]; then
			echo "Error: Cannot stage plan files matching '$pattern'. These are temporary analysis files." >&2
			exit 2
		fi
	done

	# Block broad adds (git add ., git add -A, git add -a, git add --all) if plan files would be included
	if [[ "$command" =~ git[[:space:]]+add[[:space:]]+(\.|(-[aA]|--all)) ]]; then
		root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
		pending_files=$(git -C "$root" ls-files --others --modified --exclude-standard 2>/dev/null)
		check_plan_files "$pending_files" || exit 2
	fi
fi

# Block commits if plan files are already staged
if [[ "$command" =~ git[[:space:]]+commit ]]; then
	root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
	staged_files=$(git -C "$root" diff --cached --name-only 2>/dev/null)
	check_plan_files "$staged_files" || exit 2
fi

exit 0
