#!/usr/bin/env bash
set -euo pipefail

# Install/update external skills in ~/.claude/skills/ via the `skills` CLI
# (https://github.com/vercel-labs/skills). `add` is idempotent (re-copies in place),
# so re-running this resyncs. This command list is the source of truth.
main() {
	command -v npx >/dev/null || {
		printf 'sync-skills: npx is required (install Node.js)\n' >&2
		exit 1
	}

	local common=(-g -a claude-code -y --copy)

	npx --yes skills add K-Dense-AI/claude-scientific-skills "${common[@]}" \
		--skill markdown-mermaid-writing --skill paper-lookup \
		--skill polars --skill pymc --skill scikit-learn --skill scikit-survival \
		--skill statistical-analysis

	npx --yes skills add blader/humanizer "${common[@]}"

	npx --yes skills add fallow-rs/fallow-skills "${common[@]}" --skill fallow
}

main "$@"
