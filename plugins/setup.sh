#!/usr/bin/env bash
# Install plugins from manifest.json
# Usage: bash plugins/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"

command -v claude >/dev/null || {
	printf "Error: claude CLI not found\n" >&2
	exit 1
}

command -v jq >/dev/null || {
	printf "Error: jq not found\n" >&2
	exit 1
}

main() {
	printf "==> Adding marketplaces...\n"
	jq -r '.marketplaces[] | .source' "$MANIFEST" | while IFS= read -r source; do
		printf "  Adding: %s\n" "$source"
		claude plugins marketplace add "$source" || true
	done

	printf "==> Installing plugins...\n"
	jq -r '.plugins[]' "$MANIFEST" | while IFS= read -r plugin; do
		printf "  Installing: %s\n" "$plugin"
		claude plugins install "$plugin" || true
	done

	printf "Done.\n"
}

main "$@"
