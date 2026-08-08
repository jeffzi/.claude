#!/usr/bin/env bash
set -euo pipefail

AMBER=$'\033[38;5;208m'
RED=$'\033[31m'
GREEN=$'\033[32m'
RESET=$'\033[0m'
BAR_WIDTH=5
FIVE_HOUR_SECONDS=$((5 * 3600))
SEVEN_DAY_SECONDS=$((7 * 24 * 3600))

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
	local mtime
	mtime=$(stat -f %m "$cache" 2>/dev/null) || mtime=0
	if [[ -f "$cache" ]] && ((now - mtime < 60)); then
		cat "$cache"
		return
	fi
	: >"$cache" # claim the attempt window up front; a failed fetch stays blank
	trap 'rm -f "${cache}.tmp"' RETURN
	service="Claude Code-credentials"
	[[ "$suffix" != "default" ]] && service="${service}-${suffix}"
	token=$(security find-generic-password -s "$service" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty') || return
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

# Converts HSL (hue in degrees, saturation/lightness in permille) to a
# truecolor escape sequence. Bash has no floats, so every value is held in
# permille and converted to 0-255 only at the end; truncation costs at most
# one unit per channel against the real-valued formula. The hue-sector step
# of the standard HSL → RGB conversion is inlined for 0-60° — the only sector
# usage_color's ramp reaches, since it tops out at 50° hue (green starts at
# 60°, which is what keeps mid usage gold instead of green).
hsl2rgb() {
	local hue="$1" sat="$2" light="$3"
	local dev chroma mid base r g b
	dev=$((light * 2 - 1000))
	((dev < 0)) && dev=$((-dev))
	chroma=$(((1000 - dev) * sat / 1000))
	mid=$((chroma * hue / 60))
	base=$((light - chroma / 2))
	r=$(((chroma + base) * 255 / 1000))
	g=$(((mid + base) * 255 / 1000))
	b=$((base * 255 / 1000))
	printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Maps a usage percentage onto an HSL ramp, off which hsl2rgb renders the
# truecolor escape. Saturation ramps quadratically over the lower half (3.5%
# at 12%, 60% at 50%), so a quiet session reads as gray rather than a colored
# warning; the upper half swings hue 50° → 0°, carrying gold through orange
# into red.
#
# Lightness starts at 75% — RGB(191,191,191), close to the default foreground of
# a dark terminal — and dims to the 53% the upper half starts from. Keep the base
# light: a darker gray makes a near-idle bar all but invisible.
usage_color() {
	local pct="$1"
	local t hue sat light
	((pct < 0)) && pct=0
	((pct > 100)) && pct=100 # used_percentage can overflow past 100
	if ((pct <= 50)); then
		t=$((pct * 20)) # pct / 50, in permille
		hue=50
		sat=$((t * t * 600 / 1000000))
		light=$((750 - t * 220 / 1000))
	else
		t=$(((pct - 50) * 20)) # (pct - 50) / 50, in permille
		hue=$((50 - t * 50 / 1000))
		sat=$((600 + t * 400 / 1000))
		light=$((530 + t * 100 / 1000))
	fi
	# Below ~5% saturation the color is achromatic and won't match the
	# terminal's native foreground — return nothing so text inherits it.
	((sat < 50)) && return
	hsl2rgb "$hue" "$sat" "$light"
}

# One rendered segment (" │ 5h:61% (↑ 2h10m)"). Only the ":61%" carries the usage
# gradient; the label and the reset time use the terminal's default color, so the
# gradient marks usage alone.
# reset_fmt names the formatter function — countdown for the 5h window, absolute
# date for the 7d window.
fmt_limit_segment() {
	local label="$1" used="$2" reset_epoch="$3" window_sec="$4" reset_fmt="$5" now="$6"
	local used_int color pace reset detail=""
	used_int=$(printf '%.0f' "$used")
	color=$(usage_color "$used_int")
	pace=$(fmt_pace "$used_int" "$reset_epoch" "$window_sec" "$now")
	reset=$("$reset_fmt" "$reset_epoch" "$now")
	if [[ -n "$reset" ]]; then
		[[ -n "$pace" ]] && pace+=" "
		detail=" (${pace}${reset})"
	elif [[ -n "$pace" ]]; then
		detail=" (${pace})"
	fi
	printf ' │ %s%s:%s%%%s%s' "$label" "$color" "$used_int" "$RESET" "$detail"
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
		printf '%s↑↑%s' "$RED" "$RESET"
	elif ((delta >= 5)); then
		printf '%s↑%s' "$AMBER" "$RESET"
	elif ((delta <= -5)); then
		printf '%s↓%s' "$GREEN" "$RESET"
	fi
}

# Context gauge plus its percentage ("● ◎ ○ ○ ○ 30%"). Each of BAR_WIDTH slots is
# ● full, ◎ half, or ○ empty; a slot's fractional fill snaps to the nearest of the
# three at the quarter marks.
#
# The three glyphs are concentric circles (U+25CF, U+25CE, U+25CB), all of
# unambiguous East Asian width, so each occupies exactly one cell. Do not reach for
# the half-circle family (◐ ◑ ◒ ◓) for the half state: those are ambiguous-width and
# terminals render them double-width, dwarfing ● and ○.
#
# Full slots, the half slot, and the percentage text wear the usage gradient. Only empty
# slots stay uncolored, matching the default foreground of the model name beside them.
fmt_context_bar() {
	local pct="$1"
	local color units full frac slot out=""
	color=$(usage_color "$pct")
	# Hundredths of a slot, so the fill stays integral: pct * BAR_WIDTH / 100 slots.
	units=$((pct * BAR_WIDTH))
	# used_percentage can exceed 100 (context overflow) — cap the gauge, not the % text
	if ((units > 100 * BAR_WIDTH)); then
		units=$((100 * BAR_WIDTH))
	fi
	full=$((units / 100))
	frac=$((units % 100))
	if ((frac >= 75)); then
		full=$((full + 1))
		frac=0
	fi
	for ((slot = 0; slot < BAR_WIDTH; slot++)); do
		if ((slot < full)); then
			out+="${color}●${RESET} "
		elif ((slot == full && frac >= 25)); then
			out+="${color}◎${RESET} "
		else
			out+="○ "
		fi
	done
	printf '%s%s%s%%%s' "$out" "$color" "$pct" "$RESET"
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
	local jq_out
	jq_out=$(printf '%s' "$input" | jq -r '[
		.model.display_name,
		(.effort.level // ""),
		.workspace.current_dir,
		(.context_window.used_percentage // 0 | floor),
		(.cost.total_api_duration_ms // 0)
	] | map(tostring) | join("\u001f")') || {
		printf 'statusline: stdin parse failed\n' >&2
		return 1
	}
	IFS=$'\037' read -r model effort dir pct api_ms <<<"$jq_out"
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

	# Rate limits — absent for non-subscribers or when both sources came up empty
	local limits=""
	[[ -n "$five_h" ]] && limits+=$(fmt_limit_segment "5h" "$five_h" "$five_h_reset" "$FIVE_HOUR_SECONDS" fmt_reset_countdown "$now")
	[[ -n "$week" ]] && limits+=$(fmt_limit_segment "7d" "$week" "$week_reset" "$SEVEN_DAY_SECONDS" fmt_reset_absolute "$now")

	printf '%s\n' "${dir##*/} │ ${model} $(fmt_context_bar "$pct")${limits}"
}

# Guarded so tests can source the formatters without rendering a status line.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
