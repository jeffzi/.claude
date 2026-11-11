#!/usr/bin/env bats

load helpers/statusline

setup_file() {
	declare -F main >/dev/null || {
		printf 'FATAL: main is not defined after sourcing %s\n' "$SCRIPT" >&2
		return 1
	}

	export RESET EMPTY HALF FILLED

	export NOW=1700000000
	export PACE_WINDOW=$FIVE_HOUR_SECONDS
	# 3600s left of an 18000s window means 80% of it has elapsed — the pace
	# baseline the "Pace arrow thresholds" tests compare against.
	export PACE_RESET=$((NOW + 3600))

	export MAIN_NOW
	MAIN_NOW=$(date +%s)
	export MAIN_PAYLOAD
	MAIN_PAYLOAD=$(printf '{"five_hour":{"used_percentage":78,"resets_at":%s},"seven_day":{"used_percentage":7,"resets_at":%s}}' \
		"$((MAIN_NOW + 4 * 3600 + 10 * 60 - 1))" "$((MAIN_NOW + 4 * 86400 + 13 * 3600 + 1800))")

	export MAIN_CASES
	MAIN_CASES=$(mktemp -d "${TMPDIR:-/tmp}/statusline-cases.XXXXXX")

	# transcript_path points inside the per-run case root at a file no case
	# writes, so the shared envelope never annotates the model segment and no
	# stray file on the host can make it do so.
	export STDIN_ENVELOPE
	STDIN_ENVELOPE=$(printf '{"hook_event_name":"Status","session_id":"statusline-test","transcript_path":"%s","cwd":"/tmp/statusline-proj","version":"1.0.0","output_style":{"name":"default"},"context_window":{"used_percentage":45}}' \
		"$MAIN_CASES/absent-transcript.jsonl")
	export STDIN_MODEL_WORKSPACE='{"model":{"id":"claude-opus-4-1","display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/statusline-proj","project_dir":"/tmp/statusline-proj"}}'

	export MAIN_STDIN
	MAIN_STDIN=$(full_stdin_json '{}')

	export FALLBACK_ROOT
	FALLBACK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statusline-fallback.XXXXXX")

	export USAGE_BODY='{"five_hour":{"utilization":42,"resets_at":"2099-12-31T23:59:59Z"},"seven_day":{"utilization":13,"resets_at":"2100-01-06T00:00:00Z"}}'
	export FIVE_HOUR_RESET_EPOCH=4102444799
	export RATE_LIMITED_BODY='{"error":{"type":"rate_limit_error","message":"rate limit exceeded"}}'
	# What the endpoint sends with an HTTP 401; `curl -s` exits 0 on it.
	export AUTH_ERROR_BODY='{"type":"error","error":{"type":"authentication_error","message":"OAuth token has expired"}}'
	export NO_LIMITS_LINE="statusline-proj │ Opus 4.6 ● ● ◎ ○ ○"

	# What the endpoint sends while a window is not open: the key is there, its value null.
	export NULL_FIVE_HOUR_BODY='{"five_hour":null,"seven_day":{"utilization":13,"resets_at":"2100-01-06T00:00:00Z"}}'
	export NULL_WINDOWS_BODY='{"five_hour":null,"seven_day":null}'

	export FRESH_USAGE_BODY='{"five_hour":{"utilization":55,"resets_at":"2099-12-31T23:59:59Z"},"seven_day":{"utilization":13,"resets_at":"2100-01-06T00:00:00Z"}}'

	export FB_BASE
	FB_BASE=$(date +%s)

	export CRED_ROOT
	CRED_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statusline-cred.XXXXXX")

	local shim_body

	export PROBE_DIR="$MAIN_CASES/stat-probe-unusable"
	shim_body=$'#!/usr/bin/env bash\nexit 1'
	make_stat_shim "$PROBE_DIR" "$shim_body"

	export BSD_DIR="$MAIN_CASES/stat-probe-bsd"
	shim_body=$(
		cat <<-'SHIM'
			#!/usr/bin/env bash
			if [[ "${1:-}" == "-f" && "${2:-}" == "%m" ]]; then
				printf '1700000000\n'
			else
				exit 1
			fi
		SHIM
	)
	make_stat_shim "$BSD_DIR" "$shim_body"

	export GNU_DIR="$MAIN_CASES/stat-probe-gnu"
	shim_body=$(
		cat <<-'SHIM'
			#!/usr/bin/env bash
			if [[ "${1:-}" == "-c" && "${2:-}" == "%Y" ]]; then
				printf '1700000000\n'
			else
				exit 1
			fi
		SHIM
	)
	make_stat_shim "$GNU_DIR" "$shim_body"

	export RECLAIM_DIR="$FALLBACK_ROOT/reclaim"
	export RECLAIM_TMP="$RECLAIM_DIR/tmp"
	export RECLAIM_ATTEMPTS="$RECLAIM_DIR/attempts"
	export STALE_STAMP=202001010000
}

teardown_file() {
	rm -rf "${MAIN_CASES:-}" "${FALLBACK_ROOT:-}" "${CRED_ROOT:-}"
}

bad_limits_stdin() {
	full_stdin_json '{"rate_limits":"{not json","cost":{"total_api_duration_ms":100}}'
}

usage_cache_path() {
	local hash
	hash=$(printf '%s' "$1" | sha256_hex) || return
	printf '%s/claude-statusline-usage-%s.json' "$1" "$hash"
}

undated_five_hour_body() {
	printf '{"five_hour":{"utilization":42,"resets_at":null},"seven_day":{"utilization":13,"resets_at":"%s"}}' \
		"$(epoch_to_iso "$1")"
}

assert_prints_mtime() {
	local out="" status=0
	out=$("$@") || status=$?
	[[ "$status" -eq 0 && "$out" =~ ^[0-9]+$ ]]
}

# ── Glyph layout ─────────────────────────────────────────────────────────────

@test "100%: all slots filled" {
	assert_glyphs 100 "● ● ● ● ●"
}

# ── Fractional slot rounding ─────────────────────────────────────────────────

@test "64% (3.20 slots): fraction below 0.25 renders empty" {
	assert_bar 64 "FFFEE"
}

@test "65% (3.25 slots): fraction at 0.25 renders a gradient-colored half" {
	assert_bar 65 "FFFHE"
}

@test "74% (3.70 slots): fraction below 0.75 renders a gradient-colored half" {
	assert_bar 74 "FFFHE"
}

@test "75% (3.75 slots): fraction at 0.75 is promoted to filled" {
	assert_bar 75 "FFFFE"
}

# ── Gradient coloring ────────────────────────────────────────────────────────

@test "50%: the filled slots and the half wear the literal 50% escape" {
	local gold=$'\033[38;2;207;183;63m' actual

	actual=$(format_context_bar 50)

	assert_exact "$actual" "${gold}●${RESET} ${gold}●${RESET} ${gold}◎${RESET} ○ ○"
}

# ── Gradient matches the HSL ramp ────────────────────────────────────────────

@test "25%: within 1 per channel of the HSL reference (pct <= 50 branch)" {
	assert_matches_hsl_ref 25
}

@test "75%: within 1 per channel of the HSL reference (pct > 50 branch)" {
	assert_matches_hsl_ref 75
}

@test "50% to 51%: ramp halves meet without a seam" {
	assert_continuous_across 50 51 5
}

# ── Gradient anchors ─────────────────────────────────────────────────────────

@test "0%: no escape, inherits terminal default" {
	local color

	color=$(usage_color 0)

	[[ -z "$color" ]]
}

@test "14%: the last percentage below the saturation threshold" {
	local color

	color=$(usage_color 14)

	[[ -z "$color" ]]
}

# ── Limit segment coloring ───────────────────────────────────────────────────

@test "61%: label, space, and percentage all wear the gradient" {
	local seg_color seg_out seg_want
	seg_color=$(usage_color 61)
	seg_want="${seg_color}5h 61%"

	seg_out=$(format_limit_segment "5h" 61 "$PACE_RESET" "$PACE_WINDOW" "$NOW")

	[[ "$seg_out" == *"$seg_want"* ]]
}

@test "5h countdown renders in the default foreground" {
	assert_reset_uncolored "5h" 88 "$PACE_RESET" "$PACE_WINDOW"
}

# ── Pace arrow thresholds ────────────────────────────────────────────────────

@test "75% at 80% pace (delta -5): down arrow at the boundary" {
	assert_pace_glyph 75 "↓"
}

@test "76% at 80% pace (delta -4): on pace, no arrow" {
	assert_pace_glyph 76 ""
}

@test "84% at 80% pace (delta +4): on pace, no arrow" {
	assert_pace_glyph 84 ""
}

@test "85% at 80% pace (delta +5): up arrow at the boundary" {
	assert_pace_glyph 85 "↑"
}

@test "95% at 80% pace (delta +15): double arrow at the boundary" {
	assert_pace_glyph 95 "↑↑"
}

# ── Pace arrow color ─────────────────────────────────────────────────────────

@test "85%: the up arrow inherits the 85% gradient" {
	assert_arrow_color 85 "↑"
}

# ── Segment shape ────────────────────────────────────────────────────────────

@test "over pace: the arrow hugs the percentage" {
	assert_segment_plain "5h" 88 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 88%↑ · 1h"
}

@test "on pace: countdown alone, no arrow" {
	assert_segment_plain "5h" 82 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 82% · 1h"
}

@test "no countdown to show: nothing follows the percentage" {
	assert_segment_plain "5h" 100 "$NOW" "$PACE_WINDOW" " │ 5h 100%"
}

@test "74%: below the percentage threshold, but the pace arrow brings the countdown" {
	assert_segment_plain "5h" 74 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 74%↓ · 1h"
}

@test "75%: at the threshold, the countdown appears" {
	assert_segment_plain "5h" 75 "$((NOW + 4500))" "$PACE_WINDOW" " │ 5h 75% · 1h15m"
}

@test "40% with 45m left: an imminent reset brings the countdown back" {
	assert_segment_plain "5h" 40 "$((NOW + 45 * 60))" "$PACE_WINDOW" " │ 5h 40% · 45m"
}

# ── Reset countdown ──────────────────────────────────────────────────────────

@test "45m left: minutes alone" {
	assert_countdown $((45 * 60)) "45m"
}

@test "2h left: zero minutes are dropped" {
	assert_countdown $((2 * 3600)) "2h"
}

@test "23h59m left: still below a day" {
	assert_countdown $((23 * 3600 + 59 * 60)) "23h59m"
}

@test "exactly 24h left: a day with zero hours" {
	assert_countdown $((24 * 3600)) "1d"
}

@test "4d13h left: days and hours" {
	assert_countdown $((4 * 86400 + 13 * 3600)) "4d13h"
}

@test "59s left: reset is imminent, renders 0m" {
	assert_countdown 59 "0m"
}

@test "reset lands on now: nothing to count down" {
	assert_countdown 0 ""
}

# ── Directory segment ────────────────────────────────────────────────────────

@test "a branch and no worktree: the branch follows the basename" {
	assert_dir "/tmp/statusline-proj" "" "dash" "statusline-proj ⎇ dash"
}

@test "a worktree outranks the branch: one name after the glyph" {
	assert_dir "/tmp/statusline-proj" "feature-x" "dash" "statusline-proj ⎇ feature-x"
}

@test "neither branch nor worktree: the basename stands alone" {
	assert_dir "/tmp/statusline-proj" "" "" "statusline-proj"
}

# ── Portable sha256 helper ───────────────────────────────────────────────────

@test "sha256_hex emits 8 lowercase hex characters that differ across inputs" {
	local a b
	a=$(printf 'hello' | sha256_hex)
	b=$(printf 'world' | sha256_hex)

	[[ "$a" =~ ^[0-9a-f]{8}$ && "$b" =~ ^[0-9a-f]{8}$ && "$a" != "$b" ]]
}

# ── Stat probe and file_mtime contract ───────────────────────────────────────

@test "file_mtime returns 1 for an absent file" {
	local status=0

	file_mtime "/nonexistent/path/should/not/exist" >/dev/null 2>&1 || status=$?

	[[ "$status" -eq 1 ]]
}

@test "unusable stat on an existing file returns SH_STAT_UNUSABLE" {
	local status=0

	probe_then_mtime "$PROBE_DIR" "$SCRIPT" >/dev/null 2>&1 || status=$?

	[[ "$status" -eq "$SH_STAT_UNUSABLE" ]]
}

@test "unusable stat on an absent file still returns 1" {
	local status=0

	probe_then_mtime "$PROBE_DIR" "/nonexistent/path" >/dev/null 2>&1 || status=$?

	[[ "$status" -eq 1 ]]
}

@test "BSD stat stub: probe detects -f %m and file_mtime succeeds" {
	assert_prints_mtime probe_then_mtime "$BSD_DIR" "$SCRIPT"
}

@test "GNU stat stub: probe detects -c %Y and file_mtime succeeds" {
	assert_prints_mtime probe_then_mtime "$GNU_DIR" "$SCRIPT"
}

@test "an IFS without a space still hands stat its format flag and value apart" {
	IFS=$'\n\t' assert_prints_mtime probe_then_mtime "$BSD_DIR" "$SCRIPT"
}

# ── Transcript model family ──────────────────────────────────────────────────

@test "the last assistant record supplies the family" {
	local path
	path=$(write_transcript family-last \
		"$(assistant_record claude-opus-4-1)" \
		"$(assistant_record claude-sonnet-5)")

	assert_family family-last "$path" "sonnet"
}

@test "a dated model ID keeps only the family token" {
	local path
	path=$(write_transcript family-dated "$(assistant_record claude-haiku-4-5-20251001)")

	assert_family family-dated "$path" "haiku"
}

# ── Transcript records that cannot supply the family ─────────────────────────

@test "a sidechain record never supplies the family" {
	local path
	path=$(write_transcript family-sidechain \
		"$(assistant_record claude-sonnet-5)" \
		"$(sidechain_record claude-haiku-4-5)")

	assert_family family-sidechain "$path" "sonnet"
}

@test "an assistant record without a model never supplies the family" {
	local path
	path=$(write_transcript family-modelless \
		"$(assistant_record claude-sonnet-5)" \
		"$(modelless_record)")

	assert_family family-modelless "$path" "sonnet"
}

@test "a synthetic error record never supplies the family" {
	local path
	path=$(write_transcript family-synthetic \
		"$(assistant_record claude-sonnet-5)" \
		"$(assistant_record '<synthetic>')")

	assert_family family-synthetic "$path" "sonnet"
}

@test "a non-assistant record never supplies the family" {
	local path
	path=$(write_transcript family-user \
		"$(assistant_record claude-sonnet-5)" \
		"$(typed_record user claude-haiku-4-5)")

	assert_family family-user "$path" "sonnet"
}

# ── Nothing to annotate ──────────────────────────────────────────────────────

@test "a transcript whose every record is disqualified prints nothing" {
	local path
	path=$(write_transcript family-none \
		"$(typed_record user claude-sonnet-5)" \
		"$(sidechain_record claude-haiku-4-5)" \
		"$(modelless_record)")

	assert_family family-none "$path" ""
}

# ── Transcript tail cap ──────────────────────────────────────────────────────

@test "the partial line at the tail cap boundary is skipped" {
	local path
	path=$(write_transcript family-boundary \
		"$(padded_assistant_record claude-ghost-1 $((TRANSCRIPT_TAIL_BYTES + 100)))" \
		"$(assistant_record claude-sonnet-5)")

	assert_family family-boundary "$path" "sonnet"
}

@test "a record older than the tail cap is out of reach" {
	local path
	path=$(write_transcript family-out-of-reach \
		"$(assistant_record claude-opus-4-1)" \
		"$(padded_user_record $((TRANSCRIPT_TAIL_BYTES + 100)))")

	assert_family family-out-of-reach "$path" ""
}

# ── Model family annotation ──────────────────────────────────────────────────

@test "a transcript served by another family annotates the model segment" {
	local path out
	path=$(write_transcript annotate-other "$(assistant_record claude-sonnet-5)")

	out=$(main_render annotate-other "$(annotation_stdin "$path")" "$MAIN_PAYLOAD" | strip_ansi)

	assert_model_segment "$out" "Opus 4.6→sonnet (high)"
}

@test "a transcript served by the configured family leaves the line as it renders today" {
	local path out
	path=$(write_transcript annotate-same "$(assistant_record claude-opus-4-5)")

	out=$(main_render annotate-same "$(annotation_stdin "$path")" "$MAIN_PAYLOAD" | strip_ansi)

	assert_model_segment "$out" "Opus 4.6 (high)"
}

# ── Nothing to annotate with: the segment stays as it is ─────────────────────

@test "an unreadable transcript: the segment renders unannotated" {
	local path
	path=$(write_transcript degraded-unreadable "$(assistant_record claude-sonnet-5)")
	chmod 000 "$path"

	assert_unannotated_render degraded-unreadable "$(annotation_stdin "$path")"
}

@test "no model.id on stdin: nothing to compare against, so the segment renders unannotated" {
	local path
	path=$(write_transcript degraded-no-model-id "$(assistant_record claude-sonnet-5)")

	assert_unannotated_render degraded-no-model-id \
		"$(stdin_without '.model.id' "$(annotation_stdin "$path")")"
}

# ── Whole line ───────────────────────────────────────────────────────────────

@test "the happy path renders dir, model, gauge, 5h with arrow and countdown, and the 7d tail" {
	local out

	out=$(main_line | strip_ansi)

	assert_whole_line "$out" "Opus 4.6"
}

@test "workspace.git_worktree reaches the line beside the basename" {
	local stdin_wt out
	stdin_wt=$(full_stdin_json '{"workspace":{"git_worktree":"feature-x"}}')

	out=$(main_render worktree "$stdin_wt" "$MAIN_PAYLOAD" | strip_ansi)

	assert_leading_segment "$out" "statusline-proj ⎇ feature-x"
}

@test "the branch of workspace.current_dir reaches the line beside the basename" {
	local repo stdin_branch out
	repo="$MAIN_CASES/branch-repo"
	git init -q -b tdd-branch "$repo"
	stdin_branch=$(full_stdin_json "$(printf '{"workspace":{"current_dir":"%s"}}' "$repo")")

	out=$(main_render branch "$stdin_branch" "$MAIN_PAYLOAD" | strip_ansi)

	assert_leading_segment "$out" "branch-repo ⎇ tdd-branch"
}

# ── Degraded input ───────────────────────────────────────────────────────────

@test "a stdin without model.display_name or workspace.current_dir: empty leading segment, never null" {
	local stdin_no_names out
	stdin_no_names=$(stdin_json '{"model":{"id":"claude-opus-4-1"},"workspace":{"project_dir":"/tmp/statusline-proj"}}')

	out=$(main_render no-names "$stdin_no_names" "$MAIN_PAYLOAD" | strip_ansi)

	assert_leading_segment "$out" ""
	assert_not_contains "$out" "null"
}

@test "an unparseable rate-limits payload is reported on stderr" {
	local err

	main_render bad-limits "$(bad_limits_stdin)" >/dev/null
	err=$(<"$MAIN_CASES/bad-limits/stderr")

	assert_contains "$err" "rate-limit parse failed"
}

@test "an unparseable rate-limits payload names the parse failure on the line itself" {
	local out

	out=$(main_render bad-limits-line "$(bad_limits_stdin)" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: parse failed"
}

@test "an unreadable usage cache is named on the line instead of blanking the limits" {
	local dir="$MAIN_CASES/corrupt-cache" cache out
	mkdir -p "$dir"
	cache=$(usage_cache_path "$dir")
	printf 'not json' >"$cache"
	printf 'ok' >"$cache.attempt"

	out=$(main_render corrupt-cache "$MAIN_STDIN" "$MAIN_PAYLOAD" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: cache unreadable"
}

@test "a usage cache that cannot be written: named failure line" {
	local dir="$MAIN_CASES/unwritable-cache" marker
	mkdir -p "$dir"
	marker="$(usage_cache_path "$dir").attempt"
	: >"$marker"
	touch -t "$STALE_STAMP" "$marker"
	chmod a-w "$marker"

	assert_failure_line_naming "$dir" \
		main_render unwritable-cache "$MAIN_STDIN" "$MAIN_PAYLOAD"
}

@test "stdin jq cannot walk: the line reports the failure" {
	assert_degraded_render "statusline: stdin parse failed" \
		main_render broken-stdin 'not json at all'
}

# ── Missing or unusable tools ────────────────────────────────────────────────

@test "a missing jq is reported as a named failure line" {
	assert_failure_line_naming jq \
		missing_dep_render jq jq
}

@test "neither shasum nor sha256sum: named failure line" {
	missing_sha256_render() {
		missing_dep_render sha256 "shasum sha256sum"
	}

	assert_degraded_render "statusline: missing required tool: shasum or sha256sum" \
		missing_sha256_render
}

@test "render succeeds when usage fetch fails: context gauge and model name present" {
	local out

	out=$(main_render no-security "$MAIN_STDIN" | strip_ansi)

	assert_contains "$out" "● ● ◎ ○ ○"
	assert_contains "$out" "Opus 4.6"
}

@test "an unusable stat with a marker to read: named failure line" {
	main_render stat-present "$MAIN_STDIN" "$MAIN_PAYLOAD" >/dev/null

	assert_degraded_render "statusline: unusable required tool: stat" \
		unusable_stat_render stat-present
}

# ── Usage fallback: 300s throttle between attempts ───────────────────────────

@test "fallback throttle: the first call reaches the endpoint once" {
	fallback_case throttle

	fallback_fetch throttle 0 "$USAGE_BODY" "$FB_BASE" >/dev/null

	assert_attempts throttle 1
}

@test "fallback throttle: the first call maps the usage payload" {
	local out
	fallback_case throttle-mapping

	out=$(fallback_fetch throttle-mapping 0 "$USAGE_BODY" "$FB_BASE")

	assert_fallback_json "$out" '.five_hour.used_percentage' 42
	assert_fallback_json "$out" '.five_hour.resets_at' "$FIVE_HOUR_RESET_EPOCH"
	assert_fallback_json "$out" '.seven_day.used_percentage' 13
}

@test "fallback throttle: 250s after a success, no request is sent" {
	fallback_case throttle-250
	fallback_fetch throttle-250 0 "$USAGE_BODY" "$FB_BASE" >/dev/null

	fallback_fetch throttle-250 0 "$USAGE_BODY" $((FB_BASE + 250)) >/dev/null

	assert_attempts throttle-250 1
}

@test "fallback throttle: 250s after a success, the cached payload is served" {
	local out
	fallback_case throttle-250-served
	fallback_fetch throttle-250-served 0 "$USAGE_BODY" "$FB_BASE" >/dev/null

	out=$(fallback_fetch throttle-250-served 0 "$USAGE_BODY" $((FB_BASE + 250)))

	assert_fallback_json "$out" '.five_hour.used_percentage' 42
}

@test "fallback throttle: 400s after a success, the 300s window expired" {
	fallback_case throttle-400
	fallback_fetch throttle-400 0 "$USAGE_BODY" "$FB_BASE" >/dev/null

	fallback_fetch throttle-400 0 "$USAGE_BODY" $((FB_BASE + 400)) >/dev/null

	assert_attempts throttle-400 2
}

# ── Usage fallback: failures keep the last good payload ──────────────────────

@test "fallback failure: curl error, the request was attempted and the last good payload still served" {
	local out
	seed_good_cache curl-failure

	out=$(fallback_fetch curl-failure 7 "" $((FB_BASE + 400)))

	assert_attempts curl-failure 2
	assert_fallback_json "$out" '.five_hour.used_percentage' 42
}

@test "fallback failure: 800s after a failure, still backing off with the good payload cached" {
	local out
	seed_good_cache curl-failure-backoff
	fallback_fetch curl-failure-backoff 7 "" $((FB_BASE + 400)) >/dev/null

	out=$(fallback_fetch curl-failure-backoff 7 "" $((FB_BASE + 800)))

	assert_attempts curl-failure-backoff 2
	assert_fallback_json "$out" '.five_hour.used_percentage' 42
}

@test "fallback failure: 1000s after a failure, the 900s backoff expired" {
	seed_good_cache curl-failure-1000
	fallback_fetch curl-failure-1000 7 "" $((FB_BASE + 400)) >/dev/null

	fallback_fetch curl-failure-1000 7 "" $((FB_BASE + 1000)) >/dev/null

	assert_attempts curl-failure-1000 3
}

# ── Usage fallback: error bodies are failures, not data ──────────────────────

@test "an error body without a window key: good payload served, not null" {
	local out
	seed_good_cache rate-limited

	out=$(fallback_fetch rate-limited 0 "$RATE_LIMITED_BODY" $((FB_BASE + 400)))

	assert_fallback_json "$out" '.five_hour.used_percentage' 42
}

# ── Usage fallback: expired windows are filtered ─────────────────────────────

@test "fallback expiry: an expired five_hour window is filtered, seven_day still served" {
	local body out
	fallback_case expire-partial
	body=$(make_expiry_body $((FB_BASE + 100)) $((FB_BASE + 10000)))
	fallback_fetch expire-partial 0 "$body" "$FB_BASE" >/dev/null

	out=$(fallback_fetch expire-partial 0 "$body" $((FB_BASE + 200)))

	assert_fallback_json "$out" '.five_hour.used_percentage // empty' ""
	assert_fallback_json "$out" '.seven_day.used_percentage' 13
}

@test "fallback expiry: all windows expired returns exit 1" {
	local body status=0
	fallback_case expire-all
	body=$(make_expiry_body $((FB_BASE + 100)) $((FB_BASE + 100)))
	fallback_fetch expire-all 0 "$body" "$FB_BASE" >/dev/null

	fallback_fetch expire-all 0 "$body" $((FB_BASE + 200)) >/dev/null || status=$?

	assert_exact "$status" 1
}

# ── Usage fallback: expired cache opens the poll throttle ────────────────────

@test "fallback expiry: all expired bypasses USAGE_POLL_SECONDS throttle" {
	local body fresh_body
	fallback_case expire-throttle
	body=$(make_expiry_body $((FB_BASE + 100)) $((FB_BASE + 100)))
	fresh_body=$(make_expiry_body $((FB_BASE + 5000)) $((FB_BASE + 50000)))
	fallback_fetch expire-throttle 0 "$body" "$FB_BASE" >/dev/null

	# 200s < USAGE_POLL_SECONDS (300s), but all windows are expired — refresh anyway
	fallback_fetch expire-throttle 0 "$fresh_body" $((FB_BASE + 200)) >/dev/null

	assert_attempts expire-throttle 2
}

@test "fallback expiry: expired cache still respects USAGE_BACKOFF_SECONDS on failure" {
	local body status=0
	fallback_case expire-backoff
	body=$(make_expiry_body $((FB_BASE + 100)) $((FB_BASE + 100)))
	fallback_fetch expire-backoff 0 "$body" "$FB_BASE" >/dev/null
	# A failed refresh after the poll window opens the backoff
	fallback_fetch expire-backoff 7 "" $((FB_BASE + 400)) >/dev/null || true

	# Within backoff: no new refresh, but all windows are expired — exit 1
	fallback_fetch expire-backoff 0 "$body" $((FB_BASE + 600)) >/dev/null || status=$?

	assert_attempts expire-backoff 2
	assert_failed_status "$status" "fetch inside the backoff with every window expired"
}

@test "fallback expiry: an undated five_hour beside an expired seven_day is still served" {
	local body out
	fallback_case expire-undated-served
	body=$(undated_five_hour_body $((FB_BASE + 100)))
	fallback_fetch expire-undated-served 0 "$body" "$FB_BASE" >/dev/null

	out=$(fallback_fetch expire-undated-served 0 "$body" $((FB_BASE + 200)))

	assert_fallback_json "$out" '.five_hour.used_percentage' 42
}

@test "fallback expiry: an undated five_hour beside an expired seven_day keeps the poll throttle" {
	local body
	fallback_case expire-undated-throttle
	body=$(undated_five_hour_body $((FB_BASE + 100)))
	fallback_fetch expire-undated-throttle 0 "$body" "$FB_BASE" >/dev/null

	fallback_fetch expire-undated-throttle 0 "$body" $((FB_BASE + 200)) >/dev/null

	assert_attempts expire-undated-throttle 1
}

# ── Usage fallback: the lock keeps concurrent renders from double-fetching ───

@test "the lock keeps concurrent renders from double-fetching" {
	# shellcheck disable=SC2034  # populated by setup_concurrent_race, used by concurrent_refresh in a subshell
	local concurrent_cache concurrent_marker first_pid attempts_after_second served_to_second served_after_first
	setup_concurrent_race
	concurrent_refresh &
	first_pid=$!
	wait_for_file "$FALLBACK_ROOT/concurrent/attempts"

	concurrent_refresh
	attempts_after_second=$(awk 'END {print NR}' <"$FALLBACK_ROOT/concurrent/attempts")
	served_to_second=$(cat "$concurrent_cache")
	touch "$FALLBACK_ROOT/concurrent/release"
	wait "$first_pid"
	served_after_first=$(cat "$concurrent_cache")

	assert_exact "$attempts_after_second" 1
	assert_fallback_json "$served_to_second" '.five_hour.used_percentage' 42
	assert_fallback_json "$served_after_first" '.five_hour.used_percentage' 55
}

# ── Usage fallback: the lock belongs to a render, not to a path ──────────────

@test "the lock belongs to a render, not to a path" {
	# shellcheck disable=SC2034  # populated by setup_reclaim_race, used by reclaim_refresh in a subshell
	local reclaim_cache reclaim_marker
	setup_reclaim_race

	reclaim_refresh stalled hold &
	local stalled_pid=$!
	require_stalled_render stalled
	make_lock_stale
	reclaim_refresh reclaimer hold &
	local reclaimer_pid=$!
	require_stalled_render reclaimer

	run_render bystander
	release_render stalled
	wait "$stalled_pid" || true
	run_render late
	release_render reclaimer
	wait "$reclaimer_pid" || true

	assert_not_fetched bystander
	assert_not_fetched late
	assert_no_stray_dirs
}

# ── Usage fallback: a failed write still frees the lock ──────────────────────

@test "a failed write still frees the lock for the next render" {
	# shellcheck disable=SC2034  # populated by setup_reclaim_race, used by reclaim_refresh in a subshell
	local reclaim_cache reclaim_marker
	setup_reclaim_race

	rm -f "$reclaim_marker"
	mkdir "$reclaim_marker"
	run_render write-fails || [[ $? -eq "$USAGE_CACHE_UNWRITABLE_STATUS" ]]
	rmdir "$reclaim_marker"

	run_render after-write-failure

	assert_fetched after-write-failure
}

# ── Credential file fallback ─────────────────────────────────────────────────

@test "credential file fallback: the file's token reaches curl when security fails" {
	cred_fallback_case cred-fail token-fail

	cred_fetch cred-fail >/dev/null || true

	assert_cred_token_sent cred-fail token-fail
}

@test "credential file fallback: returns non-zero when both sources fail" {
	local dir="$CRED_ROOT/neither" tool status=0
	make_fallback_bin "$dir" nogate fail
	for tool in jq cat bash; do
		ln -sf "$(command -v "$tool")" "$dir/bin/$tool"
	done

	(
		# shellcheck disable=SC2030,SC2031
		export PATH="$dir/bin" CLAUDE_CONFIG_DIR="$dir"
		# shellcheck disable=SC2030,SC2031
		export STUB_ATTEMPTS="$dir/attempts" STUB_CURL_BODY="$dir/body"
		fetch_usage_payload default
	) >/dev/null 2>&1 || status=$?

	assert_failed_status "$status" "payload lookup with neither credential source"
	assert_exact "$(<"$dir/attempts")" ""
}

@test "credential file fallback: a Keychain entry with no token falls through to the file's token" {
	cred_fallback_case keychain-notoken token-file notoken

	cred_fetch keychain-notoken >/dev/null || true

	assert_cred_token_sent keychain-notoken token-file
}

@test "credential file fallback: a malformed Keychain entry falls through to the file's token" {
	cred_fallback_case keychain-malformed token-file malformed

	cred_fetch keychain-malformed >/dev/null || true

	assert_cred_token_sent keychain-malformed token-file
}

@test "the bearer token stays off curl's argv" {
	cred_fallback_case token-argv token-secret

	cred_fetch token-argv >/dev/null || true

	assert_not_contains "$(<"$CRED_ROOT/token-argv/args")" "token-secret"
}

# ── Usage fetch: a failure with nothing cached is named on the line ─────────

@test "no cache and a curl error: the limits slot names the failed fetch" {
	local out
	fallback_case fetch-curl-error

	out=$(fallback_render fetch-curl-error 7 "" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: fetch failed"
}

@test "no cache and an HTTP error body: the limits slot names the failed fetch" {
	local out
	fallback_case fetch-http-error

	out=$(fallback_render fetch-http-error 0 "$AUTH_ERROR_BODY" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: fetch failed"
}

@test "an unparseable credentials file counts as a failed fetch" {
	local out
	fallback_case cred-unparseable fail
	printf 'not json' >"$FALLBACK_ROOT/cred-unparseable/.credentials.json"

	out=$(fallback_render cred-unparseable 0 "$USAGE_BODY" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: fetch failed"
}

@test "an unreadable credentials file counts as a failed fetch" {
	local out creds="$FALLBACK_ROOT/cred-unreadable/.credentials.json"
	fallback_case cred-unreadable fail
	printf '{"claudeAiOauth":{"accessToken":"token-unreadable"}}' >"$creds"
	chmod 000 "$creds"

	out=$(fallback_render cred-unreadable 0 "$USAGE_BODY" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: fetch failed"
}

@test "a malformed Keychain entry and no credentials file counts as a failed fetch" {
	local out
	fallback_case keychain-malformed-alone malformed

	out=$(fallback_render keychain-malformed-alone 0 "$USAGE_BODY" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: fetch failed"
}

@test "a malformed Keychain entry and a credentials file holding no token counts as a failed fetch" {
	local out
	fallback_case keychain-malformed-empty-file malformed
	printf '{"claudeAiOauth":{}}' >"$FALLBACK_ROOT/keychain-malformed-empty-file/.credentials.json"

	out=$(fallback_render keychain-malformed-empty-file 0 "$USAGE_BODY" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: fetch failed"
}

@test "a temp directory that cannot be written: named failure line" {
	local tmp="$FALLBACK_ROOT/tmp-unwritable/tmp"
	fallback_case tmp-unwritable
	chmod a-w "$tmp"

	assert_failure_line_naming "$tmp" \
		fallback_render tmp-unwritable 0 "$USAGE_BODY"
}

@test "inside the failure backoff, a render with no cache still names the failed fetch" {
	local out
	fallback_case fetch-backoff
	fallback_render fetch-backoff 7 "" >/dev/null

	out=$(fallback_render fetch-backoff 7 "" | strip_ansi)

	assert_contains "$out" "Opus 4.6 ● ● ◎ ○ ○ │ limits: fetch failed"
}

@test "a failed fetch with a good cache serves the cache without error text" {
	local out
	fallback_case fetch-cached
	fallback_render fetch-cached 0 "$USAGE_BODY" >/dev/null
	expire_usage_marker fetch-cached

	out=$(fallback_render fetch-cached 7 "" | strip_ansi)

	assert_contains "$out" " │ 5h 42%"
	assert_not_contains "$out" "limits:"
}

# ── Usage fetch: a window the endpoint reports as null is absent, not a failure

@test "a null five_hour window: the seven_day segment renders without an error" {
	local out
	fallback_case null-five-hour

	out=$(fallback_render null-five-hour 0 "$NULL_FIVE_HOUR_BODY" | strip_ansi)

	assert_exact "$out" "$NO_LIMITS_LINE │ 7d 13%"
}

@test "both windows null: no limits segment, no error" {
	local out
	fallback_case null-windows

	out=$(fallback_render null-windows 0 "$NULL_WINDOWS_BODY" | strip_ansi)

	assert_exact "$out" "$NO_LIMITS_LINE"
}

@test "both windows null after an expired cache: the poll throttle holds" {
	local body
	fallback_case null-windows-throttle
	body=$(make_expiry_body $((FB_BASE + 100)) $((FB_BASE + 100)))
	fallback_fetch null-windows-throttle 0 "$body" "$FB_BASE" >/dev/null
	fallback_fetch null-windows-throttle 0 "$NULL_WINDOWS_BODY" $((FB_BASE + 200)) >/dev/null || true

	fallback_fetch null-windows-throttle 0 "$NULL_WINDOWS_BODY" $((FB_BASE + 250)) >/dev/null || true

	assert_attempts null-windows-throttle 2
}

# ── Usage fetch: an account without a token is not a failure ─────────────────

@test "no OAuth token in the Keychain or a credentials file: no limits segment, no error" {
	local out err
	fallback_case no-token fail

	out=$(fallback_render no-token 0 "$USAGE_BODY" | strip_ansi)
	err=$(<"$FALLBACK_ROOT/no-token/stderr")

	assert_exact "$out" "$NO_LIMITS_LINE"
	assert_not_contains "$err" "statusline:"
}

@test "a credentials file holding no token: no limits segment, no error" {
	local out err
	fallback_case cred-no-token fail
	printf '{"claudeAiOauth":{}}' >"$FALLBACK_ROOT/cred-no-token/.credentials.json"

	out=$(fallback_render cred-no-token 0 "$USAGE_BODY" | strip_ansi)
	err=$(<"$FALLBACK_ROOT/cred-no-token/stderr")

	assert_exact "$out" "$NO_LIMITS_LINE"
	assert_not_contains "$err" "statusline:"
}

@test "no OAuth token does not start the failure backoff" {
	fallback_case no-token-backoff fail
	fallback_fetch no-token-backoff 0 "$USAGE_BODY" "$FB_BASE" >/dev/null || true
	printf '{"claudeAiOauth":{"accessToken":"token-later"}}' >"$FALLBACK_ROOT/no-token-backoff/.credentials.json"

	fallback_fetch no-token-backoff 0 "$USAGE_BODY" $((FB_BASE + 400)) >/dev/null

	assert_attempts no-token-backoff 1
}

# ── Script entry point ───────────────────────────────────────────────────────

@test "run by bare file name from inside scripts/, the script renders as by full path" {
	local scripts_dir by_path by_name
	scripts_dir=$(cd "$TEST_DIR/../scripts" && pwd)
	fallback_case script-path fail
	by_path=$(in_fallback_sandbox script-path 0 "" run_script_from / "$scripts_dir/statusline.sh" 2>/dev/null | strip_ansi)

	by_name=$(in_fallback_sandbox script-path 0 "" run_script_from "$scripts_dir" statusline.sh 2>/dev/null | strip_ansi)

	assert_contains "$by_path" "Opus 4.6"
	assert_exact "$by_name" "$by_path"
}
