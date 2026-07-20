#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │           Collaboration Reminder Hook                      │
# ╰────────────────────────────────────────────────────────────╯
# Re-injects the propose-decisions / answer-questions-first
# policy on every user prompt and after compaction, so it stays
# salient late in long sessions.
#
# Output: reminder text on stdout (appended to context)
# Exit: always 0

printf "%s\n" "User policy: questions or pushback in the latest message are addressed before any tool call — answered or explicitly deferred; work pauses if the answer could change it. Decisions with alternatives are proposed and confirmed before acting. Bypass/auto mode is not autonomy."
