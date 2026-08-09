#!/usr/bin/env bash
set -euo pipefail

readonly RESET=$'\033[0m'
readonly GAUGE_SLOTS=5
readonly QUARTERS_PER_SLOT=4
readonly FIVE_HOUR_SECONDS=$((5 * 3600))
readonly SEVEN_DAY_SECONDS=$((7 * 24 * 3600))
# format_limit_segment/format_pace thresholds, in percentage points.
readonly COUNTDOWN_MIN_PCT=75
readonly PACE_MIN_PCT=50
readonly PACE_HOT_DELTA=15
readonly PACE_OVER_DELTA=5
readonly PACE_UNDER_DELTA=-5
# The OAuth usage endpoint answers out of the same strict rate budget as Claude
# Code's own /usage polling, so spending it here makes /usage fail with a 429.
# Poll it rarely, and back off further once it starts refusing.
readonly USAGE_POLL_SECONDS=300
readonly USAGE_BACKOFF_SECONDS=900
# file_mtime's exit status for a stat that cannot answer at all, kept distinct from a
# plain non-zero so callers can tell a broken tool from a file that is simply not there.
readonly STAT_UNUSABLE_STATUS=3

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

# The mtime of path $1 in epoch seconds on stdout. Exit 1 when the path is absent, which
# is an ordinary condition here — an unclaimed lock, a first render with no marker yet —
# and callers absorb it with a fallback. Exit STAT_UNUSABLE_STATUS when the path is there
# and stat still cannot answer: that is a stat without -f (GNU coreutils), a broken
# environment rather than a missing file, and callers report it instead.
file_mtime() {
	stat -f %m "$1" 2>/dev/null && return 0
	[[ -e "$1" ]] || return 1
	return "$STAT_UNUSABLE_STATUS"
}

# The path of the claim held inside the lock directory $1, or nothing when the lock
# carries none — a render killed between creating the lock and claiming it, or between
# giving the claim back and removing the lock, leaves it that way.
usage_lock_holder() {
	local entry
	for entry in "$1"/owner.*; do
		if [[ -d "$entry" ]]; then
			printf '%s' "$entry"
			return 0
		fi
	done
}

# Whether path $1's mtime is at least $2 seconds behind $3 (now). Also non-zero when the
# path is missing, so a caller racing its disappearance treats that the same as "too
# fresh to reclaim." An age this cannot read is answered the same conservative way: an
# unusable stat reaches the line from fetch_usage_fallback's marker read, which every
# render performs before any lock work, so evicting a lock on an unknown age would buy
# nothing here.
usage_lock_stale() {
	local path="$1" throttle="$2" now="$3" age
	age=$(file_mtime "$path") || return 1
	((now - age >= throttle))
}

# Empties the lock directory $1 of an abandoned claim, so the caller can claim it
# instead. Non-zero means the lock is not the caller's to take: it is held by a live
# render, or another render reclaimed it first. On success the lock exists and is empty.
#
# The age test is a decision, not a claim, and two overlapping renders can reach the
# same one. What makes the reclaim single-winner is that it names the exact claim it
# judged stale: rmdir on that one path is atomic, and it fails once the stale render
# has released and another has moved in — so a live render's fresh claim is never
# evicted, and the render that lost backs off instead of fetching alongside it.
usage_lock_reclaim() {
	local lock="$1" throttle="$2" now="$3" holder
	holder=$(usage_lock_holder "$lock")
	if [[ -z "$holder" ]]; then
		usage_lock_stale "$lock" "$throttle" "$now" || return 1
		# rmdir takes the lock away only while it is still empty, so a render that
		# claimed it since the check above keeps its claim and this one backs off.
		rmdir "$lock" 2>/dev/null || return 1
		mkdir "$lock" 2>/dev/null || return 1
		return 0
	fi
	# The claim's own mtime is the moment it was made and nothing moves it, unlike the
	# lock directory's, which every claim taken or given back bumps to now.
	usage_lock_stale "$holder" "$throttle" "$now" || return 1
	rmdir "$holder" 2>/dev/null
}

# Takes the lock $1 for the claim named $2. Non-zero means a live render holds it,
# which is the caller's signal to skip the fetch entirely.
#
# The throttle check in fetch_usage_fallback is a plain read, not a claim: two renders
# that overlap can both see the poll window open. mkdir is atomic on POSIX, so only one
# of them creates the lock directory; the other falls through without fetching, leaving
# the winner as the sole writer for the window. A render killed by SIGTERM/SIGKILL never
# reaches its release, so the lock outlives it — hence the reclaim, which fires once the
# claim is older than the throttle window itself. By then no legitimate holder can still
# be running, since a live fetch finishes well inside that window.
usage_lock_acquire() {
	local lock="$1" owner="$2" throttle="$3" now="$4"
	mkdir "$lock" 2>/dev/null && mkdir "$lock/$owner" && return 0
	usage_lock_reclaim "$lock" "$throttle" "$now" || return 1
	mkdir "$lock/$owner" 2>/dev/null
}

# Gives the lock $1 back, but only while it is still this render's to give. A render
# stalled long enough to have its claim reclaimed owns nothing: rmdir on its own claim
# fails, and it leaves the lock — now somebody else's — untouched. The lock directory
# itself only comes away while no other render has claimed it in the meantime.
usage_lock_release() {
	local lock="$1" owner="$2"
	rmdir "$lock/$owner" 2>/dev/null || return 0
	rmdir "$lock" 2>/dev/null || return 0
}

# Fetches a payload for account $1 and publishes it into cache $2, recording the
# attempt's verdict in marker $3.
#
# Runs between the lock's acquisition and its release, so it reports failure by
# returning rather than by exiting: every write is checked explicitly, since errexit is
# suppressed inside a function whose status the caller tests. A write that ended the
# render here instead would leave the lock standing until the staleness window expires,
# blocking every render in between.
publish_usage_payload() {
	local suffix="$1" cache="$2" marker="$3" payload
	# A predictable staging path — rather than a per-render mktemp name — means at most
	# one orphan can ever accumulate if the process is killed before the mv below runs
	# (mktemp names would each be an orphan of their own). The lock already guarantees
	# no other render is writing this same path concurrently.
	local staging="${cache}.staging"
	# Claim the window pessimistically: a fetch that dies mid-flight must not invite the
	# next render, a second later, to try again.
	printf 'failed' >"$marker" || return 1
	payload=$(fetch_usage_payload "$suffix") || payload=""
	[[ -n "$payload" ]] || return 1
	printf '%s' "$payload" >"$staging" || return 1
	mv "$staging" "$cache" || return 1
	# The ok verdict is earned only when the payload actually reached the cache — a
	# failed write must leave the failed claim (and its longer backoff) in place rather
	# than republish stale data as fresh.
	printf 'ok' >"$marker" || return 1
}

# Reclaims a stale lock if one is present, then fetches a fresh payload and
# atomically publishes it into the cache. Called from fetch_usage_fallback only
# once its throttle check has decided the poll window is open.
#
# The lock is released with an explicit call at the end of this function rather than a
# RETURN trap: a trap set with `trap ... RETURN` fires again when the *caller*
# (fetch_usage_fallback) returns, at which point this function's local $lock is out of
# scope — fatal under `set -u`. Do not reintroduce a RETURN trap here.
refresh_usage_cache() {
	local suffix="$1" cache="$2" marker="$3" throttle="$4" now="$5"
	local lock="${cache}.lock"
	# BASHPID separates renders that share a $$ (subshells of one parent); $RANDOM keeps
	# a recycled pid from producing the name a killed render's claim already carries.
	local owner="owner.${BASHPID}.${RANDOM}"
	usage_lock_acquire "$lock" "$owner" "$throttle" "$now" || return 0
	# The failed verdict in the marker is the record of a fetch that did not land; the
	# lock has to come back either way.
	publish_usage_payload "$suffix" "$cache" "$marker" || true
	usage_lock_release "$lock" "$owner"
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
	local suffix="default" cache marker last_attempt verdict throttle
	[[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && suffix=$(printf '%s' "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)
	cache="${TMPDIR:-/tmp}/claude-statusline-usage-${suffix}.json"
	marker="${cache}.attempt"
	last_attempt=$(file_mtime "$marker") || {
		local mtime_status=$?
		((mtime_status == STAT_UNUSABLE_STATUS)) && return "$mtime_status"
		last_attempt=0
	}
	{ verdict=$(<"$marker"); } 2>/dev/null || verdict=""
	throttle=$USAGE_POLL_SECONDS
	[[ "$verdict" == "failed" ]] && throttle=$USAGE_BACKOFF_SECONDS
	if ((now - last_attempt >= throttle)); then
		refresh_usage_cache "$suffix" "$cache" "$marker" "$throttle" "$now"
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
	used_int=$(LC_ALL=C printf '%.0f' "$used")
	color=$(usage_color "$used_int")
	pace=$(format_pace "$used_int" "$reset_epoch" "$window_sec" "$now")
	reset=$(format_countdown "$reset_epoch" "$now")
	# Below 75% the window has room to spare, so when it resets is noise: the countdown
	# earns its place on the line only once usage is close enough to matter.
	((used_int >= COUNTDOWN_MIN_PCT)) && [[ -n "$reset" ]] && detail=" · ${reset}"
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
	((used_int < PACE_MIN_PCT)) && return
	remaining=$((reset_epoch - now))
	((remaining <= 0 || remaining > window_sec)) && return
	expected=$(((window_sec - remaining) * 100 / window_sec))
	delta=$((used_int - expected))
	if ((delta >= PACE_HOT_DELTA)); then
		printf '↑↑'
	elif ((delta >= PACE_OVER_DELTA)); then
		printf '↑'
	elif ((delta <= PACE_UNDER_DELTA)); then
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
#
# A session whose context window runs past 200k tokens draws the same gauge from the
# diamond family (U+25C6, U+25C8, U+25C7) instead, so the two window sizes are never
# mistaken for each other at a glance. Only the glyphs swap — the slot arithmetic,
# the quarter marks, and the coloring below are shared.
format_context_bar() {
	local pct="$1" exceeds="${2:-}"
	local color slot sep="" out=""
	local full="●" half="◎" empty="○"
	if [[ "$exceeds" == "true" ]]; then
		full="◆" half="◈" empty="◇"
	fi
	color=$(usage_color "$pct")
	# Quarter-slots filled across the gauge, capped so a used_percentage that
	# overflows past 100 still saturates the bar rather than overrunning it.
	local quarters=$((pct * GAUGE_SLOTS * QUARTERS_PER_SLOT / 100))
	local max_quarters=$((QUARTERS_PER_SLOT * GAUGE_SLOTS))
	((quarters > max_quarters)) && quarters=$max_quarters
	for ((slot = 0; slot < GAUGE_SLOTS; slot++)); do
		local q=$((quarters - slot * QUARTERS_PER_SLOT))
		if ((q >= 3)); then
			out+="${sep}${color}${full}${RESET}"
		elif ((q >= 1)); then
			out+="${sep}${color}${half}${RESET}"
		else
			out+="${sep}${empty}"
		fi
		sep=" "
	done
	printf '%s' "$out"
}

# The branch checked out at $1, empty when there is no name to give: the path is outside a
# repository, HEAD is detached, or git is not installed. All three are ordinary here, so they
# stay silent and let the segment fall back to the bare basename.
git_branch() {
	local dir="$1"
	[[ -n "$dir" ]] || return 0
	git -C "$dir" branch --show-current 2>/dev/null || true
}

# The leading segment ("proj ⎇ dash"): the working directory's basename, followed behind
# ⎇ (U+2387) by where the session sits in git. A worktree's name takes that slot over its
# branch's — the two are nearly always the same word, so showing both would only repeat it.
# Everything stays in the terminal's default foreground — the glyph is a label for the name
# beside it, not a status worth coloring.
format_dir() {
	local dir="$1" worktree="$2" branch="$3"
	local out="${dir##*/}" name="${worktree:-$branch}"
	[[ -n "$name" ]] && out+=" ⎇ ${name}"
	printf '%s' "$out"
}

# Fail fast with the culprit named instead of letting a missing tool surface as a
# misleading downstream error: absent jq reads as a stdin parse failure. The name reaches
# the user through render_failure like every other report, because a message on stderr
# alone leaves the line blank — the host renders what the command printed on stdout.
#
# stat is deliberately not in this list: what breaks about it is not its absence but its
# options, which `command -v` cannot vet. A probe here would fork a process on every
# render to pre-empt a failure file_mtime already detects at the point of use.
check_deps() {
	local tool
	for tool in jq curl security shasum date; do
		command -v "$tool" >/dev/null || {
			render_failure "missing required tool: $tool"
			return 1
		}
	done
}

# Extracts a batch of jq expressions from $1 as a single line, joined on
# \u001f (unit separator) rather than @tsv: read collapses runs of tabs — they
# are IFS whitespace — so an empty field (e.g. a missing effort level) would
# shift every field after it. Batching into one jq pass matters because the
# script forks on every statusline render (~300ms during activity), and
# per-field jq calls would multiply into real latency.
#
# $2 is a jq array literal; every element needs its own `// ""` in the
# caller, since tostring renders an absent value as the literal string
# "null" rather than an empty field.
jq_fields() {
	local json="$1" expr="$2"
	printf '%s' "$json" | jq -r "$expr"' | map(tostring) | join("\u001f")'
}

# Reports $1 on the status line itself, not only on stderr. Every field the line draws
# comes out of one jq pass, so a pass that fails leaves nothing to draw — and a
# statusline that prints nothing is indistinguishable from a working render with nothing
# to say. Callers pair this with a zero exit: Claude Code renders what the command
# printed, and a non-zero status puts the line back to blank.
render_failure() {
	printf 'statusline: %s\n' "$1" >&2
	printf 'statusline: %s\n' "$1"
}

main() {
	local input model effort dir worktree branch pct exceeds api_ms rate_limits_json now
	# check_deps has already named the culprit on stdout; the zero exit is what makes the
	# host render that line instead of discarding it.
	check_deps || return 0
	input=$(cat)
	now=$(date +%s)

	local jq_out
	jq_out=$(jq_fields "$input" '[
		(.model.display_name // ""),
		(.effort.level // ""),
		(.workspace.current_dir // ""),
		(.workspace.git_worktree // ""),
		(.context_window.used_percentage // 0 | floor),
		(.exceeds_200k_tokens // false),
		(.cost.total_api_duration_ms // 0)
	]') || {
		render_failure "stdin parse failed"
		return 0
	}
	IFS=$'\037' read -r model effort dir worktree pct exceeds api_ms <<<"$jq_out"
	[[ -n "$effort" ]] && model="$model ($effort)"

	# Asking git costs a fork on every render, so skip it when the worktree name already
	# fills the slot the branch would have taken.
	branch=""
	[[ -n "$worktree" ]] || branch=$(git_branch "$dir")

	# Prefer stdin rate_limits (live per API response, no network cost); fall back
	# to the OAuth endpoint when absent. api_ms is 0 until this session's first API
	# call and stdin rate_limits is carried over from the previous session until
	# then — so a 0 means stale stdin data. The fallback is live server data and
	# needs no such gate.
	rate_limits_json=""
	((api_ms > 0)) && rate_limits_json=$(printf '%s' "$input" | jq -c '.rate_limits // empty') || true
	if [[ -z "$rate_limits_json" ]]; then
		rate_limits_json=$(fetch_usage_fallback "$now") || {
			local fallback_status=$?
			# The fallback's throttle is read off a file's mtime, so a stat that cannot
			# answer would poll the endpoint on every render — the failure it reports is
			# worth the line rather than a degraded render that looks healthy.
			if ((fallback_status == STAT_UNUSABLE_STATUS)); then
				render_failure "unusable required tool: stat"
				return 0
			fi
		}
	fi

	local five_h="" five_h_reset="" week="" week_reset="" limits_out=""
	# Capture jq's output before reading it: a process substitution feeding `read`
	# hides jq's exit status, so a payload that will not parse would blank the
	# segments with no word about why.
	if [[ -n "$rate_limits_json" ]]; then
		limits_out=$(jq_fields "$rate_limits_json" '[
			(.five_hour.used_percentage // ""),
			(.five_hour.resets_at // ""),
			(.seven_day.used_percentage // ""),
			(.seven_day.resets_at // "")
		]') || {
			printf 'statusline: rate-limit parse failed\n' >&2
			limits_out=""
		}
		IFS=$'\037' read -r five_h five_h_reset week week_reset <<<"$limits_out"
	fi

	# Rate limits — absent for non-subscribers or when both sources came up empty
	local limits=""
	[[ -n "$five_h" ]] && limits+=$(format_limit_segment "5h" "$five_h" "$five_h_reset" "$FIVE_HOUR_SECONDS" "$now")
	[[ -n "$week" ]] && limits+=$(format_limit_segment "7d" "$week" "$week_reset" "$SEVEN_DAY_SECONDS" "$now")

	printf '%s │ %s %s%s\n' "$(format_dir "$dir" "$worktree" "$branch")" "$model" "$(format_context_bar "$pct" "$exceeds")" "$limits"
}

# Guarded so tests can source the formatters without rendering a status line.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
