#!/usr/bin/env bats

load helpers/stat_shim

setup_file() {
	export SH_COMMON
	SH_COMMON="$(cd "$BATS_TEST_DIRNAME/../scripts" && pwd)/sh-common.sh"

	export SHIM_ROOT
	SHIM_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sh-common-stat.XXXXXX")

	export SHIM_MTIME=1700000000

	export BSD_DIR="$SHIM_ROOT/bsd"
	make_stat_shim "$BSD_DIR" "$(dialect_shim -f %m)"

	export GNU_DIR="$SHIM_ROOT/gnu"
	make_stat_shim "$GNU_DIR" "$(dialect_shim -c %Y)"
}

teardown_file() {
	rm -rf "${SHIM_ROOT:-}"
}

# A stat that answers SHIM_MTIME only to format flag $1 with value $2, the way one
# dialect answers and the other refuses.
dialect_shim() {
	cat <<-SHIM
		#!/usr/bin/env bash
		if [[ "\${1:-}" == "$1" && "\${2:-}" == "$2" ]]; then
			printf '%s\n' "$SHIM_MTIME"
		else
			exit 1
		fi
	SHIM
}

# Sources sh-common.sh with the stat shim in $1 first on PATH, then reads the mtime of
# the sourced file through sh_file_attr. Sourcing in a fresh subshell runs the dialect
# probe against the shim.
mtime_under_shim() {
	local stat_dir="$1"
	(
		# shellcheck disable=SC2030,SC2031  # export scoped to subshell
		export PATH="$stat_dir:$PATH"
		# shellcheck source=../scripts/sh-common.sh disable=SC1091  # a plain `shellcheck` run does not follow sourced files; only `-x` does
		. "$SH_COMMON"
		sh_file_attr mtime "$SH_COMMON"
	)
}

@test "BSD stat: the probe picks -f %m and sh_file_attr reads the mtime" {
	local out

	out=$(mtime_under_shim "$BSD_DIR")

	[[ "$out" == "$SHIM_MTIME" ]]
}

@test "GNU stat: the probe picks -c %Y and sh_file_attr reads the mtime" {
	local out

	out=$(mtime_under_shim "$GNU_DIR")

	[[ "$out" == "$SHIM_MTIME" ]]
}

@test "an IFS without a space still hands stat its format flag and value apart" {
	local out

	out=$(IFS=$'\n\t' mtime_under_shim "$BSD_DIR")

	[[ "$out" == "$SHIM_MTIME" ]]
}
