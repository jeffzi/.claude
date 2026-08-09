#!/usr/bin/env bash
set -euo pipefail

RESET=$'\033[0m'
GAUGE_SLOTS=5
FIVE_HOUR_SECONDS=$((5 * 3600))
SEVEN_DAY_SECONDS=$((7 * 24 * 3600))
# The OAuth usage endpoint answers out of the same strict rate budget as Claude
# Code's own /usage polling, so spending it here makes /usage fail with a 429.
# Poll it rarely, and back off further once it starts refusing.
USAGE_POLL_SECONDS=300
USAGE_BACKOFF_SECONDS=900

# Reads the OAuth usage endpoint for the account keyed by $1 and emits the stdin
# .rate_limits shape on stdout (resets_at as epoch seconds).
#
# Emits nothing when the account has no token, the request fails, or the body
# carries no .five_hour.utilization — the last is what the endpoint answers
# with when it rate-limits, and mapping it would produce a well-formed payload
# with null percentages in it. That last case exits zero (jq's `empty`), so
# callers must check for empty output rather than a non-zero exit.
fetch_usage_payload() {
	local suffix="$1" service="Claude Code-credentials" token response
	[[ "$suffix" != "default" ]] && service="${service}-${suffix}"
	token=$(security find-generic-password -s "$service" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty') || return
	[[ -n "$token" ]] || return 1
	response=$(curl -s --max-time 2 \
		-H "Authorization: Bearer $token" \
		-H "anthropic-beta: oauth-2025-04-20" \
		https://api.anthropic.com/api/oauth/usage 2>/dev/null) || return
	printf '%s' "$response" | jq -c '
		def epoch: if . == null then null else (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) end;
		if .five_hour.utilization == null then empty else {
			five_hour: {used_percentage: .five_hour.utilization, resets_at: (.five_hour.resets_at | epoch)},
			seven_day: {used_percentage: .seven_day.utilization, resets_at: (.seven_day.resets_at | epoch)}
		} end' 2>/dev/null
}

# Team-plan sessions never receive the unified rate-limit headers, so stdin lacks
# .rate_limits entirely even though the data exists server-side
# (anthropics/claude-code#63659). Fetch it from the OAuth usage endpoint instead,
# cached per account in a file keyed on CLAUDE_CONFIG_DIR — the same key Claude
# Code uses to suffix its Keychain entry.
#
# The cache holds good payloads only, and is the sole data source between
# attempts: a failed fetch must serve it unchanged rather than blank the segment.
# The attempt clock therefore lives in a sibling marker file — its mtime dates the
# last attempt and its contents record the verdict — so claiming the next window
# never touches the data.
fetch_usage_fallback() {
	local now="$1"
	local suffix="default" cache marker last_attempt verdict throttle payload
	[[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && suffix=$(printf '%s' "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)
	cache="${TMPDIR:-/tmp}/claude-statusline-usage-${suffix}.json"
	marker="${cache}.attempt"
	last_attempt=$(stat -f %m "$marker" 2>/dev/null) || last_attempt=0
	{ verdict=$(<"$marker"); } 2>/dev/null || verdict=""
	throttle=$USAGE_POLL_SECONDS
	[[ "$verdict" == "failed" ]] && throttle=$USAGE_BACKOFF_SECONDS
	if ((now - last_attempt >= throttle)); then
		# The throttle check above is a plain read, not a claim: two renders that
		# overlap can both see the window open. mkdir is atomic on POSIX, so only
		# one of them can create this directory — the other falls through without
		# fetching, leaving the winner as the sole writer for the window.
		local lock="${cache}.lock"
		if [[ -d "$lock" ]]; then
			# A render killed by SIGTERM/SIGKILL never fires the RETURN trap below,
			# so the lock outlives the process that made it. Reclaim it once it's
			# older than the throttle window itself — by then no legitimate holder
			# could still be running one, since a live fetch finishes (or is
			# reclaimed) well inside that window.
			local lock_age
			lock_age=$(stat -f %m "$lock" 2>/dev/null) || lock_age=0
			((now - lock_age >= throttle)) && rmdir "$lock" 2>/dev/null
		fi
		if mkdir "$lock" 2>/dev/null; then
			trap 'rmdir "$lock" 2>/dev/null' RETURN
			# Claim the window pessimistically: a fetch that dies mid-flight must not
			# invite the next render, a second later, to try again.
			printf 'failed' >"$marker"
			# A predictable staging path — rather than a per-render mktemp name —
			# means at most one orphan can ever accumulate if the process is killed
			# before the mv below runs (mktemp names would each be an orphan of
			# their own, since a RETURN trap never fires on SIGTERM/SIGKILL). The
			# mkdir lock above already guarantees no other render is writing this
			# same path concurrently.
			local staging="${cache}.staging"
			payload=$(fetch_usage_payload "$suffix") || payload=""
			# The ok verdict is earned only when the payload actually reached the
			# cache — a failed write must leave the failed claim (and its longer
			# backoff) in place rather than republish stale data as fresh.
			if [[ -n "$payload" ]] && printf '%s' "$payload" >"$staging" && mv "$staging" "$cache"; then
				printf 'ok' >"$marker"
			fi
		fi
	fi
	[[ -f "$cache" ]] || return 1
	cat "$cache"
}

# Time left before a window resets, for both the 5h and the 7d one: "4d13h" once a day
# is on the clock, "2h10m" below that, "45m" below an hour. Zero units are dropped ("5d",
# "2h"), and minutes stop carrying information beside days, so they are left out there.
#
# A reset that has already passed has nothing to count down and renders empty, which is
# the caller's signal to leave the detail off the segment entirely.
format_countdown() {
	local reset_epoch="$1" now="$2"
	[[ -z "$reset_epoch" ]] && return
	local secs d h m
	secs=$((reset_epoch - now))
	((secs <= 0)) && return
	d=$((secs / 86400))
	h=$(((secs % 86400) / 3600))
	m=$(((secs % 3600) / 60))
	local out
	if ((d > 0)); then
		out="${d}d"
		((h > 0)) && out+="${h}h"
	elif ((h > 0)); then
		out="${h}h"
		((m > 0)) && out+="${m}m"
	else
		out="${m}m"
	fi
	printf '%s' "$out"
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

# One rendered segment (" │ 5h 61%↑ · 2h10m"). The label, the space, and the percentage
# form a single span in the usage gradient; the countdown that follows the middle dot
# stays in the terminal's default foreground so it never competes for attention.
format_limit_segment() {
	local label="$1" used="$2" reset_epoch="$3" window_sec="$4" now="$5"
	local used_int color pace reset detail=""
	used_int=$(printf '%.0f' "$used")
	color=$(usage_color "$used_int")
	pace=$(format_pace "$used_int" "$reset_epoch" "$window_sec" "$now")
	reset=$(format_countdown "$reset_epoch" "$now")
	# Below 75% the window has room to spare, so when it resets is noise: the countdown
	# earns its place on the line only once usage is close enough to matter.
	((used_int >= 75)) && [[ -n "$reset" ]] && detail=" · ${reset}"
	# Over-pace is the warning, so its arrow joins the gradient span and reddens with the
	# rest of it; the under-pace ↓ is good news and stays in the default foreground.
	local span="${label} ${used_int}%" uncolored=""
	if [[ "$pace" == "↓" ]]; then
		uncolored="$pace"
	else
		span+="$pace"
	fi
	printf ' │ %s%s%s%s%s' "$color" "$span" "$RESET" "$uncolored" "$detail"
}

# Even-pace delta: actual usage vs. linear spend rate across the window. Only shown above
# 50% — below that, pace is noise regardless of delta. The glyph carries no color of its
# own; format_limit_segment decides what the arrow wears.
format_pace() {
	local used_int="$1" reset_epoch="$2" window_sec="$3" now="$4"
	[[ -z "$reset_epoch" ]] && return
	local remaining expected delta
	((used_int < 50)) && return
	remaining=$((reset_epoch - now))
	((remaining <= 0 || remaining > window_sec)) && return
	expected=$(((window_sec - remaining) * 100 / window_sec))
	delta=$((used_int - expected))
	if ((delta >= 15)); then
		printf '↑↑'
	elif ((delta >= 5)); then
		printf '↑'
	elif ((delta <= -5)); then
		printf '↓'
	fi
}

# Context gauge ("● ◎ ○ ○ ○"). Each of GAUGE_SLOTS slots is ● full, ◎ half, or ○ empty;
# a slot's fractional fill snaps to the nearest of the three at the quarter marks. The
# gauge carries no number of its own — the percentages belong to the limit segments, and
# repeating one here would only crowd the line.
#
# The three glyphs are concentric circles (U+25CF, U+25CE, U+25CB), all of
# unambiguous East Asian width, so each occupies exactly one cell. Do not reach for
# the half-circle family (◐ ◑ ◒ ◓) for the half state: those are ambiguous-width and
# terminals render them double-width, dwarfing ● and ○.
#
# Full slots and the half slot wear the usage gradient. Only empty slots stay uncolored,
# matching the default foreground of the model name beside them.
format_context_bar() {
	local pct="$1"
	local color slot sep="" out=""
	color=$(usage_color "$pct")
	# Quarter-slots filled across the gauge, capped so a used_percentage that
	# overflows past 100 still saturates the bar rather than overrunning it.
	local quarters=$((pct * GAUGE_SLOTS * 4 / 100))
	local max_quarters=$((4 * GAUGE_SLOTS))
	((quarters > max_quarters)) && quarters=$max_quarters
	for ((slot = 0; slot < GAUGE_SLOTS; slot++)); do
		local q=$((quarters - slot * 4))
		if ((q >= 3)); then
			out+="${sep}${color}●${RESET}"
		elif ((q >= 1)); then
			out+="${sep}${color}◎${RESET}"
		else
			out+="${sep}○"
		fi
		sep=" "
	done
	printf '%s' "$out"
}

# Fail fast with the culprit named instead of letting a missing tool surface
# as a misleading downstream error: absent jq reads as a stdin parse failure,
# and a stat without -f (GNU coreutils) would defeat the fallback throttle and
# poll the usage endpoint on every render. stat gets a functional probe because
# `command -v` cannot tell the BSD and GNU variants apart.
check_deps() {
	local tool
	for tool in jq curl security shasum date; do
		command -v "$tool" >/dev/null || {
			printf 'statusline: %s is required\n' "$tool" >&2
			return 1
		}
	done
	stat -f %m . >/dev/null 2>&1 || {
		printf 'statusline: BSD stat (-f) is required\n' >&2
		return 1
	}
}

main() {
	local input model effort dir pct api_ms rate_limits_json now
	check_deps || return 1
	input=$(cat)
	now=$(date +%s)

	# Batched into one jq pass — the script forks on every statusline render
	# (~300ms during activity), so per-field jq calls multiply into real latency.
	# \u001f (unit separator) not @tsv: read collapses runs of tabs — they are IFS
	# whitespace — so empty fields like a missing effort level would shift every
	# field after them. Every field needs its own `// ""`: tostring renders an
	# absent one as the literal string "null".
	local jq_out
	jq_out=$(printf '%s' "$input" | jq -r '[
		(.model.display_name // ""),
		(.effort.level // ""),
		(.workspace.current_dir // ""),
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

	local five_h="" five_h_reset="" week="" week_reset="" limits_out=""
	# Capture jq's output before reading it: a process substitution feeding `read`
	# hides jq's exit status, so a payload that will not parse would blank the
	# segments with no word about why.
	if [[ -n "$rate_limits_json" ]]; then
		limits_out=$(printf '%s' "$rate_limits_json" | jq -r '[
			(.five_hour.used_percentage // ""),
			(.five_hour.resets_at // ""),
			(.seven_day.used_percentage // ""),
			(.seven_day.resets_at // "")
		] | map(tostring) | join("\u001f")') || {
			printf 'statusline: rate-limit parse failed\n' >&2
			limits_out=""
		}
		IFS=$'\037' read -r five_h five_h_reset week week_reset <<<"$limits_out"
	fi

	# Rate limits — absent for non-subscribers or when both sources came up empty
	local limits=""
	[[ -n "$five_h" ]] && limits+=$(format_limit_segment "5h" "$five_h" "$five_h_reset" "$FIVE_HOUR_SECONDS" "$now")
	[[ -n "$week" ]] && limits+=$(format_limit_segment "7d" "$week" "$week_reset" "$SEVEN_DAY_SECONDS" "$now")

	printf '%s\n' "${dir##*/} │ ${model} $(format_context_bar "$pct")${limits}"
}

# Guarded so tests can source the formatters without rendering a status line.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
