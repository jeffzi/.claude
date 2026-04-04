#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────╮
# │                Plan Skill Guard Hook                   │
# ╰────────────────────────────────────────────────────────╯
# Fires on EnterPlanMode — reminds Claude to load write-plan first.

cat >&2 <<'MSG'
STOP: You MUST load Skill(write-plan) before entering plan mode.
If you have not loaded it yet, abort this action and load it now.
MSG

exit 0
