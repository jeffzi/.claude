#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

MODEL=$(printf '%s' "$input" | jq -r '.model.display_name')
EFFORT=$(printf '%s' "$input" | jq -r '.effort.level // empty')
[[ -n "$EFFORT" ]] && MODEL="$MODEL ($EFFORT)"
DIR=$(printf '%s' "$input" | jq -r '.workspace.current_dir')
PCT=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
# 0 until this session makes its first API call. rate_limits is carried over from
# the previous session until then, so a 0 here means the limit data is stale.
API_MS=$(printf '%s' "$input" | jq -r '.cost.total_api_duration_ms // 0')
FIVE_H=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
FIVE_H_RESET=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
WEEK=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
WEEK_RESET=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# 5h window: countdown ("2h10m"). 7d window: absolute date ("Jul12 09:00").
fmt_reset_countdown() {
	local reset_epoch="$1"
	[[ -z "$reset_epoch" ]] && return
	local now secs h m
	now=$(date +%s)
	secs=$((reset_epoch - now))
	((secs <= 0)) && return
	h=$((secs / 3600))
	m=$(((secs % 3600) / 60))
	if ((h > 0 && m > 0)); then
		printf '%dh%dm' "$h" "$m"
	elif ((h > 0)); then
		printf '%dh' "$h"
	else
		printf '%dm' "$m"
	fi
}

# macOS date -r; GNU would be date -d @epoch
fmt_reset_absolute() {
	local reset_epoch="$1"
	[[ -z "$reset_epoch" ]] && return
	((reset_epoch <= $(date +%s))) && return # stale/past reset — don't render a bygone date
	date -r "$reset_epoch" '+%b%d %H:%M'
}

# Even-pace delta: actual usage vs. linear spend rate across the window.
# Only shown above 50% — below that, pace is noise regardless of delta.
fmt_pace() {
	local used="$1" reset_epoch="$2" window_sec="$3"
	[[ -z "$reset_epoch" ]] && return
	local used_int now remaining expected delta
	used_int=${used%.*}
	((used_int < 50)) && return
	now=$(date +%s)
	remaining=$((reset_epoch - now))
	((remaining <= 0 || remaining > window_sec)) && return
	expected=$(((window_sec - remaining) * 100 / window_sec))
	delta=$((used_int - expected))
	if ((delta >= 15)); then
		printf '🔥🔥'
	elif ((delta >= 5)); then
		printf '🔥'
	elif ((delta <= -5)); then
		printf '🐢'
	fi
}

GREEN='\033[32m'
GRAY='\033[38;5;238m'
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
BAR="${FILL// /█}"
TRACK="${PAD// /█}"

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
if ((API_MS > 0)) && [[ -n "$FIVE_H" ]]; then
	FH_INT=$(printf '%.0f' "$FIVE_H")
	fh_pace=$(fmt_pace "$FH_INT" "$FIVE_H_RESET" 18000)
	fh_reset=$(fmt_reset_countdown "$FIVE_H_RESET")
	fh_detail=""
	[[ -n "$fh_pace" || -n "$fh_reset" ]] && fh_detail=" (${fh_pace}${fh_pace:+ }${fh_reset:+⏳${fh_reset}})"
	LIMITS=" │ 5h:${FH_INT}%${fh_detail}"
fi
if ((API_MS > 0)) && [[ -n "$WEEK" ]]; then
	WK_INT=$(printf '%.0f' "$WEEK")
	wk_pace=$(fmt_pace "$WK_INT" "$WEEK_RESET" 604800)
	wk_reset=$(fmt_reset_absolute "$WEEK_RESET")
	wk_detail=""
	[[ -n "$wk_pace" || -n "$wk_reset" ]] && wk_detail=" (${wk_pace}${wk_pace:+ }${wk_reset:+⏳${wk_reset}})"
	LIMITS="${LIMITS} │ 7d:${WK_INT}%${wk_detail}"
fi

printf '%b\n' "${DIR##*/} │ ${MODEL} ${CTX_COLOR}${BAR}${GRAY}${TRACK}${RESET} ${CTX_COLOR}${PCT}%${EMOJI}${RESET}${LIMITS}"
