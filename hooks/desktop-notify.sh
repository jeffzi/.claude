#!/usr/bin/env bash
set -euo pipefail

# macOS-only desktop notification when Claude finishes responding.
# Stop hook input (JSON on stdin): stop_reason, cwd, transcript_path, session_id.
[[ "$(uname)" == "Darwin" ]] || exit 0

# ── Fallback: generic notification if jq missing ──
command -v jq >/dev/null || {
	osascript -e 'display notification "Response complete" with title "Claude Code"' 2>/dev/null
	exit 0
}

input=$(cat)

# ── Extract fields ──
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
stop_reason=$(printf '%s' "$input" | jq -r '.stop_reason // empty')
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

# ── Skip non-response stops (session exit, clear, logout, etc.) ──
case "$stop_reason" in
end_turn | max_tokens | max_output_tokens | budget_limit) ;;
*) exit 0 ;;
esac

# ── Project + branch ──
project=""
branch=""
if [[ -n "$cwd" ]]; then
	project=$(basename "$cwd")
	branch=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
fi

# ── Duration from transcript timestamps ──
duration=""
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
	first_ts=$(head -1 "$transcript_path" | jq -r '.timestamp // empty' 2>/dev/null || true)
	last_ts=$(tail -1 "$transcript_path" | jq -r '.timestamp // empty' 2>/dev/null || true)
	if [[ -n "$first_ts" && -n "$last_ts" ]]; then
		first_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "${first_ts%%.*}" "+%s" 2>/dev/null || true)
		last_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "${last_ts%%.*}" "+%s" 2>/dev/null || true)
		if [[ -n "$first_epoch" && -n "$last_epoch" ]]; then
			delta=$((last_epoch - first_epoch))
			if ((delta >= 3600)); then
				duration="$(printf '%dh %dm' $((delta / 3600)) $(((delta % 3600) / 60)))"
			elif ((delta >= 60)); then
				duration="$(printf '%dm %ds' $((delta / 60)) $((delta % 60)))"
			elif ((delta > 0)); then
				duration="${delta}s"
			fi
		fi
	fi
fi

# ── Map stop_reason to label ──
case "$stop_reason" in
end_turn) reason_label="Done" ;;
user_interrupted) reason_label="Interrupted" ;;
max_tokens) reason_label="Max tokens" ;;
*) reason_label="${stop_reason:-Done}" ;;
esac

# ── Compose title: CC → project ┃ branch ──
title="CC"
if [[ -n "$project" ]]; then
	title="${title} → ${project}"
fi
if [[ -n "$branch" ]]; then
	title="${title} ┃ ${branch}"
fi

# ── Compose body: reason + duration ──
body="$reason_label"
if [[ -n "$duration" ]]; then
	body="${body} · ${duration}"
fi

# ── Fire notification ──
osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null
exit 0
