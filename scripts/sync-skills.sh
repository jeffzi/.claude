#!/usr/bin/env bash
set -euo pipefail

# `bash sync-skills.sh` run from inside scripts/ leaves no slash to strip a
# directory at.
SCRIPT_SOURCE=${BASH_SOURCE[0]}
[[ "$SCRIPT_SOURCE" == */* ]] || SCRIPT_SOURCE="./$SCRIPT_SOURCE"
# `die`.
# shellcheck source=SCRIPTDIR/sh-common.sh
. "${SCRIPT_SOURCE%/*}/sh-common.sh"
PROG=sync-skills

# Install/update external skills in ~/.claude/skills/ via the `skills` CLI
# (https://github.com/vercel-labs/skills). `add` is idempotent (re-copies in place),
# so re-running this resyncs. This command list is the source of truth.
main() {
	command -v npx >/dev/null || die "npx is required (install Node.js)" 1

	local install_flags=(-g -a claude-code -y --copy)

	npx --yes skills add K-Dense-AI/claude-scientific-skills "${install_flags[@]}" \
		--skill markdown-mermaid-writing --skill paper-lookup \
		--skill polars --skill pymc --skill scikit-learn --skill scikit-survival \
		--skill statistical-analysis

	npx --yes skills add blader/humanizer "${install_flags[@]}"

	npx --yes skills add fallow-rs/fallow-skills "${install_flags[@]}" --skill fallow

	npx --yes skills add jeffzi/ils "${install_flags[@]}" --skill write-release
}

main "$@"
