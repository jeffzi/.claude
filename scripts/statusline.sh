#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
WEEK=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLINK='\033[5m'
RESET='\033[0m'

# Build progress bar (20 blocks)
BAR_WIDTH=20
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
printf -v FILL "%${FILLED}s"
printf -v PAD "%${EMPTY}s"
BAR="${FILL// /▓}${PAD// /░}"

# Zone: color thresholds (💀 only at 90%+)
if [[ "$PCT" -ge 90 ]]; then
	EMOJI=" 💀"
	CTX_COLOR="${BLINK}${RED}"
elif [[ "$PCT" -ge 75 ]]; then
	EMOJI=""
	CTX_COLOR="$RED"
elif [[ "$PCT" -ge 50 ]]; then
	EMOJI=""
	CTX_COLOR="$YELLOW"
else
	EMOJI=""
	CTX_COLOR="$GREEN"
fi

# Rate limits — absent before first API response or for non-subscribers
LIMITS=""
if [[ -n "$FIVE_H" ]]; then
	FH_INT=$(printf '%.0f' "$FIVE_H")
	LIMITS=" │ 5h:${FH_INT}%"
fi
if [[ -n "$WEEK" ]]; then
	WK_INT=$(printf '%.0f' "$WEEK")
	LIMITS="${LIMITS} │ 7d:${WK_INT}%"
fi

printf '%b\n' "${DIM}${MODEL}${RESET} │ ${DIM}${DIR##*/}${RESET}  ${CTX_COLOR}${BAR} ${PCT}%${EMOJI}${RESET}${LIMITS}"
