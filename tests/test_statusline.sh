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
	color=$(usage_color "$pct")
	for ((i = 0; i < ${#pattern}; i++)); do
		case "${pattern:i:1}" in
		F) expected+="${sep}${color}${FILLED}${C_RESET}" ;;
		H) expected+="${sep}${color}${HALF}${C_RESET}" ;;
		E) expected+="${sep}${EMPTY}" ;;
		*)
			printf "FAIL  %s\n    unknown slot code %q in pattern %q\n" "$desc" "${pattern:i:1}" "$pattern"
			((++FAIL))
			return
			;;
		esac
		sep=" "
	done
	actual=$(format_context_bar "$pct")
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected: %q\n      actual: %q' "$expected" "$actual")"
}

# Every ● in the bar must wear the gradient: strip the colored-filled form, and no bare ●
# may remain.
expect_every_filled_colored() {
	local desc="$1" pct="$2" color rest ok=no
	color=$(usage_color "$pct")
	rest=$(format_context_bar "$pct")
	while [[ "$rest" == *"${color}${FILLED}${C_RESET}"* ]]; do
		rest="${rest/"${color}${FILLED}${C_RESET}"/}"
	done
	[[ "$rest" != *"$FILLED"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'uncolored %s left after stripping colored ones: %q' "$FILLED" "$rest")"
}

# ── Load the renderer ─────────────────────────────────────────────────────────

# shellcheck source-path=SCRIPTDIR source=../scripts/statusline.sh
source "$SCRIPT" </dev/null

for required in format_context_bar usage_color; do
	require_function "$required"
done

# ── Glyph layout: 5 slots, space separated ───────────────────────────────────

printf "\n── Glyph layout ─────────────────────────────────────────────────────────────\n"
expect_glyphs "0%: all slots empty" 0 "○ ○ ○ ○ ○"
expect_glyphs "100%: all slots filled" 100 "● ● ● ● ●"
expect_glyphs "20%: exactly one slot filled" 20 "● ○ ○ ○ ○"

# The gauge carries no number of its own: the percentages belong to the limit segments.
expect_no_percent_sign() {
	local desc="$1" pct="$2" actual ok=no
	actual=$(format_context_bar "$pct" | strip_ansi)
	[[ "$actual" != *"%"* && "$actual" != *"$pct"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected glyphs only, got: %q' "$actual")"
}

for pct in 0 45 67 100; do
	expect_no_percent_sign "$pct%: the gauge renders glyphs only, no percentage text" "$pct"
done

# ── Fractional slot rounding ─────────────────────────────────────────────────

printf "\n── Fractional slot rounding (three glyphs: ● ◎ ○) ────────────────────────────\n"
expect_glyphs "30% (1.50 slots): the partly-filled slot renders ◎" 30 "● ◎ ○ ○ ○"
expect_glyphs "52% (2.60 slots): the partly-filled slot renders ◎" 52 "● ● ◎ ○ ○"

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

# ◎ is the only partly-filled glyph now: no bare ● stands in for one.
for pct in 30 52; do
	expect_every_filled_colored "$pct%: every ● wears the gradient, none is left bare" "$pct"
done

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

# Exact channel anchor, independent of ref_rgb: it holds the second ramp half in place
# while the first half's lightness changes.
expect_rgb() {
	local desc="$1" pct="$2" want_r="$3" want_g="$4" want_b="$5" r g b ok=yes
	read -r r g b <<<"$(usage_rgb "$pct")"
	within_tolerance "$r" "$want_r" 1 || ok=no
	within_tolerance "$g" "$want_g" 1 || ok=no
	within_tolerance "$b" "$want_b" 1 || ok=no
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
		*)
			report "$desc" no "unknown direction $dir"
			return
			;;
		esac
	fi
	report "$desc" "$ok" "$(printf 'R(%s) = %s, R(%s) = %s, expected it to have %s' "$lo" "$r_lo" "$hi" "$r_hi" "$dir")"
}

# The two ramp halves must meet without a visible seam at 50%.
expect_continuous_across() {
	local desc="$1" lo="$2" hi="$3" limit="$4" ok=yes
	local r1 g1 b1 r2 g2 b2
	read -r r1 g1 b1 <<<"$(usage_rgb "$lo")"
	read -r r2 g2 b2 <<<"$(usage_rgb "$hi")"
	within_tolerance "$r1" "$r2" "$limit" || ok=no
	within_tolerance "$g1" "$g2" "$limit" || ok=no
	within_tolerance "$b1" "$b2" "$limit" || ok=no
	report "$desc" "$ok" "$(printf '%s%% = %s %s %s, %s%% = %s %s %s' "$lo" "$r1" "$g1" "$b1" "$hi" "$r2" "$g2" "$b2")"
}

NOW=1700000000
# The default reset window for segment/pace tests below: a 5h window with 1h left.
PACE_WINDOW=18000
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

# Parentheses framed the old detail group; the new separator is a middle dot.
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
expect_segment_gradient "25%: label, space, and 25%% all wear the gradient" "5h" 25
expect_segment_gradient "95%: label, space, and 95%% all wear the gradient" "5h" 95
expect_segment_gradient "7d label, space, and 20%% all wear the gradient" "7d" 20
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
# Which glyph appears is the arrow's own contract; what color it wears is the
# segment's, and is pinned by expect_arrow_color below.

expect_pace_glyph() {
	local desc="$1" used="$2" expected="$3" actual ok=no
	actual=$(format_pace "$used" "$PACE_RESET" "$PACE_WINDOW" "$NOW" | strip_ansi)
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected %q\n      actual: %q' "$expected" "$actual")"
}

# The whole segment as plain text: pins glyph order and spacing — the leading separator,
# the space between label and percentage, the arrow hugging the `%`, and the ` · ` before
# the countdown — without restating any color. The segment carries its own " │ " prefix;
# main concatenates segments without inserting one.
expect_segment_plain() {
	local desc="$1" label="$2" used="$3" reset_ts="$4" window="$5" expected="$6"
	local actual ok=no
	actual=$(format_limit_segment "$label" "$used" "$reset_ts" "$window" "$NOW" | strip_ansi)
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected %q\n      actual: %q' "$expected" "$actual")"
}

# The last color escape standing before the arrow decides what color the arrow renders in:
# the gradient for the over-pace arrows, a reset (terminal default) for the under-pace one.
last_escape() {
	printf '%s' "$1" | grep -oE $'\033\\[[0-9;]*m' | tail -1 || true
}

expect_arrow_color() {
	local desc="$1" used="$2" arrow="$3" want="$4"
	local color out head got expected ok=no
	color=$(usage_color "$used")
	out=$(format_limit_segment "5h" "$used" "$PACE_RESET" "$PACE_WINDOW" "$NOW")
	head=${out%%"$arrow"*}
	got=$(last_escape "$head")
	case "$want" in
	gradient) expected="$color" ;;
	default) expected="$C_RESET" ;;
	*)
		report "$desc" no "unknown color expectation $want"
		return
		;;
	esac
	[[ "$out" == *"$arrow"* && "$got" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'escape in force at the arrow: %q, expected %q\n      actual: %q' "$got" "$expected" "$out")"
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
# Over-pace is the bad news, so it inherits the segment's own usage gradient and grows
# louder as usage climbs. Under-pace is good news and stays quiet: the ↓ renders in the
# terminal's default foreground, with no color of its own.

printf "\n── Pace arrow color (gradient up, default down) ──────────────────────────────\n"
expect_arrow_color "85%: the ↑ inherits the 85%% gradient" 85 "↑" gradient
expect_arrow_color "100%: the ↑↑ inherits the 100%% gradient" 100 "↑↑" gradient
expect_arrow_color "60%: the ↓ renders in the default foreground" 60 "↓" default

# ── Segment shape ────────────────────────────────────────────────────────────
#
# `<label> <pct>%<arrow> · <countdown>` — no colon, no parentheses, no space before the
# arrow. The countdown is appended only when there is one to show *and* usage has reached
# 75%: below that the window has room to spare, so how long until it resets is noise and
# the percentage stands alone.

printf "\n── Segment shape (label pct%%arrow · countdown) ───────────────────────────────\n"
expect_segment_plain "over pace: the arrow hugs the percentage" "5h" 88 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 88%↑ · 1h"
expect_segment_plain "hot pace: the double arrow hugs the percentage" "5h" 100 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 100%↑↑ · 1h"
expect_segment_plain "on pace: countdown alone, no arrow" "5h" 82 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 82% · 1h"
expect_segment_plain "no countdown to show: nothing follows the percentage" "5h" 100 "$NOW" "$PACE_WINDOW" " │ 5h 100%"
# The 75% boundary, pinned from both sides. Both cases sit under pace, so the down arrow
# still hugs the percentage and the countdown is the only difference between them.
expect_segment_plain "74%: below the threshold, the down arrow hugs the percentage and no countdown follows" "5h" 74 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 74%↓"
expect_segment_plain "75%: at the threshold, the countdown appears" "5h" 75 "$PACE_RESET" "$PACE_WINDOW" " │ 5h 75%↓ · 1h"
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
	local desc="$1" seconds="$2" expected="$3" actual ok=no
	actual=$(format_countdown "$((NOW + seconds))" "$NOW")
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected %q\n      actual: %q' "$expected" "$actual")"
}

printf "\n── Reset countdown ──────────────────────────────────────────────────────────\n"
expect_countdown "45m left: minutes alone" $((45 * 60)) "45m"
expect_countdown "2h left: zero minutes are dropped" $((2 * 3600)) "2h"
expect_countdown "2h10m left: hours and minutes" $((2 * 3600 + 10 * 60)) "2h10m"
expect_countdown "23h59m left: still below a day" $((23 * 3600 + 59 * 60)) "23h59m"
expect_countdown "exactly 24h left: a day with zero hours" $((24 * 3600)) "1d"
expect_countdown "4d13h left: days and hours" $((4 * 86400 + 13 * 3600)) "4d13h"
expect_countdown "reset lands on now: nothing to count down" 0 ""
expect_countdown "reset already passed: nothing to count down" -3600 ""

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
MAIN_TRANSCRIPT=$(mktemp "${TMPDIR:-/tmp}/statusline-transcript.XXXXXX")
CLEANUP_PATHS=("$MAIN_TRANSCRIPT")
trap 'rm -rf "${CLEANUP_PATHS[@]}"' EXIT

# All three stdin fixtures below (this one and the two degraded-input ones further down)
# share this envelope; stdin_json merges in each fixture's distinguishing fields.
STDIN_ENVELOPE='{"hook_event_name":"Status","session_id":"statusline-test","transcript_path":"'"$MAIN_TRANSCRIPT"'","cwd":"/tmp/statusline-proj","version":"1.0.0","output_style":{"name":"default"},"exceeds_200k_tokens":false}'
stdin_json() {
	jq -c --argjson extra "$1" '. * $extra' <<<"$STDIN_ENVELOPE"
}

MAIN_STDIN=$(stdin_json '{"model":{"id":"claude-opus-4-1","display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/statusline-proj","project_dir":"/tmp/statusline-proj"}}')

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

expect_exact_line() {
	local desc="$1" actual="$2" expected="$3" ok=no
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected %q\n      actual: %q' "$expected" "$actual")"
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
expect_line_contains "the 5h segment renders as label, percentage, arrow, countdown" "$MAIN_PLAIN" "│ 5h 78%↑↑ · 4h9m │"
# The trailing segment, taken whole: nothing follows the percentage, so the 7d window's
# days-away reset stays off the line while it is below the threshold.
expect_exact_line "the 7d segment is below the threshold, so no countdown trails the line" "${MAIN_PLAIN##*│ }" "7d 7%"
expect_no_parentheses "the whole line frames details with · , not parentheses" "$MAIN_PLAIN"
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

# The diagnostic reaches stderr and the line still reaches stdout: neither alone is
# enough, since a diagnostic that replaces the line is as bad as a line that hides the
# failure.
expect_diagnosed() {
	local desc="$1" plain="$2" needle="$3" rendered="$4" case_name="$5" err ok=no
	err=$(<"$MAIN_CASES/$case_name/stderr")
	[[ "$err" == *"$needle"* && "$plain" == *"$rendered"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected stderr to mention %q and the line to keep %q\n      stderr: %q\n      stdout: %q' "$needle" "$rendered" "$err" "$plain")"
}

# shellcheck disable=SC2031 # main_render's TMPDIR change is subshell-local; ambient TMPDIR is intact here
STDIN_NO_NAMES=$(stdin_json '{"model":{"id":"claude-opus-4-1"},"workspace":{"project_dir":"/tmp/statusline-proj"}}')
# Valid stdin carrying an invalid rate-limits payload: the string parses, its contents do not.
STDIN_BAD_LIMITS=$(stdin_json '{"model":{"id":"claude-opus-4-1","display_name":"Opus 4.6"},"workspace":{"current_dir":"/tmp/statusline-proj","project_dir":"/tmp/statusline-proj"},"rate_limits":"{not json","cost":{"total_api_duration_ms":100}}')

printf "\n── Degraded input ───────────────────────────────────────────────────────────\n"
expect_exact_line "a stdin without model.display_name or workspace.current_dir renders empty slots, not \"null\"" \
	"$(main_render no-names "$STDIN_NO_NAMES" "$MAIN_PAYLOAD" | strip_ansi)" \
	" │  ○ ○ ○ ○ ○ │ 5h 78%↑↑ · 4h9m │ 7d 7%"
expect_diagnosed "an unparseable rate-limits payload is reported on stderr, and the line still renders" \
	"$(main_render bad-limits "$STDIN_BAD_LIMITS" | strip_ansi)" "rate-limit parse failed" "Opus 4.6" bad-limits

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
		# shellcheck disable=SC2031 # subshell-local on purpose: each case owns its cache
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
# the same time. The mkdir lock is what keeps only one of them fetching: a render that
# loses the race falls through without touching the network, still serving whatever the
# cache already holds rather than blanking the segment. Once the lock is released, the
# next call past the throttle window is free to fetch and land its payload in the cache.

# The cache file name is the script's own business, so it is discovered by content
# rather than spelled out here.
cache_file_for() {
	local dir="$FALLBACK_ROOT/$1/tmp" f
	for f in "$dir"/*; do
		[[ -f "$f" ]] || continue
		if grep -q five_hour "$f"; then
			printf '%s' "$f"
			return 0
		fi
	done
	return 1
}

FRESH_USAGE_BODY='{"five_hour":{"utilization":55,"resets_at":"2023-11-14T22:13:20Z"},"seven_day":{"utilization":13,"resets_at":"2023-11-20T22:13:20Z"}}'

printf "\n── Usage fallback: the lock keeps concurrent renders from double-fetching ─────\n"
seed_good_cache staging
staging_cache=$(cache_file_for staging) || {
	printf "\nFAIL  cache_file_for could not find the seeded cache file for the staging case\n"
	exit 1
}
mkdir -p "${staging_cache}.lock"
# The lock is reclaimed once it's older than the throttle window, judged against the
# `now` argument below rather than the wall clock — so a lock merely mkdir'd at the real
# time would look stale to a `now` this far ahead and get reclaimed instead of held. Back
# date it to just inside the window so it reads as a lock a concurrent render still holds.
touch -m -t "$(date -r $((FB_BASE + 399)) +%Y%m%d%H%M.%S)" "${staging_cache}.lock"

fb_out=$(fallback_fetch staging 0 "$FRESH_USAGE_BODY" $((FB_BASE + 400)))
expect_attempts "a held lock keeps the locked-out render from fetching" staging 1
expect_fallback_json "a held lock still serves the stale cache, not a blank segment" "$fb_out" '.five_hour.used_percentage' 42

rmdir "${staging_cache}.lock"

fb_out=$(fallback_fetch staging 0 "$FRESH_USAGE_BODY" $((FB_BASE + 450)))
expect_attempts "lock released: the next call past the throttle window fetches" staging 2
expect_fallback_json "lock released: the fresh payload lands in the cache" "$fb_out" '.five_hour.used_percentage' 55

# ── Summary ──────────────────────────────────────────────────────────────────

printf "\n─────────────────────────────────────────────────────────────────────────────\n"
printf "%d passed, %d failed\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
