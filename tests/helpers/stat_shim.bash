#!/usr/bin/env bash
# A fake `stat` for tests that need a given dialect, or none, on PATH.

# The shim shadows the host `stat` when its directory is prepended to PATH.
# The caller supplies the full script in $2, shebang included.
make_stat_shim() {
	local dir="$1" body="$2"
	mkdir -p "$dir"
	printf '%s\n' "$body" >"$dir/stat"
	chmod +x "$dir/stat"
}
