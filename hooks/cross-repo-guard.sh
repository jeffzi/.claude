#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │              Cross-Repository Write Guard                  │
# ╰────────────────────────────────────────────────────────────╯
# PreToolUse hook for Write|Edit: blocks file writes outside the
# session's git repository root.
#
# Input:  JSON on stdin — .cwd and .tool_input.file_path
# Output: stderr on block with diagnostic message
# Exit:   0 to allow, 2 to block

command -v jq >/dev/null || exit 0

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

[[ -z "$file_path" ]] && exit 0
[[ -z "$cwd" ]] && exit 0

# ── Resolve absolute file path ────────────────────────────────
# file_path may be relative; resolve it against cwd.
if [[ "$file_path" != /* ]]; then
	file_path="$cwd/$file_path"
fi

# ── Allow Claude's own workspace unconditionally ─────────────
# Plans, memory, and other harness files legitimately land in ~/.claude
# regardless of which project session is active.
claude_dir="${HOME}/.claude"
case "$file_path" in
"$claude_dir" | "$claude_dir"/*) exit 0 ;;
esac

# ── Get session's git root ────────────────────────────────────
# If cwd is not inside a git repo there is no boundary to enforce.
session_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

# ── Check boundary ────────────────────────────────────────────
# Allow if file_path is exactly the root or under it.
case "$file_path" in
"$session_root" | "$session_root"/*) exit 0 ;;
esac

# Outside the session's repository — block and explain.
printf "BLOCKED: %s is outside the current session's repository.\n" "$file_path" >&2
printf "Session root: %s\n" "$session_root" >&2
printf "To modify files in another repository, ask the user first or open a separate session in that directory.\n" >&2
exit 2
