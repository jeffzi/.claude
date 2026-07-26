#!/usr/bin/env bash
set -euo pipefail

# Fires on ExitPlanMode — blocks until verification agents have run.

printf >&2 '%s\n' \
	"STOP — Pre-Exit Gate. Both must be done before ExitPlanMode:" \
	"" \
	"1. claim-reviewer agent: dispatched and verdicts incorporated into the plan." \
	"2. Plan review agent (2+ tasks): general-purpose agent dispatched and feedback incorporated." \
	"" \
	"Look for agent results in the conversation. If you cannot find them — especially after" \
	"compaction — dispatch now. 'I already verified' is not evidence; agent results are."

exit 0
