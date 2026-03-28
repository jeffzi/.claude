#!/usr/bin/env bash
set -euo pipefail

# UserPromptSubmit hook: seed .planning/config.json from ~/.gsd/defaults.json
# when user types /gsd:new-project or /gsd:new-milestone.
# Ensures model overrides are available before gsd-tools init resolves models.

INPUT=$(cat)

# Check if the user's prompt matches
PROMPT=$(printf '%s' "$INPUT" | jq -re '.prompt // ""' 2>/dev/null)
case "$PROMPT" in
/gsd:new-project* | /gsd:new-milestone*) ;;
*) exit 0 ;;
esac

DEFAULTS="$HOME/.gsd/defaults.json"
[[ -f "$DEFAULTS" ]] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -re '.cwd // ""' 2>/dev/null)
[[ -z "$CWD" ]] && exit 0

# Seed at cwd (where gsd-tools process.cwd() will look)
if [[ ! -f "$CWD/.planning/config.json" ]]; then
	mkdir -p "$CWD/.planning"
	cp "$DEFAULTS" "$CWD/.planning/config.json"
fi

# Also seed at git root if different from cwd
PROJECT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$PROJECT_ROOT" ]] && [[ "$PROJECT_ROOT" != "$CWD" ]]; then
	if [[ ! -f "$PROJECT_ROOT/.planning/config.json" ]]; then
		mkdir -p "$PROJECT_ROOT/.planning"
		cp "$DEFAULTS" "$PROJECT_ROOT/.planning/config.json"
	fi
fi
