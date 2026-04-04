#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │               Config Protection Guard                      │
# ╰────────────────────────────────────────────────────────────╯
# PreToolUse hook for Write|Edit: blocks edits to linter/formatter
# config files. Forces Claude to fix code instead of weakening configs.

command -v jq >/dev/null || exit 0

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[[ -n "$file_path" ]] || exit 0

basename=$(basename "$file_path")

# ── Deny-list: files whose sole purpose is linter/formatter config ──
case "$basename" in
.eslintrc* | eslint.config.*) ;;
.prettierrc* | prettier.config.*) ;;
biome.json | biome.jsonc) ;;
ruff.toml | .ruff.toml) ;;
.markdownlint-cli2* | .markdownlint*) ;;
dprint.json) ;;
.swiftlint.yml) ;;
luacheck* | .luacheckrc) ;;
.editorconfig) ;;
*) exit 0 ;;
esac

# ── Block: linter/formatter config edit ──────────────────────
jq -n \
	--arg reason "BLOCKED: Editing linter/formatter config ($basename). Fix the code instead of weakening the config. If this config change is genuinely needed, ask the user for permission first." \
	'{ "decision": "block", "reason": $reason }'
exit 2
