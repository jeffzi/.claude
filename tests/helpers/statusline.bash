#!/usr/bin/env bash
# Shared helpers and domain scaffolding for tests/test_statusline.bats.

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$TEST_DIR/../scripts/statusline.sh"

# shellcheck source=../../scripts/statusline.sh disable=SC1091
# </dev/null keeps main (which reads stdin) from consuming test input while the script loads.
. "$SCRIPT" </dev/null

EMPTY="○"
HALF="◎"
FILLED="●"

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------
#
# Each assert_* prints a diagnostic on failure and returns 1; Bats catches the
# non-zero exit. No report() function, no PASS/FAIL counters.

strip_ansi() {
	sed $'s/\033\\[[0-9;]*m//g'
}

assert_glyphs() {
	local pct="$1" expected="$2" actual
	actual=$(format_context_bar "$pct" | strip_ansi)
	if [[ "$actual" != "$expected" ]]; then
		printf 'expected: %s\n  actual: %s\n' "$expected" "$actual" >&2
		return 1
	fi
}

assert_bar() {
	local pct="$1" pattern="$2" color expected="" sep="" i actual
	local filled="$FILLED" half="$HALF" empty="$EMPTY"
	color=$(usage_color "$pct")
	for ((i = 0; i < ${#pattern}; i++)); do
		case "${pattern:i:1}" in
		F) expected+="${sep}${color}${filled}${RESET}" ;;
		H) expected+="${sep}${color}${half}${RESET}" ;;
		E) expected+="${sep}${empty}" ;;
		*)
			printf 'invalid pattern char: %s\n' "${pattern:i:1}" >&2
			return 1
			;;
		esac
		sep=" "
	done
	actual=$(format_context_bar "$pct")
	if [[ "$actual" != "$expected" ]]; then
		printf 'expected: %q\n  actual: %q\n' "$expected" "$actual" >&2
		return 1
	fi
}

assert_exact() {
	local actual="$1" expected="$2"
	if [[ "$actual" != "$expected" ]]; then
		printf 'expected: %q\n  actual: %q\n' "$expected" "$actual" >&2
		return 1
	fi
}

assert_contains() {
	local haystack="$1" needle="$2"
	if [[ "$haystack" != *"$needle"* ]]; then
		printf 'expected to contain: %q\n  actual: %q\n' "$needle" "$haystack" >&2
		return 1
	fi
}

assert_not_contains() {
	local haystack="$1" needle="$2"
	if [[ "$haystack" == *"$needle"* ]]; then
		printf 'expected NOT to contain: %q\n  actual: %q\n' "$needle" "$haystack" >&2
		return 1
	fi
}

assert_rgb() {
	local pct="$1" want_r="$2" want_g="$3" want_b="$4" r g b
	read -r r g b <<<"$(usage_rgb "$pct")"
	if ! rgb_within_tolerance "$r" "$g" "$b" "$want_r" "$want_g" "$want_b" 1; then
		printf 'expected ~%s %s %s, got %s %s %s\n' "$want_r" "$want_g" "$want_b" "$r" "$g" "$b" >&2
		return 1
	fi
}

assert_matches_hsl_ref() {
	local pct="$1" rr rg rb
	read -r rr rg rb <<<"$(ref_rgb "$pct")"
	assert_rgb "$pct" "$rr" "$rg" "$rb"
}

assert_red_direction() {
	local lo="$1" hi="$2" dir="$3" r_lo r_hi _
	read -r r_lo _ <<<"$(usage_rgb "$lo")"
	read -r r_hi _ <<<"$(usage_rgb "$hi")"
	if [[ ! "$r_lo" =~ ^[0-9]+$ || ! "$r_hi" =~ ^[0-9]+$ ]]; then
		printf 'non-numeric R values: R(%s) = %s, R(%s) = %s\n' "$lo" "$r_lo" "$hi" "$r_hi" >&2
		return 1
	fi
	case "$dir" in
	rises) ((r_hi > r_lo)) && return 0 ;;
	falls) ((r_hi < r_lo)) && return 0 ;;
	esac
	printf 'R(%s) = %s, R(%s) = %s, expected it to have %s\n' "$lo" "$r_lo" "$hi" "$r_hi" "$dir" >&2
	return 1
}

assert_continuous_across() {
	local lo="$1" hi="$2" limit="$3"
	local r1 g1 b1 r2 g2 b2
	read -r r1 g1 b1 <<<"$(usage_rgb "$lo")"
	read -r r2 g2 b2 <<<"$(usage_rgb "$hi")"
	if ! rgb_within_tolerance "$r1" "$g1" "$b1" "$r2" "$g2" "$b2" "$limit"; then
		printf '%s%% = %s %s %s, %s%% = %s %s %s\n' "$lo" "$r1" "$g1" "$b1" "$hi" "$r2" "$g2" "$b2" >&2
		return 1
	fi
}

assert_pace_glyph() {
	local used="$1" expected="$2" actual
	actual=$(format_pace "$used" "$PACE_RESET" "$PACE_WINDOW" "$NOW" | strip_ansi)
	assert_exact "$actual" "$expected"
}

assert_segment_plain() {
	local label="$1" used="$2" reset_ts="$3" window="$4" expected="$5" actual
	actual=$(format_limit_segment "$label" "$used" "$reset_ts" "$window" "$NOW" | strip_ansi)
	assert_exact "$actual" "$expected"
}

assert_arrow_color() {
	local used="$1" arrow="$2"
	local color out head got
	color=$(usage_color "$used")
	out=$(format_limit_segment "5h" "$used" "$PACE_RESET" "$PACE_WINDOW" "$NOW")
	head=${out%%"$arrow"*}
	got=$(last_escape "$head")
	if [[ "$out" != *"$arrow"* || "$got" != "$color" ]]; then
		printf 'escape in force at the arrow: %q, expected %q\n  actual: %q\n' "$got" "$color" "$out" >&2
		return 1
	fi
}

assert_countdown() {
	local seconds="$1" expected="$2" actual
	actual=$(format_countdown "$((NOW + seconds))" "$NOW")
	assert_exact "$actual" "$expected"
}

assert_dir() {
	local dir="$1" worktree="$2" branch="$3" expected="$4" actual
	actual=$(format_dir "$dir" "$worktree" "$branch")
	assert_exact "$actual" "$expected"
}

assert_leading_segment() {
	local plain="$1" expected="$2"
	assert_exact "${plain%% │ *}" "$expected"
}

# Pins the whole composed line around a given model segment, so a change to the
# segment cannot quietly disturb the gauge, the usage segments, or the dir name.
# The 5h countdown's minutes are matched rather than pinned: setup_file captures
# MAIN_NOW while main() reads its own clock at render time, so the digits roll
# whenever execution lags setup by more than a few seconds.
assert_whole_line() {
	local plain="$1" model="$2" normalized
	normalized=$(printf '%s' "$plain" | sed -E 's/· 4h[0-9]+m/· 4h#m/')
	assert_exact "$normalized" "statusline-proj │ ${model} ● ● ◎ ○ ○ │ 5h 78%↑↑ · 4h#m │ 7d 7%"
}

# Every degraded transcript lookup must leave the model segment exactly as it
# renders with no transcript at all: unannotated, exit 0, no literal "null" from
# a missing stdin field, and no failure line on either stream — an annotation
# that cannot be computed is not a render failure.
assert_unannotated_render() {
	local case_name="$1" stdin="$2" status=0 out plain err
	out=$(main_render "$case_name" "$stdin" "$MAIN_PAYLOAD") || status=$?
	plain=$(printf '%s' "$out" | strip_ansi)
	assert_contains "$plain" "Opus 4.6 (high)" || return 1
	assert_not_contains "$plain" "→" || return 1
	assert_not_contains "$plain" "null" || return 1
	assert_not_contains "$plain" "statusline:" || return 1
	if ((status != 0)); then
		printf 'expected exit 0, got %s\n' "$status" >&2
		return 1
	fi
	err=$(<"$MAIN_CASES/$case_name/stderr")
	assert_not_contains "$err" "statusline:"
}

# Degraded mode must both fall back gracefully (exit 0) and print the correct
# fallback content; either check alone would pass a render that is broken in the other way.
assert_degraded_render() {
	local expected="$1" status=0 out
	shift
	out=$("$@") || status=$?
	local plain
	plain=$(printf '%s' "$out" | strip_ansi)
	if [[ "$plain" != "$expected" ]]; then
		printf 'expected line: %q\n  actual: %q\n' "$expected" "$plain" >&2
		return 1
	fi
	if [[ "$status" -ne 0 ]]; then
		printf 'expected exit 0, got %s\n' "$status" >&2
		return 1
	fi
}

assert_reset_uncolored() {
	local label="$1" pct="$2" reset_ts="$3" window="$4"
	local out tail
	out=$(format_limit_segment "$label" "$pct" "$reset_ts" "$window" "$NOW")
	tail=" · ${out##* · }"
	if [[ "$out" != *" · "* || "$tail" == *$'\033'* ]]; then
		printf 'reset text carries an escape: %q\n' "$tail" >&2
		return 1
	fi
}

assert_attempts() {
	local case_name="$1" want="$2" got
	got=$(awk 'END {print NR}' <"$FALLBACK_ROOT/$case_name/attempts")
	if [[ "$got" != "$want" ]]; then
		printf 'expected %s endpoint attempt(s), got %s\n' "$want" "$got" >&2
		return 1
	fi
}

assert_fallback_json() {
	local payload="$1" filter="$2" want="$3" got
	got=$(printf '%s' "$payload" | jq -r "$filter" 2>/dev/null) || got="<not JSON>"
	if [[ "$got" != "$want" ]]; then
		printf 'expected %s = %q, got %q\n  payload: %q\n' "$filter" "$want" "$got" "$payload" >&2
		return 1
	fi
}

assert_fetched() {
	local id="$1"
	if ! grep -qx "$id" "$RECLAIM_ATTEMPTS"; then
		printf 'no attempt logged for %s\n  attempts: %s\n' "$id" "$(tr '\n' ' ' <"$RECLAIM_ATTEMPTS")" >&2
		return 1
	fi
}

assert_not_fetched() {
	local id="$1"
	if grep -qx "$id" "$RECLAIM_ATTEMPTS"; then
		printf '%s reached the network\n  attempts: %s\n' "$id" "$(tr '\n' ' ' <"$RECLAIM_ATTEMPTS")" >&2
		return 1
	fi
}

assert_no_stray_dirs() {
	local leftovers
	leftovers=$(find "$RECLAIM_TMP" -mindepth 1 -type d)
	if [[ -n "$leftovers" ]]; then
		printf 'directories left behind in TMPDIR:\n  %s\n' "$(printf '%s' "$leftovers" | tr '\n' ' ')" >&2
		return 1
	fi
}

# The family must arrive on stdout alone: an empty expectation means "no annotation",
# which only reads as such if the call also exits 0 and leaves stderr silent. Checking
# stdout alone would pass a lookup that printed nothing but shouted a failure line.
assert_family() {
	local case_name="$1" path="$2" expected="$3" dir out err status=0
	dir="$MAIN_CASES/$case_name"
	mkdir -p "$dir"
	out=$(transcript_model_family "$path" 2>"$dir/family-stderr") || status=$?
	assert_exact "$out" "$expected" || return 1
	if ((status != 0)); then
		printf 'expected exit 0, got %s\n' "$status" >&2
		return 1
	fi
	err=$(<"$dir/family-stderr")
	assert_exact "$err" ""
}

# ---------------------------------------------------------------------------
# Domain helpers
# ---------------------------------------------------------------------------

ref_rgb() {
	awk -v pct="$1" 'BEGIN {
		if (pct <= 50) { t = pct / 50; h = 50; s = t * t * 60; l = 75 - t * 22 }
		else           { t = (pct - 50) / 50; h = 50 - t * 50; s = 60 + t * 40; l = 53 + t * 10 }
		sat = s / 100; light = l / 100
		dev = 2 * light - 1; if (dev < 0) dev = -dev
		chroma = (1 - dev) * sat
		sector = h / 60
		off = sector - 1; if (off < 0) off = -off
		second = chroma * (1 - off)
		base = light - chroma / 2
		printf "%d %d %d", int((chroma + base) * 255 + 0.5), int((second + base) * 255 + 0.5), int(base * 255 + 0.5)
	}'
}

usage_rgb() {
	local body
	body=$(usage_color "$1")
	body=${body#$'\033'"[38;2;"}
	body=${body%m}
	printf '%s' "${body//;/ }"
}

rgb_within_tolerance() {
	local got_r="$1" got_g="$2" got_b="$3" want_r="$4" want_g="$5" want_b="$6" limit="$7"
	within_tolerance "$got_r" "$want_r" "$limit" || return 1
	within_tolerance "$got_g" "$want_g" "$limit" || return 1
	within_tolerance "$got_b" "$want_b" "$limit" || return 1
}

within_tolerance() {
	local got="$1" want="$2" limit="$3"
	[[ "$got" =~ ^[0-9]+$ && "$want" =~ ^[0-9]+$ ]] || return 1
	local diff=$((got > want ? got - want : want - got))
	((diff <= limit))
}

last_escape() {
	printf '%s' "$1" | grep -oE $'\033\\[[0-9;]*m' | tail -1 || true
}

stdin_json() {
	jq -c --argjson extra "$1" '. * $extra' <<<"$STDIN_ENVELOPE"
}

full_stdin_json() {
	jq -c --argjson base "$STDIN_MODEL_WORKSPACE" --argjson extra "$1" '. * $base * $extra' <<<"$STDIN_ENVELOPE"
}

# Stdin for the model-family annotation cases: a per-case transcript plus an
# effort level, which pins where the annotation sits relative to the suffix.
annotation_stdin() {
	local path="$1" extra
	extra=$(jq -cn --arg path "$path" '{transcript_path: $path, effort: {level: "high"}}')
	full_stdin_json "$extra"
}

# Deletes a field from a rendered stdin JSON: `. * $extra` merging can empty a
# field but never make it absent, and absent is its own degraded input.
stdin_without() {
	local filter="$1" stdin="$2"
	printf '%s' "$stdin" | jq -c "del($filter)"
}

main_render() {
	local case_name="$1" stdin_json="$2" stub_payload="${3-}" dir
	dir="$MAIN_CASES/$case_name"
	mkdir -p "$dir"
	(
		# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
		export TMPDIR="$dir" CLAUDE_CONFIG_DIR="$dir"
		if [[ -n "$stub_payload" ]]; then
			# shellcheck disable=SC2329  # stub override for test
			fetch_usage_payload() { printf '%s' "$stub_payload"; }
		else
			# shellcheck disable=SC2329  # stub override for test
			fetch_usage_payload() { return 1; }
		fi
		printf '%s' "$stdin_json" | main
	) 2>"$dir/stderr"
}

main_line() {
	main_render happy-path "$MAIN_STDIN" "$MAIN_PAYLOAD"
}

missing_dep_render() {
	local case_name="$1" exclude=" $2 " tool path dir
	dir="$MAIN_CASES/missing-$case_name"
	mkdir -p "$dir/bin"
	for tool in jq curl shasum sha256sum date stat; do
		if [[ "$exclude" != *" $tool "* ]] && path=$(command -v "$tool"); then
			ln -sf "$path" "$dir/bin/$tool"
		fi
	done
	(
		# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
		export PATH="$dir/bin" TMPDIR="$dir" CLAUDE_CONFIG_DIR="$dir"
		# shellcheck disable=SC2329  # stub override for test
		fetch_usage_payload() { printf '%s' "$MAIN_PAYLOAD"; }
		printf '%s' "$MAIN_STDIN" | main
	) 2>"$dir/stderr"
}

# Writes a fake `stat` executable with the given body to $dir/stat.
make_stat_shim() {
	local dir="$1" body="$2"
	mkdir -p "$dir"
	printf '%s\n' "$body" >"$dir/stat"
	chmod +x "$dir/stat"
}

unusable_stat_render() {
	local case_name="$1" dir
	dir="$MAIN_CASES/$case_name"
	make_stat_shim "$dir/bin" $'#!/usr/bin/env bash\nexit 1'
	(
		# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
		export PATH="$dir/bin:$PATH"
		main_render "$case_name" "$MAIN_STDIN" "$MAIN_PAYLOAD"
	)
}

probe_then_mtime() {
	local stat_dir="$1" target_path="$2"
	(
		# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
		export PATH="$stat_dir:$PATH"
		# Re-probe via the function rather than re-sourcing the script: a second
		# source re-runs the readonly declarations, which is fatal on bash 3.2.
		# shellcheck disable=SC2034 # consumed by file_mtime, defined in the sourced script
		STAT_FMT=$(detect_stat_fmt)
		file_mtime "$target_path"
	)
}

# Scaffolds a fake $dir/bin with a curl shim and (optionally) a security shim, plus an
# attempts file curl appends to. gate_curl "gate" makes the shim honor $STUB_CURL_EXIT;
# "nogate" makes it always succeed. security_mode selects the security shim: "ok" (returns
# a token), "fail" (exits 1), or "absent" (no shim written).
make_fallback_bin() {
	local dir="$1" gate_curl="$2" security_mode="$3"
	mkdir -p "$dir/bin"
	: >"$dir/attempts"
	if [[ "$gate_curl" == gate ]]; then
		cat >"$dir/bin/curl" <<-'SHIM'
			#!/usr/bin/env bash
			printf 'attempt\n' >>"$STUB_ATTEMPTS"
			code=$(cat "$STUB_CURL_EXIT")
			((code == 0)) || exit "$code"
			cat "$STUB_CURL_BODY"
		SHIM
	else
		cat >"$dir/bin/curl" <<-'SHIM'
			#!/usr/bin/env bash
			printf 'attempt\n' >>"$STUB_ATTEMPTS"
			cat "$STUB_CURL_BODY"
		SHIM
	fi
	chmod +x "$dir/bin/curl"
	case "$security_mode" in
	ok)
		cat >"$dir/bin/security" <<-'SHIM'
			#!/usr/bin/env bash
			printf '%s\n' '{"claudeAiOauth":{"accessToken":"stub-token"}}'
		SHIM
		chmod +x "$dir/bin/security"
		;;
	fail)
		cat >"$dir/bin/security" <<-'SHIM'
			#!/usr/bin/env bash
			exit 1
		SHIM
		chmod +x "$dir/bin/security"
		;;
	absent) ;;
	esac
}

fallback_case() {
	local dir="$FALLBACK_ROOT/$1"
	mkdir -p "$dir/tmp"
	make_fallback_bin "$dir" gate ok
}

fallback_fetch() {
	local dir="$FALLBACK_ROOT/$1" curl_exit="$2" body="$3" now="$4"
	printf '%s' "$body" >"$dir/body"
	printf '%s' "$curl_exit" >"$dir/curl-exit"
	(
		# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
		export PATH="$dir/bin:$PATH" TMPDIR="$dir/tmp" CLAUDE_CONFIG_DIR="$dir"
		# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
		export STUB_ATTEMPTS="$dir/attempts" STUB_CURL_BODY="$dir/body" STUB_CURL_EXIT="$dir/curl-exit"
		fetch_usage_fallback "$now"
	)
}

seed_good_cache() {
	local case_name="$1"
	fallback_case "$case_name"
	fallback_fetch "$case_name" 0 "$USAGE_BODY" "$FB_BASE" >/dev/null
}

concurrent_refresh() {
	# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
	export PATH="$FALLBACK_ROOT/concurrent/bin:$PATH"
	# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
	export RACE_ATTEMPTS="$FALLBACK_ROOT/concurrent/attempts" RACE_CURL_BODY="$FALLBACK_ROOT/concurrent/body" RACE_CURL_EXIT="$FALLBACK_ROOT/concurrent/curl-exit"
	# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
	export RACE_RELEASE="$FALLBACK_ROOT/concurrent/release"
	# shellcheck disable=SC2154  # set by calling scope
	refresh_usage_cache concurrent "$concurrent_cache" "$concurrent_marker" "$USAGE_BACKOFF_SECONDS" "$(date +%s)"
}

setup_reclaim_race() {
	seed_good_cache reclaim
	# shellcheck disable=SC2034  # used by reclaim_refresh in a subshell
	reclaim_cache=$(compgen -G "$RECLAIM_TMP/claude-statusline-usage-*.json")
	# shellcheck disable=SC2034  # used by reclaim_refresh in a subshell
	reclaim_marker="${reclaim_cache}.attempt"

	cat >"$RECLAIM_DIR/bin/curl" <<-'SHIM'
		#!/usr/bin/env bash
		printf '%s\n' "$RACE_ID" >>"$RACE_ATTEMPTS"
		if [[ -n "${RACE_HOLD:-}" ]]; then
			until [[ -f "$RACE_HOLD" ]]; do sleep 0.05; done
		fi
		code=$(cat "$RACE_CURL_EXIT")
		((code == 0)) || exit "$code"
		cat "$RACE_CURL_BODY"
	SHIM
	chmod +x "$RECLAIM_DIR/bin/curl"
	: >"$RECLAIM_ATTEMPTS"
	rm -f "$RECLAIM_DIR"/release.*
	printf '%s' "$FRESH_USAGE_BODY" >"$RECLAIM_DIR/body"
	printf '0' >"$RECLAIM_DIR/curl-exit"
}

reclaim_refresh() {
	local id="$1" hold="${2-}"
	# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
	export PATH="$RECLAIM_DIR/bin:$PATH" TMPDIR="$RECLAIM_TMP"
	# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
	export RACE_ID="$id" RACE_ATTEMPTS="$RECLAIM_ATTEMPTS" RACE_CURL_BODY="$RECLAIM_DIR/body" RACE_CURL_EXIT="$RECLAIM_DIR/curl-exit"
	# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
	[[ -z "$hold" ]] || export RACE_HOLD="$RECLAIM_DIR/release.$id"
	# shellcheck disable=SC2154  # set by calling scope
	refresh_usage_cache reclaim "$reclaim_cache" "$reclaim_marker" "$USAGE_BACKOFF_SECONDS" "$(date +%s)"
}

run_render() {
	local pid
	(reclaim_refresh "$1") &
	pid=$!
	wait "$pid"
}

release_render() {
	touch "$RECLAIM_DIR/release.$1"
}

wait_for_file() {
	local path="$1" tries=0
	until [[ -s "$path" ]]; do
		((++tries < 100)) || return 1
		sleep 0.05
	done
}

wait_for_attempt() {
	local id="$1" tries=0
	until grep -qx "$id" "$RECLAIM_ATTEMPTS"; do
		((++tries < 200)) || return 1
		sleep 0.05
	done
}

require_stalled_render() {
	wait_for_attempt "$1" || {
		printf 'render %s never reached its fetch\n' "$1" >&2
		return 1
	}
}

make_lock_stale() {
	local lock
	lock=$(find "$RECLAIM_TMP" -mindepth 1 -maxdepth 1 -type d)
	[[ -n "$lock" && "$lock" != *$'\n'* ]] || {
		printf 'expected exactly one lock directory, found: %q\n' "$lock" >&2
		return 1
	}
	find "$lock" -depth -exec touch -t "$STALE_STAMP" {} +
}

cred_fallback_case() {
	local dir="$CRED_ROOT/$1" token="${2:-cred-file-token}"
	make_fallback_bin "$dir" nogate fail
	printf '{"claudeAiOauth":{"accessToken":"%s"}}' "$token" >"$dir/.credentials.json"
	printf '%s' "$USAGE_BODY" >"$dir/body"
}

cred_fetch() {
	local dir="$CRED_ROOT/$1"
	(
		# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
		export PATH="$dir/bin:$PATH" CLAUDE_CONFIG_DIR="$dir"
		# shellcheck disable=SC2030,SC2031  # exports scoped to subshell
		export STUB_ATTEMPTS="$dir/attempts" STUB_CURL_BODY="$dir/body"
		fetch_usage_payload default
	)
}

# ---------------------------------------------------------------------------
# Transcript fixtures
# ---------------------------------------------------------------------------
#
# Records carry the fields the model lookup reads (type, isSidechain,
# message.model); the rest of a real transcript record is irrelevant to it.

assistant_record() {
	local model="$1"
	printf '{"isSidechain":false,"type":"assistant","message":{"role":"assistant","model":"%s"}}' "$model"
}

sidechain_record() {
	local model="$1"
	printf '{"isSidechain":true,"type":"assistant","message":{"role":"assistant","model":"%s"}}' "$model"
}

modelless_record() {
	printf '{"isSidechain":false,"type":"assistant","message":{"role":"assistant"}}'
}

# A record of some other type that still carries a model, so a lookup that
# ignores .type has something wrong to find.
typed_record() {
	local type="$1" model="$2"
	printf '{"isSidechain":false,"type":"%s","message":{"role":"%s","model":"%s"}}' "$type" "$type" "$model"
}

pad_of() {
	printf '%*s' "$1" '' | tr ' ' 'x'
}

padded_assistant_record() {
	local model="$1" pad
	pad=$(pad_of "$2")
	printf '{"isSidechain":false,"type":"assistant","message":{"role":"assistant","model":"%s","pad":"%s"}}' "$model" "$pad"
}

padded_user_record() {
	local pad
	pad=$(pad_of "$1")
	printf '{"isSidechain":false,"type":"user","message":{"role":"user","content":"%s"}}' "$pad"
}

# No records means an empty transcript.
write_transcript() {
	local case_name="$1" dir path record
	shift
	dir="$MAIN_CASES/$case_name"
	mkdir -p "$dir"
	path="$dir/transcript.jsonl"
	: >"$path"
	for record in "$@"; do
		printf '%s\n' "$record" >>"$path"
	done
	printf '%s' "$path"
}

cred_no_security_case() {
	local dir="$CRED_ROOT/no-security" tool path
	make_fallback_bin "$dir" nogate absent
	for tool in jq cat bash; do
		if path=$(command -v "$tool"); then
			ln -sf "$path" "$dir/bin/$tool"
		fi
	done
	printf '{"claudeAiOauth":{"accessToken":"no-security-token"}}' >"$dir/.credentials.json"
	printf '%s' "$USAGE_BODY" >"$dir/body"
}
