#!/usr/bin/env bash
set -euo pipefail

GREEN=$'\033[32m'
GRAY=$'\033[38;5;238m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
BLINK=$'\033[5m'
RESET=$'\033[0m'
BAR_WIDTH=20

# Team-plan sessions never receive the unified rate-limit headers, so stdin lacks
# .rate_limits entirely even though the data exists server-side
# (anthropics/claude-code#63659). Fetch it from the OAuth usage endpoint instead,
# throttled to one attempt per minute via a per-account cache file keyed on
# CLAUDE_CONFIG_DIR — the same key Claude Code uses to suffix its Keychain entry.
# Any failure leaves the cache empty, blanking the segment until a later render
# retries. Emits JSON in the stdin .rate_limits shape (resets_at as epoch seconds).
fetch_usage_fallback() {
	local now="$1"
	local suffix="default" cache service token response
	[[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && suffix=$(printf '%s' "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)
	cache="${TMPDIR:-/tmp}/claude-statusline-usage-${suffix}.json"
	if [[ -f "$cache" ]] && ((now - $(stat -f %m "$cache") < 60)); then
		cat "$cache"
		return
	fi
	: >"$cache" # claim the attempt window up front; a failed fetch stays blank
	trap 'rm -f "${cache}.tmp"' EXIT RETURN
	service="Claude Code-credentials"
	[[ "$suffix" != "default" ]] && service="${service}-${suffix}"
	token=$(security find-generic-password -s "$service" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
	[[ -z "$token" ]] && return
	response=$(curl -sS --max-time 2 \
		-H "Authorization: Bearer $token" \
		-H "anthropic-beta: oauth-2025-04-20" \
		https://api.anthropic.com/api/oauth/usage 2>/dev/null) || return
	printf '%s' "$response" | jq -c '
		def epoch: if . == null then null else (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) end;
		{
			five_hour: {used_percentage: .five_hour.utilization, resets_at: (.five_hour.resets_at | epoch)},
			seven_day: {used_percentage: .seven_day.utilization, resets_at: (.seven_day.resets_at | epoch)}
		}' >"${cache}.tmp" 2>/dev/null || return
	mv "${cache}.tmp" "$cache"
	cat "$cache"
}

# 5h window: countdown ("2h10m"). 7d window: absolute date ("Jul12 09:00").
fmt_reset_countdown() {
	local reset_epoch="$1" now="$2"
	[[ -z "$reset_epoch" ]] && return
	local secs h m
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

fmt_reset_absolute() {
	local reset_epoch="$1" now="$2"
	[[ -z "$reset_epoch" ]] && return
	((reset_epoch <= now)) && return # stale/past reset — don't render a bygone date
	date -r "$reset_epoch" '+%b%d %H:%M'
}

# One rendered segment (" │ 5h:61% (🔥 ⏳2h10m)"). reset_fmt names the formatter
# function — countdown for the 5h window, absolute date for the 7d window.
fmt_limit_segment() {
	local label="$1" used="$2" reset_epoch="$3" window_sec="$4" reset_fmt="$5" now="$6"
	local used_int pace reset detail=""
	used_int=$(printf '%.0f' "$used")
	pace=$(fmt_pace "$used_int" "$reset_epoch" "$window_sec" "$now")
	reset=$("$reset_fmt" "$reset_epoch" "$now")
	[[ -n "$pace" || -n "$reset" ]] && detail=" (${pace}${reset:+${pace:+ }⏳${reset}})"
	printf ' │ %s:%s%%%s' "$label" "$used_int" "$detail"
}

# Even-pace delta: actual usage vs. linear spend rate across the window.
# Only shown above 50% — below that, pace is noise regardless of delta.
fmt_pace() {
	local used_int="$1" reset_epoch="$2" window_sec="$3" now="$4"
	[[ -z "$reset_epoch" ]] && return
	local remaining expected delta
	((used_int < 50)) && return
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

main() {
	local input model effort dir pct api_ms rate_limits_json now
	input=$(cat)
	now=$(date +%s)

	# Batched into one jq pass — the script forks on every statusline render
	# (~300ms during activity), so per-field jq calls multiply into real latency.
	# \u001f (unit separator) not @tsv: read collapses runs of tabs — they are IFS
	# whitespace — so empty fields like a missing effort level would shift every
	# field after them.
	IFS=$'\037' read -r model effort dir pct api_ms < <(printf '%s' "$input" | jq -r '[
		.model.display_name,
		(.effort.level // ""),
		.workspace.current_dir,
		(.context_window.used_percentage // 0 | floor),
		(.cost.total_api_duration_ms // 0)
	] | map(tostring) | join("\u001f")') || true
	[[ -n "$effort" ]] && model="$model ($effort)"

	# Prefer stdin rate_limits (live per API response, no network cost); fall back
	# to the OAuth endpoint when absent. api_ms is 0 until this session's first API
	# call and stdin rate_limits is carried over from the previous session until
	# then — so a 0 means stale stdin data. The fallback is live server data and
	# needs no such gate.
	rate_limits_json=""
	((api_ms > 0)) && rate_limits_json=$(printf '%s' "$input" | jq -c '.rate_limits // empty') || true
	[[ -z "$rate_limits_json" ]] && rate_limits_json=$(fetch_usage_fallback "$now" || true)

	local five_h="" five_h_reset="" week="" week_reset=""
	[[ -n "$rate_limits_json" ]] && IFS=$'\037' read -r five_h five_h_reset week week_reset < <(printf '%s' "$rate_limits_json" | jq -r '[
		(.five_hour.used_percentage // ""),
		(.five_hour.resets_at // ""),
		(.seven_day.used_percentage // ""),
		(.seven_day.resets_at // "")
	] | map(tostring) | join("\u001f")') || true

	local filled empty fill pad bar track
	# used_percentage can exceed 100 (context overflow) — cap the bar, not the % text
	filled=$((pct * BAR_WIDTH / 100))
	((filled > BAR_WIDTH)) && filled="$BAR_WIDTH"
	empty=$((BAR_WIDTH - filled))
	printf -v fill "%${filled}s"
	printf -v pad "%${empty}s"
	bar="${fill// /█}"
	track="${pad// /█}"

	local emoji ctx_color
	if ((pct >= 90)); then
		emoji=" 💀"
		ctx_color="${BLINK}${RED}"
	elif ((pct >= 75)); then
		emoji=""
		ctx_color="$RED"
	elif ((pct >= 50)); then
		emoji=""
		ctx_color="$YELLOW"
	else
		emoji=""
		ctx_color="$GREEN"
	fi

	# Rate limits — absent for non-subscribers or when both sources came up empty
	local limits=""
	[[ -n "$five_h" ]] && limits+=$(fmt_limit_segment "5h" "$five_h" "$five_h_reset" 18000 fmt_reset_countdown "$now")
	[[ -n "$week" ]] && limits+=$(fmt_limit_segment "7d" "$week" "$week_reset" 604800 fmt_reset_absolute "$now")

	printf '%s\n' "${dir##*/} │ ${model} ${ctx_color}${bar}${GRAY}${track}${RESET} ${ctx_color}${pct}%${emoji}${RESET}${limits}"
}

main "$@"
