#!/usr/bin/env bash
set -euo pipefail

# Context bar rendering in scripts/statusline.sh.
#
# The bar is a 5-slot circle gauge, single-space separated, drawn from three glyphs:
# ● (U+25CF) filled, ◎ (U+25CE) half, ○ (U+25CB) empty. All three are unambiguous-width
# concentric circles, so they occupy one cell each. The half-circle family — ◐ (U+25D0),
# ◑ (U+25D1), ◒, ◓ — is never used: their ambiguous East Asian width makes terminals
# render them double-width, larger than ● and ○.
#
# Each slot covers 20%. Within the partially-filled slot the fraction picks the glyph:
# below 0.25 → ○, 0.25 up to 0.75 → ◎, 0.75 and above → ● (promoted to filled).
#
# The gauge is glyphs only — no percentage text follows it. The numbers live in the limit
# segments beside it, so the bar reads as a shape rather than as a second copy of a number.
#
# Color marks progress: the filled slots and the half slot wear the smooth `usage_color`
# gradient. Only empty slots carry no color escape at all, so they render in the terminal's
# default foreground like the model name beside them. There are no color tiers — the gradient
# is continuous across 50% and 90%.

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$TEST_DIR/../scripts/statusline.sh"
PASS=0
FAIL=0

C_RESET=$'\033[0m'
EMPTY="○"
HALF="◎"
FILLED="●"

# ── Helpers ───────────────────────────────────────────────────────────────────

strip_ansi() {
	sed $'s/\033\\[[0-9;]*m//g'
}

require_function() {
	declare -F "$1" >/dev/null || {
		printf "\nFAIL  %s is not defined after sourcing %s\n" "$1" "$SCRIPT"
		exit 1
	}
}

# Shared PASS/FAIL reporter: every expect_* helper below computes "$desc", an
# ok=yes/no verdict, and (on failure only) a detail string, then delegates here.
report() {
	local desc="$1" ok="$2" detail="${3:-}"
	if [[ "$ok" == "yes" ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		printf "FAIL  %s\n    %s\n" "$desc" "$detail"
		((++FAIL))
	fi
}

expect_glyphs() {
	local desc="$1" pct="$2" expected="$3" actual ok=no
	actual=$(format_context_bar "$pct" | strip_ansi)
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected: %s\n      actual: %s' "$expected" "$actual")"
}

# Compares the fully colored bar against a slot pattern, one character per slot:
#
#   F  filled ●, wearing the `usage_color $pct` gradient
#   H  half ◎, wearing the same gradient
#   E  empty ○, uncolored
#
# The gradient escape is looked up from usage_color itself, so these assertions pin which
# glyphs carry the gradient without restating the ramp — the ramp has its own tests below.
expect_bar() {
	local desc="$1" pct="$2" pattern="$3" color expected="" sep="" i actual ok=no
	local filled="$FILLED" half="$HALF" empty="$EMPTY"
	color=$(usage_color "$pct")
	for ((i = 0; i < ${#pattern}; i++)); do
		case "${pattern:i:1}" in
		F) expected+="${sep}${color}${filled}${C_RESET}" ;;
		H) expected+="${sep}${color}${half}${C_RESET}" ;;
		E) expected+="${sep}${empty}" ;;
		esac
		sep=" "
	done
	actual=$(format_context_bar "$pct")
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected: %q\n      actual: %q' "$expected" "$actual")"
}

# Byte-for-byte comparison that several expect_* helpers below reduce to: compute
# "actual", compare to "expected". Defined here, ahead of the "Whole line" section
# it conceptually belongs to, since some of those callers run earlier in the file.
expect_exact_line() {
	local desc="$1" actual="$2" expected="$3" ok=no
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected %q\n      actual: %q' "$expected" "$actual")"
}

# ── Load the renderer ─────────────────────────────────────────────────────────

# shellcheck source-path=SCRIPTDIR source=../scripts/statusline.sh
. "$SCRIPT" </dev/null

for required in format_context_bar usage_color; do
	require_function "$required"
done

# ── Glyph layout: 5 slots, space separated ───────────────────────────────────

printf "\n── Glyph layout ─────────────────────────────────────────────────────────────\n"
# The gauge carries no number of its own: the percentages belong to the limit segments.
# expect_glyphs compares against exact glyph strings below, so a stray "%" or digit would
# already fail those comparisons.
expect_glyphs "0%: all slots empty" 0 "○ ○ ○ ○ ○"
expect_glyphs "100%: all slots filled" 100 "● ● ● ● ●"
expect_glyphs "20%: exactly one slot filled" 20 "● ○ ○ ○ ○"

# ── Fractional slot rounding ─────────────────────────────────────────────────

printf "\n── Fractional slot rounding (three glyphs: ● ◎ ○) ────────────────────────────\n"
expect_bar "30% (1.50 slots): the partly-filled slot renders a gradient-colored ◎" 30 "FHEEE"
expect_bar "52% (2.60 slots): the partly-filled slot renders a gradient-colored ◎" 52 "FFHEE"

# The half and filled glyphs differ while both wear the gradient, so the rounding boundaries
# below still pin which glyph each fraction picks.
expect_bar "64% (3.20 slots): fraction below 0.25 renders empty" 64 "FFFEE"
expect_bar "65% (3.25 slots): fraction at 0.25 renders a gradient-colored half" 65 "FFFHE"
expect_bar "74% (3.70 slots): fraction below 0.75 renders a gradient-colored half" 74 "FFFHE"
expect_bar "75% (3.75 slots): fraction at 0.75 is promoted to filled" 75 "FFFFE"

# ── Gradient coloring ────────────────────────────────────────────────────────

printf "\n── Gradient coloring (filled and half; only empty uncolored) ─────────────────\n"
expect_bar "48%: the filled slots and the ◎ all wear the gradient" 48 "FFHEE"
expect_bar "95%: every filled slot wears the 95% gradient" 95 "FFFFF"

# ── Usage gradient helpers ───────────────────────────────────────────────────
#
# usage_color maps a percentage onto an HSL ramp and emits a truecolor escape:
#
#   0–50%   hue 50, saturation t² × 60, lightness 75 − t × 22   (t = pct/50)
#   50–100% hue 50 → 0, saturation 60 + t × 40, lightness 53 + t × 10
#           (t = (pct − 50)/50)
#
# The first half darkens as usage climbs: it starts at the lightness of ordinary terminal
# text and dims toward the 53% seam where the second half takes over.
#
# The script does the HSL → RGB conversion in integer arithmetic. `ref_rgb` is an
# independent floating-point oracle for the same formula, so the tests pin the
# ramp itself rather than whatever the integer implementation happens to produce.

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

# Splits usage_color's escape into "R G B". Leaves the raw escape intact when it
# does not match \033[38;2;R;G;Bm, so a malformed escape fails the caller loudly.
usage_rgb() {
	local body
	body=$(usage_color "$1")
	body=${body#$'\033'"[38;2;"}
	body=${body%m}
	printf '%s' "${body//;/ }"
}

expect_truecolor_escape() {
	local desc="$1" pct="$2" actual ok=no
	actual=$(usage_color "$pct")
	[[ "$actual" =~ ^$'\033'\[38\;2\;[0-9]+\;[0-9]+\;[0-9]+m$ ]] && ok=yes
	report "$desc" "$ok" "$(printf 'not a truecolor escape: %q' "$actual")"
}

# True when both channel values are numeric and no more than $limit apart.
# Shared by expect_matches_hsl_ref (per-pct tolerance) and expect_continuous_across
# (seam tolerance between adjacent pct values).
within_tolerance() {
	local got="$1" want="$2" limit="$3"
	[[ "$got" =~ ^[0-9]+$ && "$want" =~ ^[0-9]+$ ]] || return 1
	local diff=$((got > want ? got - want : want - got))
	((diff <= limit))
}

# True when all three channels are within $limit of their counterpart. Shared by
# expect_rgb and expect_continuous_across, which each keep their own report line.
rgb_within_tolerance() {
	local got_r="$1" got_g="$2" got_b="$3" want_r="$4" want_g="$5" want_b="$6" limit="$7"
	within_tolerance "$got_r" "$want_r" "$limit" || return 1
	within_tolerance "$got_g" "$want_g" "$limit" || return 1
	within_tolerance "$got_b" "$want_b" "$limit" || return 1
}

# The tolerance-comparison backend expect_matches_hsl_ref calls with the HSL
# reference's own R/G/B — not an independently-used exact anchor.
expect_rgb() {
	local desc="$1" pct="$2" want_r="$3" want_g="$4" want_b="$5" r g b ok=no
	read -r r g b <<<"$(usage_rgb "$pct")"
	rgb_within_tolerance "$r" "$g" "$b" "$want_r" "$want_g" "$want_b" 1 && ok=yes
	report "$desc" "$ok" "$(printf 'expected ~%s %s %s, got %s %s %s' "$want_r" "$want_g" "$want_b" "$r" "$g" "$b")"
}

expect_matches_hsl_ref() {
	local desc="$1" pct="$2" rr rg rb
	read -r rr rg rb <<<"$(ref_rgb "$pct")"
	expect_rgb "$desc" "$pct" "$rr" "$rg" "$rb"
}

# Gold means red leads green leads blue. Hue 60 would make red and green equal.
expect_gold_not_green() {
	local desc="$1" pct="$2" r g b ok=no
	read -r r g b <<<"$(usage_rgb "$pct")"
	[[ "$r" =~ ^[0-9]+$ && $r -gt $g && $g -gt $b ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected R > G > B, got %s %s %s' "$r" "$g" "$b")"
}

expect_pure_red_hue() {
	local desc="$1" pct="$2" r g b ok=no
	read -r r g b <<<"$(usage_rgb "$pct")"
	[[ "$r" == "255" && "$g" == "$b" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected R = 255 and G = B, got %s %s %s' "$r" "$g" "$b")"
}

# Direction of the red channel between two percentages: pass "rises" or "falls".
expect_red_direction() {
	local desc="$1" lo="$2" hi="$3" dir="$4" r_lo r_hi rest ok=no
	read -r r_lo rest <<<"$(usage_rgb "$lo")"
	read -r r_hi rest <<<"$(usage_rgb "$hi")"
	if [[ "$r_lo" =~ ^[0-9]+$ && "$r_hi" =~ ^[0-9]+$ ]]; then
		case "$dir" in
		rises) ((r_hi > r_lo)) && ok=yes ;;
		falls) ((r_hi < r_lo)) && ok=yes ;;
		esac
	fi
	report "$desc" "$ok" "$(printf 'R(%s) = %s, R(%s) = %s, expected it to have %s' "$lo" "$r_lo" "$hi" "$r_hi" "$dir")"
}

# The two ramp halves must meet without a visible seam at 50%.
expect_continuous_across() {
	local desc="$1" lo="$2" hi="$3" limit="$4" ok=no
	local r1 g1 b1 r2 g2 b2
	read -r r1 g1 b1 <<<"$(usage_rgb "$lo")"
	read -r r2 g2 b2 <<<"$(usage_rgb "$hi")"
	rgb_within_tolerance "$r1" "$g1" "$b1" "$r2" "$g2" "$b2" "$limit" && ok=yes
	report "$desc" "$ok" "$(printf '%s%% = %s %s %s, %s%% = %s %s %s' "$lo" "$r1" "$g1" "$b1" "$hi" "$r2" "$g2" "$b2")"
}

NOW=1700000000
# The default reset window for segment/pace tests below: a 5h window with 1h left.
PACE_WINDOW=$FIVE_HOUR_SECONDS
PACE_RESET=$((NOW + 3600))
# The 7d window's own reset window, mirrored below wherever a 7d countdown is needed.
WEEK_WINDOW=$SEVEN_DAY_SECONDS
WEEK_RESET=$((NOW + 200000))

# The label, the space, and the percentage form one gradient-colored span — no colon.
expect_segment_gradient() {
	local desc="$1" label="$2" pct="$3" color out want ok=no
	color=$(usage_color "$pct")
	out=$(format_limit_segment "$label" "$pct" "$PACE_RESET" "$PACE_WINDOW" "$NOW")
	want="${color}${label} ${pct}%"
	[[ "$out" == *"$want"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected to contain %q\n    actual: %q' "$want" "$out")"
}

# The segment's detail group is framed by a middle dot, never parentheses.
expect_no_parentheses() {
	local desc="$1" actual="$2" ok=no
	[[ "$actual" != *"("* && "$actual" != *")"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected no parentheses, got: %q' "$actual")"
}

# Everything from the ` · ` separator onward renders in the terminal's default foreground,
# so the countdown never competes with the usage color for attention.
expect_reset_uncolored() {
	local desc="$1" label="$2" pct="$3" reset_ts="$4" window="$5"
	local out tail ok=no
	out=$(format_limit_segment "$label" "$pct" "$reset_ts" "$window" "$NOW")
	tail=" · ${out##* · }"
	[[ "$out" == *" · "* && "$tail" != *$'\033'* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'reset text carries an escape: %q' "$tail")"
}

# ── Gradient escape shape ────────────────────────────────────────────────────

printf "\n── Gradient escape shape ────────────────────────────────────────────────────\n"
expect_truecolor_escape "50%: emits a truecolor escape" 50
expect_truecolor_escape "100%: emits a truecolor escape" 100

# ── Gradient matches the HSL ramp ────────────────────────────────────────────

printf "\n── Gradient matches the HSL ramp (integer math keeps precision) ──────────────\n"
for pct in 25 37 50 61 75 88 95 100; do
	expect_matches_hsl_ref "$pct%: within 1 per channel of the HSL reference" "$pct"
done
expect_continuous_across "49% → 50%: ramp halves meet without a seam" 49 50 5
expect_continuous_across "50% → 51%: ramp halves meet without a seam" 50 51 5

# ── Gradient anchors ─────────────────────────────────────────────────────────

printf "\n── Gradient anchors ─────────────────────────────────────────────────────────\n"
# Below the saturation threshold, usage_color returns empty so text inherits
# the terminal's native foreground — no truecolor escape emitted.
expect_empty_color() {
	local desc="$1" pct="$2" color ok=no
	color=$(usage_color "$pct")
	[[ -z "$color" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected empty, got %q' "$color")"
}
expect_empty_color "0%: no escape, inherits terminal default" 0
expect_empty_color "12%: still below saturation threshold" 12
expect_gold_not_green "50%: warm gold, R > G > B" 50
expect_pure_red_hue "100%: pure red hue, G = B at full saturation" 100
# Below 50% the ramp darkens as color emerges: the light base is the low-usage end, so the
# red channel dips before the second half drives it up to pure red.
expect_red_direction "red channel climbs from 25% to 50%" 25 50 rises
expect_red_direction "red channel climbs from 50% to 100%" 50 100 rises

# ── Limit segment coloring ───────────────────────────────────────────────────

printf "\n── Limit segment coloring ───────────────────────────────────────────────────\n"
expect_segment_gradient "61%: label, space, and 61%% all wear the gradient" "5h" 61
# Both percentages sit at or above the 75% threshold, so there is a countdown to check.
expect_reset_uncolored "5h countdown renders in the default foreground" "5h" 88 "$PACE_RESET" "$PACE_WINDOW"
expect_reset_uncolored "7d countdown renders in the default foreground" "7d" 80 "$WEEK_RESET" "$WEEK_WINDOW"

# ── Pace indicator ───────────────────────────────────────────────────────────
#
# format_pace compares usage against the share of the window already elapsed and
# renders an arrow for the gap:
#
#   delta <= -5    ↓   (under pace)
#   -5 < delta < 5  (nothing, on pace)
#   +5 .. +14      ↑   (over pace)
#   delta >= +15   ↑↑  (hot)
#
# Every case below uses a 5h window with 1h left (PACE_WINDOW/PACE_RESET), so 4h
# of 5h has elapsed and the on-pace usage is 80%. The `used` value therefore sets
# the delta directly.
#
# Which glyph appears is the arrow's own contract; all arrows inherit the segment's
# usage gradient, pinned by expect_arrow_color below.

expect_pace_glyph() {
	local desc="$1" used="$2" expected="$3" actual
	actual=$(format_pace "$used" "$PACE_RESET" "$PACE_WINDOW" "$NOW" | strip_ansi)
	expect_exact_line "$desc" "$actual" "$expected"
}

# The whole segment as plain text: pins glyph order and spacing — the leading separator,
# the space between label and percentage, the arrow hugging the `%`, and the ` · ` before
# the countdown — without restating any color. The segment carries its own " │ " prefix;
# main concatenates segments without inserting one.
expect_segment_plain() {
	local desc="$1" label="$2" used="$3" reset_ts="$4" window="$5" expected="$6" actual
	actual=$(format_limit_segment "$label" "$used" "$reset_ts" "$window" "$NOW" | strip_ansi)
	expect_exact_line "$desc" "$actual" "$expected"
}

# The last color escape standing before the arrow decides what color the arrow renders in:
# all pace arrows inherit the segment's usage gradient.
last_escape() {
	printf '%s' "$1" | grep -oE $'\033\\[[0-9;]*m' | tail -1 || true
}

expect_arrow_color() {
	local desc="$1" used="$2" arrow="$3"
	local color out head got ok=no
	color=$(usage_color "$used")
	out=$(format_limit_segment "5h" "$used" "$PACE_RESET" "$PACE_WINDOW" "$NOW")
	head=${out%%"$arrow"*}
	got=$(last_escape "$head")
	[[ "$out" == *"$arrow"* && "$got" == "$color" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'escape in force at the arrow: %q, expected %q\n      actual: %q' "$got" "$color" "$out")"
}

require_function format_pace

printf "\n── Pace arrow thresholds ────────────────────────────────────────────────────\n"
expect_pace_glyph "75% at 80%% pace (delta -5): down arrow at the boundary" 75 "↓"
expect_pace_glyph "76% at 80%% pace (delta -4): on pace, no arrow" 76 ""
expect_pace_glyph "84% at 80%% pace (delta +4): on pace, no arrow" 84 ""
expect_pace_glyph "85% at 80%% pace (delta +5): up arrow at the boundary" 85 "↑"
expect_pace_glyph "94% at 80%% pace (delta +14): up arrow" 94 "↑"
expect_pace_glyph "95% at 80%% pace (delta +15): double arrow at the boundary" 95 "↑↑"

# ── Pace arrow color ─────────────────────────────────────────────────────────
#
# All pace arrows inherit the segment's usage gradient.

printf "\n── Pace arrow color (all arrows inherit the gradient) ─────────────────────────\n"
expect_arrow_color "85%: the ↑ inherits the 85%% gradient" 85 "↑"
expect_arrow_color "100%: the ↑↑ inherits the 100%% gradient" 100 "↑↑"
expect_arrow_color "60%: the ↓ inherits the 60%% gradient" 60 "↓"

# ── Segment shape ────────────────────────────────────────────────────────────
#
# `<label> <pct>%<arrow> · <countdown>` — no colon, no parentheses, no space before the
# arrow. The countdown is appended when there is one to show *and* the window is worth
# watching: either usage has reached 75%, or the reset is under an hour away. Outside those
# two, the window has room to spare, so how long until it resets is noise and the
# percentage stands alone.

printf "\n── Segment shape (label pct%%arrow · countdown) ───────────────────────────────\n"
expect_segment_plain "over pace: the arrow hugs the percentage" "5h" 88 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 88%↑ · 1h"
expect_segment_plain "hot pace: the double arrow hugs the percentage" "5h" 100 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 100%↑↑ · 1h"
expect_segment_plain "on pace: countdown alone, no arrow" "5h" 82 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 82% · 1h"
expect_segment_plain "no countdown to show: nothing follows the percentage" "5h" 100 "$NOW" "$PACE_WINDOW" " │ 5h 100%"
# The 75% boundary, pinned from both sides. Both cases sit under pace, so the down arrow
# still hugs the percentage and the countdown is the only difference between them. Both
# resets are exactly an hour out — the far edge of the urgency window below — so the 74%
# case doubles as that window's closed side: an hour left is not yet imminent.
expect_segment_plain "74%: below the threshold, the down arrow hugs the percentage and no countdown follows" "5h" 74 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 74%↓"
expect_segment_plain "75%: at the threshold, the countdown appears" "5h" 75 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 75%↓ · 1h"
# Under an hour to go, the imminent reset is the news rather than the percentage, so the
# countdown comes back however far below 75% usage sits.
expect_segment_plain "60% with 45m left: an imminent reset brings the countdown back below the threshold" "5h" 60 "$((NOW + 45 * 60))" "$PACE_WINDOW" " │ 5h 60%↓ · 45m"
# Both windows render a countdown: the 7d segment prints "4d13h"-style output, matching the
# 5h segment's format.
expect_segment_plain "7d window counts down in days and hours" "7d" 80 "$((NOW + 4 * 86400 + 13 * 3600))" "$WEEK_WINDOW" " │ 7d 80%↑↑ · 4d13h"

# ── Reset countdown ──────────────────────────────────────────────────────────
#
# Both windows render a countdown, and the 7d window routinely has days left, so the
# format has a day unit above 24h: `4d13h`, dropping the hours when they are zero
# (`5d`) exactly as the sub-day form drops zero minutes (`2h`). Minutes are noise next to
# days, so they disappear once a day is on the clock.
#
# A reset that has already passed — or lands exactly on now — has nothing to count down,
# and renders as the empty string so the caller can leave the detail off entirely.

expect_countdown() {
	local desc="$1" seconds="$2" expected="$3" actual
	actual=$(format_countdown "$((NOW + seconds))" "$NOW")
	expect_exact_line "$desc" "$actual" "$expected"
}

printf "\n── Reset countdown ──────────────────────────────────────────────────────────\n"
expect_countdown "45m left: minutes alone" $((45 * 60)) "45m"
expect_countdown "2h left: zero minutes are dropped" $((2 * 3600)) "2h"
expect_countdown "2h10m left: hours and minutes" $((2 * 3600 + 10 * 60)) "2h10m"
expect_countdown "23h59m left: still below a day" $((23 * 3600 + 59 * 60)) "23h59m"
expect_countdown "exactly 24h left: a day with zero hours" $((24 * 3600)) "1d"
expect_countdown "4d13h left: days and hours" $((4 * 86400 + 13 * 3600)) "4d13h"
expect_countdown "59s left: reset is imminent, renders 0m rather than nothing" 59 "0m"
expect_countdown "reset lands on now: nothing to count down" 0 ""
expect_countdown "reset already passed: nothing to count down" -3600 ""

# ── Directory segment ────────────────────────────────────────────────────────
#
# The line opens with the working directory's basename, and whatever follows ⎇ (U+2387) names
# where the session sits in git: `proj ⎇ dash`. A session running in a git worktree carries
# `workspace.git_worktree`, and that name takes the slot instead — a worktree and its branch
# are nearly always the same word, so printing both would only repeat it. With neither name
# to show, the basename stands alone and the glyph goes with it rather than dangling.
#
# format_dir stays a pure formatter: the branch is resolved by the caller and handed in, so
# the cases below never need a repository on disk. That the caller resolves it from the real
# working directory is asserted end to end through main below.
#
# The whole segment stays in the terminal's default foreground — the glyph is a label, not a
# status — so the assertions below compare raw output rather than stripping escapes first: an
# escape anywhere in it fails the comparison.

require_function format_dir

expect_dir() {
	local desc="$1" dir="$2" worktree="$3" branch="$4" expected="$5" actual
	actual=$(format_dir "$dir" "$worktree" "$branch")
	expect_exact_line "$desc" "$actual" "$expected"
}

printf "\n── Directory segment (basename ⎇ branch or worktree) ─────────────────────────\n"
expect_dir "a branch and no worktree: the branch follows the basename, uncolored" "/tmp/statusline-proj" "" "dash" "statusline-proj ⎇ dash"
expect_dir "a worktree outranks the branch: one name after the glyph, never both" "/tmp/statusline-proj" "feature-x" "dash" "statusline-proj ⎇ feature-x"
expect_dir "neither branch nor worktree: the basename stands alone, no dangling glyph" "/tmp/statusline-proj" "" "" "statusline-proj"

# ── Whole line ───────────────────────────────────────────────────────────────
#
# main composes the pieces into the rendered status line. The usage payload is stubbed at
# the network boundary with the normalized shape fetch_usage_payload yields, so the line is
# deterministic; the resets sit a comfortable margin past their rendered minute so a second
# of wall-clock drift during the run cannot move the countdown.
#
# The two windows straddle the 75% countdown threshold — the 5h window is above it and the
# 7d window well below — so one composed line shows both a segment that carries a countdown
# and one that does not.

require_function main

MAIN_NOW=$(date +%s)
MAIN_PAYLOAD=$(printf '{"five_hour":{"used_percentage":78,"resets_at":%s},"seven_day":{"used_percentage":7,"resets_at":%s}}' \
	"$((MAIN_NOW + 4 * 3600 + 10 * 60 - 1))" "$((MAIN_NOW + 4 * 86400 + 13 * 3600 + 1800))")
CLEANUP_PATHS=()
trap 'rm -rf "${CLEANUP_PATHS[@]}"' EXIT

# All stdin fixtures below share this envelope; stdin_json merges in each fixture's
# distinguishing fields. context_window.used_percentage sits here rather than on any one
# fixture so every case renders a partially-filled gauge, exercising that field's wiring
# through main wherever the gauge is checked.
STDIN_ENVELOPE='{"hook_event_name":"Status","session_id":"statusline-test","transcript_path":"/tmp/statusline-transcript.jsonl","cwd":"/tmp/statusline-proj","version":"1.0.0","output_style":{"name":"default"},"context_window":{"used_percentage":45}}'
stdin_json() {
	jq -c --argjson extra "$1" '. * $extra' <<<"$STDIN_ENVELOPE"
}

# The model/workspace object shared by every fixture that carries a full, non-degraded
# model and workspace — merged in on top of STDIN_ENVELOPE rather than folded into it,
# since STDIN_ENVELOPE's `. * $extra` merge cannot remove keys: baking display_name and
# current_dir into the envelope would leak them back into STDIN_NO_NAMES and stop that
# fixture from testing degraded input.
STDIN_MODEL_WORKSPACE='{"model":{"id":"claude-opus-4-1","display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/statusline-proj","project_dir":"/tmp/statusline-proj"}}'
full_stdin_json() {
	jq -c --argjson base "$STDIN_MODEL_WORKSPACE" --argjson extra "$1" '. * $base * $extra' <<<"$STDIN_ENVELOPE"
}

MAIN_STDIN=$(full_stdin_json '{}')

# main reaches the stubbed fetch_usage_payload through fetch_usage_fallback, whose
# cache lives under TMPDIR keyed on CLAUDE_CONFIG_DIR — so both are pointed at a
# private directory. Otherwise the run reads the user's live cache (nondeterministic)
# or overwrites it with the stub payload. Each case gets its own cache directory
# under here and its own stderr file inside it, for the same reason.
MAIN_CASES=$(mktemp -d "${TMPDIR:-/tmp}/statusline-cases.XXXXXX")
CLEANUP_PATHS+=("$MAIN_CASES")

# Renders main in a per-case cache directory with the network boundary stubbed, so no
# case can read or overwrite the user's live usage cache. `payload` is what the stubbed
# fetch serves; empty means the fetch fails and no usage data reaches the line. stderr
# is collected in the case's own directory, so cases sharing MAIN_CASES never race on
# one shared file.
main_render() {
	local case_name="$1" stdin_json="$2" stub_payload="${3-}" dir
	dir="$MAIN_CASES/$case_name"
	mkdir -p "$dir"
	(
		# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: isolation must not leak out
		export TMPDIR="$dir" CLAUDE_CONFIG_DIR="$dir"
		if [[ -n "$stub_payload" ]]; then
			fetch_usage_payload() { printf '%s' "$stub_payload"; }
		else
			fetch_usage_payload() { return 1; }
		fi
		printf '%s' "$stdin_json" | main
	) 2>"$dir/stderr"
}

main_line() {
	main_render happy-path "$MAIN_STDIN" "$MAIN_PAYLOAD"
}

expect_line_contains() {
	local desc="$1" haystack="$2" needle="$3" ok=no
	[[ "$haystack" == *"$needle"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected to contain %q\n      actual: %q' "$needle" "$haystack")"
}

# The gauge runs straight into the next separator: no percentage stands between them.
expect_gauge_meets_separator() {
	local desc="$1" plain="$2" ok=no
	[[ "$plain" == *"$EMPTY │"* || "$plain" == *"$FILLED │"* || "$plain" == *"$HALF │"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'no gauge glyph directly before a separator: %q' "$plain")"
}

MAIN_OUT=$(main_line)
MAIN_PLAIN=$(printf '%s' "$MAIN_OUT" | strip_ansi)

printf "\n── Whole line ───────────────────────────────────────────────────────────────\n"
expect_gauge_meets_separator "the context gauge is followed by the separator, not a percentage" "$MAIN_PLAIN"
expect_line_contains "context_window.used_percentage reaches the gauge, which partially fills" "$MAIN_PLAIN" "Opus 4.6 ● ● ◎ ○ ○ │"
expect_line_contains "the 5h segment renders as label, percentage, arrow, countdown" "$MAIN_PLAIN" "│ 5h 78%↑↑ · 4h9m │"
# The trailing segment, taken whole: nothing follows the percentage, so the 7d window's
# days-away reset stays off the line while it is below the threshold.
expect_exact_line "the 7d segment is below the threshold, so no countdown trails the line" "${MAIN_PLAIN##*│ }" "7d 7%"
expect_no_parentheses "the whole line frames details with · , not parentheses" "$MAIN_PLAIN"

expect_leading_segment() {
	local desc="$1" plain="$2" expected="$3"
	expect_exact_line "$desc" "${plain%% │ *}" "$expected"
}

expect_leading_segment "no workspace.git_worktree: the basename stands alone" "$MAIN_PLAIN" "statusline-proj"

MAIN_STDIN_WORKTREE=$(full_stdin_json '{"workspace":{"git_worktree":"feature-x"}}')
expect_leading_segment "workspace.git_worktree reaches the line beside the basename" \
	"$(main_render worktree "$MAIN_STDIN_WORKTREE" "$MAIN_PAYLOAD" | strip_ansi)" \
	"statusline-proj ⎇ feature-x"

# The branch is git's own answer for workspace.current_dir, not a field on stdin, so this
# case needs a repository on disk: a fresh repo on a known branch with current_dir pointed
# at it. No commit is needed — `git branch --show-current` names an unborn branch too.
# Every other main case points current_dir at a path that is no repository at all, so the
# leading segments they assert also pin that a directory with no branch keeps its bare
# basename.
BRANCH_REPO="$MAIN_CASES/branch-repo"
git init -q -b tdd-branch "$BRANCH_REPO"
MAIN_STDIN_BRANCH=$(full_stdin_json "$(printf '{"workspace":{"current_dir":"%s"}}' "$BRANCH_REPO")")
expect_leading_segment "the branch of workspace.current_dir reaches the line beside the basename" \
	"$(main_render branch "$MAIN_STDIN_BRANCH" "$MAIN_PAYLOAD" | strip_ansi)" \
	"branch-repo ⎇ tdd-branch"

MAIN_STDIN_EFFORT=$(full_stdin_json '{"effort":{"level":"high"}}')
expect_line_contains "effort.level is appended to the model name in parentheses" \
	"$(main_render effort "$MAIN_STDIN_EFFORT" "$MAIN_PAYLOAD" | strip_ansi)" \
	"Opus 4.6 (high)"

# ── Degraded input ───────────────────────────────────────────────────────────
#
# Claude Code does not promise every field on every event. A model without a display
# name or a workspace without a current dir leaves that slot empty — never the JSON
# null spelled out as the four-letter word "null", which is what `tostring` yields for
# an absent field.
#
# An unparseable rate-limits payload is the same kind of surprise with one difference:
# it is worth saying out loud. A silently empty segment list is indistinguishable from
# "there were no limits to show", so the failure goes to stderr the way a failed stdin
# parse already does, and the rest of the line still renders.

# A field that renders as the literal "null" would slip past a mere emptiness check on
# one slot, so this scans the whole line instead.
expect_no_literal_null() {
	local desc="$1" actual="$2" ok=no
	[[ "$actual" != *"null"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected no literal "null", got: %q' "$actual")"
}

# shellcheck disable=SC2031 # main_render's TMPDIR change is subshell-local; ambient TMPDIR is intact here
STDIN_NO_NAMES=$(stdin_json '{"model":{"id":"claude-opus-4-1"},"workspace":{"project_dir":"/tmp/statusline-proj"}}')
# Valid stdin carrying an invalid rate-limits payload: the string parses, its contents do not.
STDIN_BAD_LIMITS=$(full_stdin_json '{"rate_limits":"{not json","cost":{"total_api_duration_ms":100}}')

printf "\n── Degraded input ───────────────────────────────────────────────────────────\n"
NO_NAMES_LINE=$(main_render no-names "$STDIN_NO_NAMES" "$MAIN_PAYLOAD" | strip_ansi)
expect_leading_segment "a stdin without workspace.current_dir leaves the leading segment empty" "$NO_NAMES_LINE" ""
expect_no_literal_null "a stdin without model.display_name or workspace.current_dir never renders the literal \"null\"" "$NO_NAMES_LINE"

BAD_LIMITS_LINE=$(main_render bad-limits "$STDIN_BAD_LIMITS" | strip_ansi)
BAD_LIMITS_ERR=$(<"$MAIN_CASES/bad-limits/stderr")
expect_line_contains "an unparseable rate-limits payload leaves the rest of the line rendering" "$BAD_LIMITS_LINE" "Opus 4.6"
expect_line_contains "an unparseable rate-limits payload is reported on stderr" "$BAD_LIMITS_ERR" "rate-limit parse failed"

# stdin that jq cannot walk — not JSON at all, or JSON whose fields carry the wrong type —
# fails the batched extraction that every other field on the line comes from. Printing
# nothing is the one outcome the user cannot read: the statusline goes blank, which is
# exactly what a working render with nothing to say looks like. The failure has to reach
# the line itself, and it only gets there if the host renders what the script printed —
# so the script leaves with a success status carrying the degraded line, not a bare
# failure the host drops on the floor.
#
# expect_degraded_render is the shared backend for every "still renders" case below,
# including the missing- and unusable-tool cases further down: run the given render
# command, then check both that its stdout names the failure and that its exit status
# stays 0 so the host does not drop the line on the floor.
expect_degraded_render() {
	local desc="$1" expected="$2" status=0 out
	shift 2
	out=$("$@") || status=$?
	expect_exact_line "$desc: the line reports the failure instead of rendering blank" \
		"$(printf '%s' "$out" | strip_ansi)" "$expected"
	expect_exact_line "$desc: the exit status keeps the line renderable" "$status" "0"
}

expect_degraded_render "stdin jq cannot walk" "statusline: stdin parse failed" \
	main_render broken-stdin 'not json at all'

# ── Missing or unusable tools ────────────────────────────────────────────────
#
# The host renders the statusline from what the script prints, and discards the output of
# a command that exited non-zero. A dependency check that only writes to stderr and
# returns 1 therefore reaches the user as a blank line — indistinguishable from a healthy
# render with nothing to say. Every environment failure leaves by the same door the stdin
# parse failure already uses: a named line on stdout under a success status, naming the
# tool that is missing so the user knows what to install.
#
# `stat` is the one tool no `command -v` can vet, since what breaks is not its absence but
# its options: a non-BSD stat is on PATH and answers, just not the way file_mtime asked.
# It surfaces at the point of use instead — and only where the file it was asked about
# exists. An absent lock or marker is an ordinary condition on every platform, so a
# missing file stays the silent fallback it already is; only a stat that cannot run at all
# is worth a line.

# Renders main with one required tool taken off PATH. The case's bin directory holds a
# symlink to every other required tool and is the entire PATH, so nothing else on the
# system can supply the missing one. check_deps runs before main touches any of them, so
# the render never needs more than this.
missing_dep_render() {
	local missing="$1" tool path dir
	dir="$MAIN_CASES/missing-$missing"
	mkdir -p "$dir/bin"
	for tool in jq curl security shasum date stat; do
		if [[ "$tool" != "$missing" ]] && path=$(command -v "$tool"); then
			ln -sf "$path" "$dir/bin/$tool"
		fi
	done
	(
		# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: the narrowed PATH must not leak out
		export PATH="$dir/bin" TMPDIR="$dir" CLAUDE_CONFIG_DIR="$dir"
		fetch_usage_payload() { printf '%s' "$MAIN_PAYLOAD"; }
		printf '%s' "$MAIN_STDIN" | main
	) 2>"$dir/stderr"
}

expect_missing_dep_reported() {
	local tool="$1"
	expect_degraded_render "a missing $tool" "statusline: missing required tool: $tool" \
		missing_dep_render "$tool"
}

# Prepends a `stat` that always fails to PATH — the stand-in for a stat whose options this
# platform does not accept — leaving every other tool the render needs real.
unusable_stat_render() {
	local case_name="$1" dir
	dir="$MAIN_CASES/$case_name"
	mkdir -p "$dir/bin"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$dir/bin/stat"
	chmod +x "$dir/bin/stat"
	(
		# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: the stub must not leak out
		export PATH="$dir/bin:$PATH"
		main_render "$case_name" "$MAIN_STDIN" "$MAIN_PAYLOAD"
	)
}

printf "\n── Missing or unusable tools ────────────────────────────────────────────────\n"
# Two tools, so the line has to carry the name of the one that is actually missing rather
# than a single blanket message.
expect_missing_dep_reported jq
expect_missing_dep_reported shasum

# Nothing has run in this case's cache directory, so the marker whose mtime the render
# reads does not exist — the ordinary condition, which the render absorbs in silence.
expect_line_contains "an unusable stat with no marker to read: the ordinary line still renders" \
	"$(unusable_stat_render stat-absent | strip_ansi)" "Opus 4.6 ● ● ◎ ○ ○ │"

# Seeded with one ordinary render, so the marker exists and this render's stat failure is
# the tool's doing, not the file's.
main_render stat-present "$MAIN_STDIN" "$MAIN_PAYLOAD" >/dev/null
expect_degraded_render "an unusable stat with a marker to read" "statusline: unusable required tool: stat" \
	unusable_stat_render stat-present

# ── Usage fallback fetch ─────────────────────────────────────────────────────
#
# fetch_usage_fallback polls the OAuth usage endpoint when Claude Code's stdin
# carries no .rate_limits. That endpoint enforces a strict shared rate budget, so
# the function throttles itself: one attempt per 300s after a success, and a
# longer 900s backoff after a failure, giving the endpoint room to recover.
#
# Between attempts the last successful payload is the statusline's only data, so
# no failure may discard it — not a curl error, not a non-JSON body, and not a
# JSON body without .five_hour.utilization, which is the shape the endpoint
# returns once it starts rate-limiting.
#
# curl and security are stubbed with shims on PATH; TMPDIR and CLAUDE_CONFIG_DIR
# point at a per-case directory, so each scenario owns its cache. Elapsed time is
# driven by the `now` argument, offset from the real clock that the cache files
# themselves carry. The offsets stay well clear of the 300s and 900s boundaries
# so that a second of wall-clock drift during the run cannot flip a verdict.

require_function fetch_usage_fallback

# shellcheck disable=SC2031 # main_render's TMPDIR change is subshell-local; ambient TMPDIR is intact here
FALLBACK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statusline-fallback.XXXXXX")
CLEANUP_PATHS+=("$FALLBACK_ROOT")

# The endpoint's own shape: utilization percentages and ISO-8601 reset stamps.
USAGE_BODY='{"five_hour":{"utilization":42,"resets_at":"2023-11-14T22:13:20Z"},"seven_day":{"utilization":13,"resets_at":"2023-11-20T22:13:20Z"}}'
FIVE_HOUR_RESET_EPOCH=1700000000
# What the endpoint answers with once the shared budget is spent: no utilization.
RATE_LIMITED_BODY='{"error":{"type":"rate_limit_error","message":"rate limit exceeded"}}'
NOT_JSON_BODY='<html>429 Too Many Requests</html>'

# Creates an isolated case directory holding the curl/security shims, the attempt
# log, and its own TMPDIR for the cache.
fallback_case() {
	local dir="$FALLBACK_ROOT/$1"
	mkdir -p "$dir/bin" "$dir/tmp"
	: >"$dir/attempts"
	cat >"$dir/bin/curl" <<-'SHIM'
		#!/usr/bin/env bash
		printf 'attempt\n' >>"$STUB_ATTEMPTS"
		code=$(cat "$STUB_CURL_EXIT")
		((code == 0)) || exit "$code"
		cat "$STUB_CURL_BODY"
	SHIM
	cat >"$dir/bin/security" <<-'SHIM'
		#!/usr/bin/env bash
		printf '%s\n' '{"claudeAiOauth":{"accessToken":"stub-token"}}'
	SHIM
	chmod +x "$dir/bin/curl" "$dir/bin/security"
}

# Calls the function against a case's stubs and prints whatever it emits. A
# curl_exit of 0 serves `body`; any other value makes the curl stub fail with
# that status without emitting anything, as a transport error would.
fallback_fetch() {
	local dir="$FALLBACK_ROOT/$1" curl_exit="$2" body="$3" now="$4"
	printf '%s' "$body" >"$dir/body"
	printf '%s' "$curl_exit" >"$dir/curl-exit"
	(
		# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: each case owns its cache
		export PATH="$dir/bin:$PATH" TMPDIR="$dir/tmp" CLAUDE_CONFIG_DIR="$dir"
		export STUB_ATTEMPTS="$dir/attempts" STUB_CURL_BODY="$dir/body" STUB_CURL_EXIT="$dir/curl-exit"
		fetch_usage_fallback "$now"
	) || true
}

expect_fallback_json() {
	local desc="$1" payload="$2" filter="$3" want="$4" got ok=no
	got=$(printf '%s' "$payload" | jq -r "$filter" 2>/dev/null) || got="<not JSON>"
	[[ "$got" == "$want" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected %s = %q, got %q\n      payload: %q' "$filter" "$want" "$got" "$payload")"
}

expect_attempts() {
	local desc="$1" case_name="$2" want="$3" got ok=no
	got=$(awk 'END {print NR}' <"$FALLBACK_ROOT/$case_name/attempts")
	[[ "$got" == "$want" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected %s endpoint attempt(s), got %s' "$want" "$got")"
}

# Creates a case and seeds it with one successful fetch at FB_BASE, establishing
# the "last good payload" a subsequent failure in that case must not discard.
seed_good_cache() {
	local case_name="$1"
	fallback_case "$case_name"
	fallback_fetch "$case_name" 0 "$USAGE_BODY" "$FB_BASE" >/dev/null
}

FB_BASE=$(date +%s)

printf "\n── Usage fallback: 300s throttle between attempts ────────────────────────────\n"
fallback_case throttle
fb_out=$(fallback_fetch throttle 0 "$USAGE_BODY" "$FB_BASE")
expect_attempts "first call reaches the endpoint" throttle 1
expect_fallback_json "first call maps utilization onto used_percentage" "$fb_out" '.five_hour.used_percentage' 42
expect_fallback_json "first call converts resets_at to epoch seconds" "$fb_out" '.five_hour.resets_at' "$FIVE_HOUR_RESET_EPOCH"
expect_fallback_json "first call maps the 7d window too" "$fb_out" '.seven_day.used_percentage' 13

fb_out=$(fallback_fetch throttle 0 "$USAGE_BODY" $((FB_BASE + 250)))
expect_attempts "250s after a success: no request, the window is 300s not 60s" throttle 1
expect_fallback_json "250s after a success: the cached payload is served" "$fb_out" '.five_hour.used_percentage' 42

fallback_fetch throttle 0 "$USAGE_BODY" $((FB_BASE + 400)) >/dev/null
expect_attempts "400s after a success: the 300s window expired, request sent" throttle 2

printf "\n── Usage fallback: failures keep the last good payload ───────────────────────\n"
seed_good_cache curl-failure

fb_out=$(fallback_fetch curl-failure 7 "" $((FB_BASE + 400)))
expect_attempts "curl error: the request was attempted" curl-failure 2
expect_fallback_json "curl error: the last good payload is still served" "$fb_out" '.five_hour.used_percentage' 42

fb_out=$(fallback_fetch curl-failure 7 "" $((FB_BASE + 800)))
expect_attempts "800s after a failure: still backing off, no request" curl-failure 2
expect_fallback_json "800s after a failure: the cache still holds the good payload" "$fb_out" '.five_hour.used_percentage' 42

fallback_fetch curl-failure 7 "" $((FB_BASE + 1000)) >/dev/null
expect_attempts "1000s after a failure: the 900s backoff expired, request sent" curl-failure 3

printf "\n── Usage fallback: error bodies are failures, not data ───────────────────────\n"
seed_good_cache rate-limited

fb_out=$(fallback_fetch rate-limited 0 "$RATE_LIMITED_BODY" $((FB_BASE + 400)))
expect_fallback_json "body without .five_hour.utilization: good payload served, not null" "$fb_out" '.five_hour.used_percentage' 42

fb_out=$(fallback_fetch rate-limited 0 "$USAGE_BODY" $((FB_BASE + 800)))
expect_attempts "error body counts as a failed attempt: backing off 800s later" rate-limited 2
expect_fallback_json "error body never reaches the cache" "$fb_out" '.five_hour.used_percentage' 42

seed_good_cache not-json

fb_out=$(fallback_fetch not-json 0 "$NOT_JSON_BODY" $((FB_BASE + 400)))
expect_fallback_json "non-JSON body: the last good payload is still served" "$fb_out" '.five_hour.used_percentage' 42

# ── Usage fallback: the lock keeps concurrent renders from double-fetching ─────
#
# Renders overlap — two windows repaint at once, both see the throttle window open at
# the same time. The lock is what keeps only one of them fetching: a render that loses
# the race falls through without touching the network, still serving whatever the cache
# already holds rather than blanking the segment. Once the in-flight fetch completes, its
# own fresh payload lands in the cache.
#
# Driven directly against refresh_usage_cache rather than through fetch_usage_fallback:
# the outer throttle can't isolate this race on its own terms. The in-flight writer's
# marker write happens the same wall-clock second as the lock's own mkdir (the write
# follows the mkdir immediately, before the fetch even starts), so a second
# fetch_usage_fallback call reading that marker would see the same age the reclaim
# check sees on the lock -- clearing the throttle always also clears the reclaim, so a
# racing call can never observe "window open, lock still fresh" through that path.
# refresh_usage_cache is called from fetch_usage_fallback only, but it is what the
# lock actually lives in, and only a direct call can hold the throttle constant while
# still exercising the mkdir race.

require_function refresh_usage_cache

# Waits for $path to appear and be non-empty, bounded so a stuck race fails the test
# instead of hanging the suite.
wait_for_file() {
	local path="$1" tries=0
	until [[ -s "$path" ]]; do
		((++tries < 100)) || return 1
		sleep 0.05
	done
}

FRESH_USAGE_BODY='{"five_hour":{"utilization":55,"resets_at":"2023-11-14T22:13:20Z"},"seven_day":{"utilization":13,"resets_at":"2023-11-20T22:13:20Z"}}'

# Calls refresh_usage_cache against the concurrent case's stubs, isolated in a subshell
# so each racer's PATH/RACE_* exports never leak into the other.
concurrent_refresh() {
	# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: each racer owns its own env
	export PATH="$FALLBACK_ROOT/concurrent/bin:$PATH"
	# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: each racer owns its own env
	export RACE_ATTEMPTS="$FALLBACK_ROOT/concurrent/attempts" RACE_CURL_BODY="$FALLBACK_ROOT/concurrent/body" RACE_CURL_EXIT="$FALLBACK_ROOT/concurrent/curl-exit"
	# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: each racer owns its own env
	export RACE_RELEASE="$FALLBACK_ROOT/concurrent/release"
	refresh_usage_cache concurrent "$concurrent_cache" "$concurrent_marker" "$USAGE_BACKOFF_SECONDS" "$(date +%s)"
}

printf "\n── Usage fallback: the lock keeps concurrent renders from double-fetching ─────\n"
seed_good_cache concurrent
concurrent_cache=$(compgen -G "$FALLBACK_ROOT/concurrent/tmp/claude-statusline-usage-*.json")
concurrent_marker="${concurrent_cache}.attempt"

# Blocks the curl stub on a release file for the first invocation only, so the
# in-flight fetch below holds its lock open long enough for a genuinely concurrent
# second call to race it. A second invocation (only possible if the lock fails to
# hold it out) answers immediately instead of blocking too, so a broken lock fails
# the attempt-count assertion below rather than deadlocking the suite.
cat >"$FALLBACK_ROOT/concurrent/bin/curl" <<-'SHIM'
	#!/usr/bin/env bash
	printf 'attempt\n' >>"$RACE_ATTEMPTS"
	if [[ $(wc -l <"$RACE_ATTEMPTS") -eq 1 ]]; then
		until [[ -f "$RACE_RELEASE" ]]; do sleep 0.05; done
	fi
	code=$(cat "$RACE_CURL_EXIT")
	((code == 0)) || exit "$code"
	cat "$RACE_CURL_BODY"
SHIM
chmod +x "$FALLBACK_ROOT/concurrent/bin/curl"
: >"$FALLBACK_ROOT/concurrent/attempts"
rm -f "$FALLBACK_ROOT/concurrent/release"
printf '%s' "$FRESH_USAGE_BODY" >"$FALLBACK_ROOT/concurrent/body"
printf '0' >"$FALLBACK_ROOT/concurrent/curl-exit"

(concurrent_refresh) &
first_pid=$!

wait_for_file "$FALLBACK_ROOT/concurrent/attempts" || {
	printf "\nFAIL  the in-flight fetch never registered its attempt\n"
	exit 1
}

(concurrent_refresh)
expect_attempts "a render racing an in-flight fetch sees the lock held, no request sent" concurrent 1
second_out=$(cat "$concurrent_cache")
expect_fallback_json "the locked-out render still serves the stale cache, not a blank segment" "$second_out" '.five_hour.used_percentage' 42

touch "$FALLBACK_ROOT/concurrent/release"
wait "$first_pid"
first_out=$(cat "$concurrent_cache")
expect_fallback_json "the in-flight render lands the fresh payload once its own fetch completes" "$first_out" '.five_hour.used_percentage' 55

# ── Usage fallback: the lock belongs to a render, not to a path ────────────────
#
# A render can stall long enough for its lock to look abandoned — the machine sleeps, the
# endpoint hangs — so a later render is allowed to reclaim it. From that moment the lock at
# that path belongs to the reclaimer, and the stalled render owns nothing. Every operation
# on the lock therefore has to name whose lock it is acting on: a release that only knows
# the path frees a lock somebody else is fetching under, and a reclaim that only knows the
# path evicts whoever happens to be standing there when it arrives.
#
# The cases below drive refresh_usage_cache directly, the way the concurrency case above
# does, and extend its curl stub: every render exports its own RACE_ID, so the attempt log
# names who reached the network, and a render started with a hold file blocks inside curl
# until that file appears — holding its lock open for exactly as long as the scenario needs.
# Staleness is forced by backdating the lock rather than by waiting out a threshold, so the
# cases stay deterministic and finish in milliseconds.

RECLAIM_DIR="$FALLBACK_ROOT/reclaim"
RECLAIM_TMP="$RECLAIM_DIR/tmp"
RECLAIM_ATTEMPTS="$RECLAIM_DIR/attempts"
# Far enough back that any staleness threshold counts the lock abandoned.
STALE_STAMP=202001010000

seed_good_cache reclaim
reclaim_cache=$(compgen -G "$RECLAIM_TMP/claude-statusline-usage-*.json")
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

# Runs one render under this case's stubs. A non-empty `hold` makes its fetch block until
# release_render names it. TMPDIR points at the case's cache directory so that any scratch
# directory the refresh creates lands where expect_no_stray_dirs can see it.
reclaim_refresh() {
	local id="$1" hold="${2-}"
	# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: each render owns its own env
	export PATH="$RECLAIM_DIR/bin:$PATH" TMPDIR="$RECLAIM_TMP"
	# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: each render owns its own env
	export RACE_ID="$id" RACE_ATTEMPTS="$RECLAIM_ATTEMPTS" RACE_CURL_BODY="$RECLAIM_DIR/body" RACE_CURL_EXIT="$RECLAIM_DIR/curl-exit"
	# shellcheck disable=SC2030,SC2031 # subshell-local on purpose: each render owns its own env
	[[ -z "$hold" ]] || export RACE_HOLD="$RECLAIM_DIR/release.$id"
	refresh_usage_cache reclaim "$reclaim_cache" "$reclaim_marker" "$USAGE_BACKOFF_SECONDS" "$(date +%s)"
}

# Runs a render to completion. Backgrounding it keeps the caller's `||` off the function,
# so errexit stays live inside refresh_usage_cache the way it is for a direct call —
# fetch_usage_fallback's own `|| true` is not around to mask a failed write.
run_render() {
	local pid
	(reclaim_refresh "$1") &
	pid=$!
	wait "$pid" || return 0
}

release_render() {
	touch "$RECLAIM_DIR/release.$1"
}

# Waits for a named render to reach the network, bounded so a render that never gets there
# fails the test instead of hanging the suite.
wait_for_attempt() {
	local id="$1" tries=0
	until grep -qx "$id" "$RECLAIM_ATTEMPTS"; do
		((++tries < 200)) || return 1
		sleep 0.05
	done
}

require_stalled_render() {
	wait_for_attempt "$1" || {
		printf "\nFAIL  render %s never reached its fetch\n" "$1"
		exit 1
	}
}

# Backdates the lock the in-flight render is holding, so the next render finds it
# abandoned. The lock is found rather than named: it is the only directory a refresh
# leaves in the cache directory, and the tests have no business knowing its path.
make_lock_stale() {
	local lock
	lock=$(find "$RECLAIM_TMP" -mindepth 1 -maxdepth 1 -type d)
	[[ -n "$lock" && "$lock" != *$'\n'* ]] || {
		printf "\nFAIL  expected exactly one lock directory under the cache dir, found: %q\n" "$lock"
		exit 1
	}
	# Depth-first, so the lock directory itself is stamped after its contents: touching a
	# child would otherwise bump the parent's mtime back to now.
	find "$lock" -depth -exec touch -t "$STALE_STAMP" {} +
}

expect_fetched() {
	local desc="$1" id="$2" ok=no
	grep -qx "$id" "$RECLAIM_ATTEMPTS" && ok=yes
	report "$desc" "$ok" "$(printf 'no attempt logged for %s\n      attempts: %s' "$id" "$(tr '\n' ' ' <"$RECLAIM_ATTEMPTS")")"
}

expect_not_fetched() {
	local desc="$1" id="$2" ok=no
	grep -qx "$id" "$RECLAIM_ATTEMPTS" || ok=yes
	report "$desc" "$ok" "$(printf '%s reached the network\n      attempts: %s' "$id" "$(tr '\n' ' ' <"$RECLAIM_ATTEMPTS")")"
}

expect_no_stray_dirs() {
	local desc="$1" leftovers ok=no
	leftovers=$(find "$RECLAIM_TMP" -mindepth 1 -type d)
	[[ -z "$leftovers" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'directories left behind in TMPDIR:\n      %s' "$(printf '%s' "$leftovers" | tr '\n' ' ')")"
}

printf "\n── Usage fallback: the lock belongs to a render, not to a path ───────────────\n"

(reclaim_refresh stalled hold) &
stalled_pid=$!
require_stalled_render stalled

make_lock_stale
(reclaim_refresh reclaimer hold) &
reclaimer_pid=$!
require_stalled_render reclaimer

run_render bystander
expect_not_fetched "the reclaimer's own lock holds the next render out, so no second fetch runs" bystander

release_render stalled
wait "$stalled_pid" || true
run_render late
expect_not_fetched "the reclaimed render frees nothing: the reclaimer's lock still stands after it exits" late

release_render reclaimer
wait "$reclaimer_pid" || true

expect_no_stray_dirs "the first reclaim cycle leaves no directory behind in TMPDIR"

# ── Usage fallback: reclaiming a stale lock leaves no debris ──────────────────
#
# usage_lock_reclaim takes the stale lock over in place (rmdir then mkdir on the same
# path) rather than staging it under a separate directory, so nothing pid-keyed is ever
# created for a reclaim. Two reclaim cycles from this one test process therefore have to
# end with the cache directory holding no extra directories at all — that is what
# expect_no_stray_dirs checks below.

(reclaim_refresh stalled-again hold) &
stalled_again_pid=$!
require_stalled_render stalled-again

make_lock_stale
(reclaim_refresh reclaimer-again hold) &
reclaimer_again_pid=$!
require_stalled_render reclaimer-again

release_render stalled-again
wait "$stalled_again_pid" || true
release_render reclaimer-again
wait "$reclaimer_again_pid" || true

printf "\n── Usage fallback: reclaiming a stale lock leaves no debris ──────────────────\n"
expect_no_stray_dirs "two reclaims from one process leave no directory behind in TMPDIR"

# ── Usage fallback: a failed write still frees the lock ──────────────────────
#
# Between taking the lock and giving it back, refresh_usage_cache writes. Those writes fail
# for reasons the statusline does not control — a full disk, a TMPDIR the user cannot write.
# With errexit live and no caller's `|| true` to soften it, a failed write ends the function
# where it stands, and a lock that outlives its holder blocks every later render until the
# staleness window runs out. Pointing the marker path at a directory makes every write to it
# fail without touching anything else the refresh depends on.

rm -f "$reclaim_marker"
mkdir "$reclaim_marker"
run_render write-fails
rmdir "$reclaim_marker"

printf "\n── Usage fallback: a failed write still frees the lock ───────────────────────\n"
run_render after-write-failure
expect_fetched "a render whose write failed leaves the lock free for the next one" after-write-failure

# ── Summary ──────────────────────────────────────────────────────────────────

printf "\n─────────────────────────────────────────────────────────────────────────────\n"
printf "%d passed, %d failed\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
