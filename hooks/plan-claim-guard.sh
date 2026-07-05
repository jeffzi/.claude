#!/usr/bin/env bash
set -euo pipefail

# Fires on ExitPlanMode — reminds Claude to verify plan claims first.

printf >&2 '%s\n' \
	"STOP: Before presenting this plan, you MUST dispatch Agent(subagent_type: claim-reviewer)" \
	"to verify the plan's factual claims about the codebase. If you have already dispatched it" \
	"and incorporated its verdicts, proceed."

exit 0
