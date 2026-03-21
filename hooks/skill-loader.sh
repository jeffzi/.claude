#!/usr/bin/env bash
# SessionStart hook: injects using-skills skill into every conversation.
# Replaces superpowers plugin's session-start hook.

set -euo pipefail

SKILL_FILE="${HOME}/.claude/skills/using-skills/SKILL.md"

if [ ! -f "$SKILL_FILE" ]; then
	exit 0
fi

skill_content=$(cat "$SKILL_FILE" 2>/dev/null || exit 0)

# Escape string for JSON embedding using bash parameter substitution.
escape_for_json() {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	s="${s//$'\n'/\\n}"
	s="${s//$'\r'/\\r}"
	s="${s//$'\t'/\\t}"
	printf '%s' "$s"
}

escaped=$(escape_for_json "$skill_content")
context="<EXTREMELY_IMPORTANT>\nYou have skills.\n\n**Below is your 'using-skills' skill. For all other skills, use the 'Skill' tool:**\n\n---\n${escaped}\n\n</EXTREMELY_IMPORTANT>"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${context}"
  }
}
EOF

exit 0
