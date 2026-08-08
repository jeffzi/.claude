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
# Color marks progress: the filled slots, the half slot, and the percentage text wear the smooth
# `usage_color` gradient. Only empty slots carry no color escape at all, so they render in the
# terminal's default foreground like the model name beside them. There are no color tiers —
# the gradient is continuous across 50% and 90%.
#
# The gradient's own base is light (≈191 gray at 0%), so a bar at low usage reads like default
# terminal text on a dark background rather than as near-invisible dark gray.

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$TEST_DIR/../scripts/statusline.sh"
PASS=0
FAIL=0

# ── Expected escapes, spelled out independently of the script's own variables ─

C_GRAY=$'\033[38;5;238m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_AMBER=$'\033[38;5;208m'
C_BLINK=$'\033[5m'
C_RESET=$'\033[0m'

# Only empty slots wear no escape: a bare glyph in the default foreground.
EMPTY="○"
HALF="◎"
FILLED="●"

# ── Helpers ───────────────────────────────────────────────────────────────────

strip_ansi() {
	sed $'s/\033\\[[0-9;]*m//g'
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
	actual=$(fmt_context_bar "$pct" | strip_ansi)
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected: %s\n      actual: %s' "$expected" "$actual")"
}

# Compares the fully colored bar against a slot pattern, one character per slot:
#
#   F  filled ●, wearing the `usage_color $pct` gradient
#   H  half ◎, wearing the same gradient
#   E  empty ○, uncolored
#
# The trailing percentage text always wears the same gradient, whatever the pattern.
#
# The gradient escape is looked up from usage_color itself, so these assertions pin which
# glyphs carry the gradient without restating the ramp — the ramp has its own tests below.
expect_bar() {
	local desc="$1" pct="$2" pattern="$3" color slots="" sep="" i expected actual ok=no
	color=$(usage_color "$pct")
	for ((i = 0; i < ${#pattern}; i++)); do
		case "${pattern:i:1}" in
		F) slots+="${sep}${color}${FILLED}${C_RESET}" ;;
		H) slots+="${sep}${color}${HALF}${C_RESET}" ;;
		E) slots+="${sep}${EMPTY}" ;;
		*)
			printf "FAIL  %s\n    unknown slot code %q in pattern %q\n" "$desc" "${pattern:i:1}" "$pattern"
			((++FAIL))
			return
			;;
		esac
		sep=" "
	done
	expected="${slots} ${color}${pct}%${C_RESET}"
	actual=$(fmt_context_bar "$pct")
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected: %q\n      actual: %q' "$expected" "$actual")"
}

# Every ● in the bar must wear the gradient: strip the colored-filled form, and no bare ●
# may remain. This is what rules out the superseded uncolored ● that used to stand in for a
# partial slot — that role belongs to ◎ now.
expect_every_filled_colored() {
	local desc="$1" pct="$2" color rest ok=no
	color=$(usage_color "$pct")
	rest=$(fmt_context_bar "$pct")
	while [[ "$rest" == *"${color}${FILLED}${C_RESET}"* ]]; do
		rest="${rest/"${color}${FILLED}${C_RESET}"/}"
	done
	[[ "$rest" != *"$FILLED"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'uncolored %s left after stripping colored ones: %q' "$FILLED" "$rest")"
}

# Checks any rendered fragment — bar, segment, whole line — for the marks of superseded
# renderers: the block glyphs and the ambiguous-width half-circle family (◐ ◑ ◒ ◓) of the
# old gauges, the skull and blink of the old alarm, and the palette `usage_color` replaced
# (dim gray as base text, the yellow tier). `usage_color` is the only source of color for
# usage now, so nothing colored by usage may carry these.
#
# Green and red are deliberately absent from the list: fmt_pace still owns \033[32m for its
# under-pace arrow and \033[31m for the hot-pace one. The bar's own expect_bar assertions
# match its output exactly, so they already reject any stray escape there.
expect_no_legacy_artifacts() {
	local desc="$1" actual="$2" found="" ok=no
	if [[ "$actual" == *"█"* || "$actual" == *"░"* || "$actual" == *"▓"* ]]; then
		found="block glyph"
	elif [[ "$actual" == *"◐"* || "$actual" == *"◑"* || "$actual" == *"◒"* || "$actual" == *"◓"* ]]; then
		found="half-circle glyph (◐ ◑ ◒ ◓ all render double-width)"
	elif [[ "$actual" == *"💀"* ]]; then
		found="skull emoji"
	elif [[ "$actual" == *"$C_BLINK"* ]]; then
		found="blink escape"
	elif [[ "$actual" == *"$C_GRAY"* ]]; then
		found="dim gray escape (usage text renders uncolored or gradient-colored)"
	elif [[ "$actual" == *"$C_YELLOW"* ]]; then
		found="yellow tier escape"
	fi
	[[ -z "$found" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'found %s in %q' "$found" "$actual")"
}

# ── Load the renderer ─────────────────────────────────────────────────────────

# shellcheck source-path=SCRIPTDIR source=../scripts/statusline.sh
source "$SCRIPT" </dev/null

for required in fmt_context_bar usage_color; do
	if ! declare -F "$required" >/dev/null; then
		printf "FAIL  %s is not defined after sourcing %s\n" "$required" "$SCRIPT"
		exit 1
	fi
done

# ── Glyph layout: 5 slots, space separated ───────────────────────────────────

printf "\n── Glyph layout ─────────────────────────────────────────────────────────────\n"
expect_glyphs "0%: all slots empty" 0 "○ ○ ○ ○ ○ 0%"
expect_glyphs "100%: all slots filled" 100 "● ● ● ● ● 100%"
expect_glyphs "20%: exactly one slot filled" 20 "● ○ ○ ○ ○ 20%"

# ── Fractional slot rounding ─────────────────────────────────────────────────

printf "\n── Fractional slot rounding (three glyphs: ● ◎ ○) ────────────────────────────\n"
expect_glyphs "24% (1.20 slots): fraction below 0.25 renders empty" 24 "● ○ ○ ○ ○ 24%"
expect_glyphs "30% (1.50 slots): the partly-filled slot renders ◎" 30 "● ◎ ○ ○ ○ 30%"
expect_glyphs "52% (2.60 slots): the partly-filled slot renders ◎" 52 "● ● ◎ ○ ○ 52%"

# The half and filled glyphs differ while both wear the gradient, so the rounding boundaries
# below still pin which glyph each fraction picks.
expect_bar "64% (3.20 slots): fraction below 0.25 renders empty" 64 "FFFEE"
expect_bar "65% (3.25 slots): fraction at 0.25 renders a gradient-colored half" 65 "FFFHE"
expect_bar "74% (3.70 slots): fraction below 0.75 renders a gradient-colored half" 74 "FFFHE"
expect_bar "75% (3.75 slots): fraction at 0.75 is promoted to filled" 75 "FFFFE"

# ── Gradient coloring ────────────────────────────────────────────────────────

printf "\n── Gradient coloring (filled, half and text; only empty uncolored) ───────────\n"
expect_bar "48%: the filled slots, the ◎ and the 48% text all wear the gradient" 48 "FFHEE"
expect_bar "95%: every filled slot and the text wear the 95% gradient, not red" 95 "FFFFF"
expect_bar "0%: no slot is filled, so only the 0% text wears the gradient" 0 "EEEEE"

# ◎ is the only partly-filled glyph now: no bare ● stands in for one.
for pct in 30 48 52 65 74 89; do
	expect_every_filled_colored "$pct%: every ● wears the gradient, none is left bare" "$pct"
done

# The gradient is continuous: the percentages where the old tiers switched color render
# like their neighbors, with no jump to yellow at 50% or red at 90%.
printf "\n── No tier boundaries ───────────────────────────────────────────────────────\n"
expect_bar "50%: gradient value, not the yellow tier" 50 "FFHEE"
expect_bar "89%: gradient value, not the yellow tier" 89 "FFFFH"
expect_bar "90%: gradient value, not the red tier" 90 "FFFFH"

# ── Removed artifacts ────────────────────────────────────────────────────────

printf "\n── Removed artifacts (blocks, ◐ ◑ ◒ ◓, skull, blink, gray, yellow tier) ──────\n"
for pct in 0 30 45 50 52 90 100; do
	expect_no_legacy_artifacts "$pct%: context bar carries no superseded escape or glyph" \
		"$(fmt_context_bar "$pct")"
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

occurrences() {
	local rest="$1" needle="$2" count=0
	while [[ "$rest" == *"$needle"* ]]; do
		rest="${rest#*"$needle"}"
		((++count))
	done
	printf '%d' "$count"
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

expect_matches_hsl_ref() {
	local desc="$1" pct="$2" ok=yes
	local r g b rr rg rb
	read -r r g b <<<"$(usage_rgb "$pct")"
	read -r rr rg rb <<<"$(ref_rgb "$pct")"
	within_tolerance "$r" "$rr" 1 || ok=no
	within_tolerance "$g" "$rg" 1 || ok=no
	within_tolerance "$b" "$rb" 1 || ok=no
	report "$desc" "$ok" "$(printf 'expected ~%s %s %s, got %s %s %s' "$rr" "$rg" "$rb" "$r" "$g" "$b")"
}

# A neutral gray of a given brightness: all three channels equal and near $level. The level
# is spelled out here rather than derived from ref_rgb, so it pins the design anchor — the
# base of the ramp must sit at ordinary-terminal-text brightness — independently of whatever
# lightness formula the ramp happens to carry.
expect_gray_level() {
	local desc="$1" pct="$2" level="$3" tol="$4" r g b ok=no
	read -r r g b <<<"$(usage_rgb "$pct")"
	if [[ "$r" == "$g" && "$g" == "$b" ]] && within_tolerance "$r" "$level" "$tol"; then
		ok=yes
	fi
	report "$desc" "$ok" "$(printf 'expected three equal channels near %s (±%s), got %s %s %s' "$level" "$tol" "$r" "$g" "$b")"
}

# Exact channel anchor, again independent of ref_rgb: it holds the second ramp half in place
# while the first half's lightness changes.
expect_rgb() {
	local desc="$1" pct="$2" want_r="$3" want_g="$4" want_b="$5" r g b ok=yes
	read -r r g b <<<"$(usage_rgb "$pct")"
	within_tolerance "$r" "$want_r" 1 || ok=no
	within_tolerance "$g" "$want_g" 1 || ok=no
	within_tolerance "$b" "$want_b" 1 || ok=no
	report "$desc" "$ok" "$(printf 'expected ~%s %s %s, got %s %s %s' "$want_r" "$want_g" "$want_b" "$r" "$g" "$b")"
}

# Chroma stand-in: red minus blue is the visible colorfulness of this ramp.
expect_chroma_at_most() {
	local desc="$1" pct="$2" limit="$3" r g b diff ok=no
	read -r r g b <<<"$(usage_rgb "$pct")"
	diff=$((r - b))
	[[ "$r" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && $diff -le "$limit" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'R-B = %s, expected <= %s (rgb %s %s %s)' "$diff" "$limit" "$r" "$g" "$b")"
}

expect_chroma_at_least() {
	local desc="$1" pct="$2" floor="$3" r g b diff ok=no
	read -r r g b <<<"$(usage_rgb "$pct")"
	diff=$((r - b))
	[[ "$r" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && $diff -ge "$floor" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'R-B = %s, expected >= %s (rgb %s %s %s)' "$diff" "$floor" "$r" "$g" "$b")"
}

# Gold means red leads green leads blue. Hue 60 would make red and green equal.
expect_gold_not_green() {
	local desc="$1" pct="$2" r g b ok=no
	read -r r g b <<<"$(usage_rgb "$pct")"
	[[ "$r" =~ ^[0-9]+$ && $r -gt $g && $g -gt $b ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected R > G > B, got %s %s %s' "$r" "$g" "$b")"
}

expect_red() {
	local desc="$1" pct="$2" min_r="$3" max_gb="$4" r g b ok=no
	read -r r g b <<<"$(usage_rgb "$pct")"
	[[ "$r" =~ ^[0-9]+$ && $r -ge "$min_r" && $g -le "$max_gb" && $b -le "$max_gb" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected R >= %s and G,B <= %s, got %s %s %s' "$min_r" "$max_gb" "$r" "$g" "$b")"
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

# The gradient starts after the colon: the "label:" prefix stays uncolored, so only
# "PCT%" is wrapped in the escape.
expect_segment_gradient() {
	local desc="$1" label="$2" pct="$3" color out want ok=no
	color=$(usage_color "$pct")
	out=$(fmt_limit_segment "$label" "$pct" "$PACE_RESET" "$PACE_WINDOW" fmt_reset_countdown "$NOW")
	want="${label}:${color}${pct}%${C_RESET}"
	[[ "$out" == *"$want"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected to contain %q\n    actual: %q' "$want" "$out")"
}

# Everything the segment prints before the gradient escape — the separator and the label —
# must carry no escape at all, so the label renders in the terminal's default foreground.
expect_label_uncolored() {
	local desc="$1" label="$2" pct="$3" color out head ok=no
	color=$(usage_color "$pct")
	out=$(fmt_limit_segment "$label" "$pct" "$PACE_RESET" "$PACE_WINDOW" fmt_reset_countdown "$NOW")
	head=${out%%"$color"*}
	[[ "$head" != *$'\033'* && "$head" == *"$label:" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'text before the gradient escape: %q' "$head")"
}

expect_gradient_used_once() {
	local desc="$1" label="$2" pct="$3" color out ok=no
	color=$(usage_color "$pct")
	out=$(fmt_limit_segment "$label" "$pct" "$PACE_RESET" "$PACE_WINDOW" fmt_reset_countdown "$NOW")
	[[ "$(occurrences "$out" "$color")" == "1" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'gradient escape appears %s time(s): %q' "$(occurrences "$out" "$color")" "$out")"
}

expect_reset_not_gradient() {
	local desc="$1" label="$2" pct="$3" formatter="$4" reset_ts="$5" window="$6"
	local color out tail ok=no
	color=$(usage_color "$pct")
	out=$(fmt_limit_segment "$label" "$pct" "$reset_ts" "$window" "$formatter" "$NOW")
	tail=${out#*"${label}:${color}${pct}%${C_RESET}"}
	[[ "$tail" != *"$color"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'reset text after the label: %q' "$tail")"
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
# The lighter base only moves the first ramp half: the seam value stays where it was.
expect_rgb "50%: warm gold unchanged by the lighter base" 50 207 183 63
expect_chroma_at_least "50%: clearly colored, not gray" 50 100
expect_red "95%: red" 95 240 100
expect_pure_red_hue "100%: pure red hue, G = B at full saturation" 100
# Below 50% the ramp darkens as color emerges: the light base is the low-usage end, so the
# red channel dips before the second half drives it up to pure red.
expect_red_direction "red channel climbs from 25% to 50%" 25 50 rises
expect_red_direction "red channel climbs from 50% to 100%" 50 100 rises

# ── Limit segment coloring ───────────────────────────────────────────────────

printf "\n── Limit segment coloring ───────────────────────────────────────────────────\n"
expect_segment_gradient "61%: only 61% wears the gradient, the 5h: label does not" "5h" 61
expect_segment_gradient "10%: only 10% wears the gradient, the 5h: label does not" "5h" 10
expect_segment_gradient "95%: only 95% wears the gradient, the 5h: label does not" "5h" 95
expect_label_uncolored "5h label and colon render with no color escape" "5h" 61
expect_label_uncolored "7d label and colon render with no color escape" "7d" 20
expect_gradient_used_once "61%: gradient escape is emitted once per segment" "5h" 61
expect_reset_not_gradient "countdown reset text not gradient-colored" "5h" 61 fmt_reset_countdown "$PACE_RESET" "$PACE_WINDOW"
expect_reset_not_gradient "absolute reset text not gradient-colored" "7d" 20 fmt_reset_absolute "$((NOW + 200000))" 604800

# The gradient is the only source of usage color here too, so the superseded palette must be
# gone from the segments as well — not just from the bar.
expect_no_legacy_artifacts "5h segment carries no superseded escape or glyph" \
	"$(fmt_limit_segment "5h" 61 "$PACE_RESET" "$PACE_WINDOW" fmt_reset_countdown "$NOW")"
expect_no_legacy_artifacts "7d segment carries no superseded escape or glyph" \
	"$(fmt_limit_segment "7d" 20 "$((NOW + 200000))" 604800 fmt_reset_absolute "$NOW")"

# ── Pace indicator ───────────────────────────────────────────────────────────
#
# fmt_pace compares usage against the share of the window already elapsed and
# renders a colored arrow for the gap:
#
#   delta <= -5    ↓   green   (under pace)
#   -5 < delta < 5  (nothing)  (on pace)
#   +5 .. +14      ↑   amber   (over pace)
#   delta >= +15   ↑↑  red     (hot)
#
# Every case below uses a 5h window with 1h left (PACE_WINDOW/PACE_RESET), so 4h
# of 5h has elapsed and the on-pace usage is 80%. The `used` value therefore sets
# the delta directly.

expect_pace() {
	local desc="$1" used="$2" expected="$3" actual ok=no
	actual=$(fmt_pace "$used" "$PACE_RESET" "$PACE_WINDOW" "$NOW")
	[[ "$actual" == "$expected" ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected %q\n      actual: %q' "$expected" "$actual")"
}

# Compares the plain-text rendering of the whole segment, so the assertion pins
# glyph order and spacing inside the parenthetical without restating colors.
expect_detail_text() {
	local desc="$1" label="$2" used="$3" expected_detail="$4"
	local out plain reset_plain ok=no
	out=$(fmt_limit_segment "$label" "$used" "$PACE_RESET" "$PACE_WINDOW" fmt_reset_countdown "$NOW")
	plain=$(printf '%s' "$out" | strip_ansi)
	reset_plain=$(fmt_reset_countdown "$PACE_RESET" "$NOW" | strip_ansi)
	local want="${expected_detail/RESET/$reset_plain}"
	[[ "$plain" == *"$want"* ]] && ok=yes
	report "$desc" "$ok" "$(printf 'expected to contain %q\n      actual: %q' "$want" "$plain")"
}

if ! declare -F fmt_pace >/dev/null; then
	printf "\nFAIL  fmt_pace is not defined after sourcing %s\n" "$SCRIPT"
	exit 1
fi

printf "\n── Pace arrows ──────────────────────────────────────────────────────────────\n"
expect_pace "60% at 80%% pace (delta -20): green down arrow" 60 "${C_GREEN}↓${C_RESET}"
expect_pace "75% at 80%% pace (delta -5): green down arrow at the boundary" 75 "${C_GREEN}↓${C_RESET}"
expect_pace "76% at 80%% pace (delta -4): on pace, no arrow" 76 ""
expect_pace "84% at 80%% pace (delta +4): on pace, no arrow" 84 ""
expect_pace "85% at 80%% pace (delta +5): amber up arrow at the boundary" 85 "${C_AMBER}↑${C_RESET}"
expect_pace "94% at 80%% pace (delta +14): amber up arrow" 94 "${C_AMBER}↑${C_RESET}"
expect_pace "95% at 80%% pace (delta +15): red double arrow at the boundary" 95 "${C_RED}↑↑${C_RESET}"
expect_pace "100% at 80%% pace (delta +20): red double arrow" 100 "${C_RED}↑↑${C_RESET}"

# ── Pace detail parenthetical ────────────────────────────────────────────────

printf "\n── Pace detail parenthetical (no hourglass prefix) ───────────────────────────\n"
expect_detail_text "over pace: reset time follows the arrow directly" "5h" 88 "(↑ RESET)"
expect_detail_text "on pace: reset time alone, no arrow prefix" "5h" 82 "(RESET)"

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

if ! declare -F fetch_usage_fallback >/dev/null; then
	printf "\nFAIL  fetch_usage_fallback is not defined after sourcing %s\n" "$SCRIPT"
	exit 1
fi

FALLBACK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statusline-fallback.XXXXXX")
trap 'rm -rf "$FALLBACK_ROOT"' EXIT

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

# ── Summary ──────────────────────────────────────────────────────────────────

printf "\n─────────────────────────────────────────────────────────────────────────────\n"
printf "%d passed, %d failed\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
