#!/usr/bin/env bats

load helpers/hooks

USAGE_LINE="usage: release.sh start <X.Y.Z> [--adopt]
       release.sh status
       release.sh merge [plan/<slug>] [--force]
       release.sh finish (--check|--push|--publish) [--force] [--gh-release]"

# Message the merge fixtures write to $GIT_DIR/plan-squash/<slug>.msg.
PLAN_MSG="feat(widget): add the widget

Also fixes: the sprocket.
"

# Subjects of the two commits the fold fixtures put on the release branch.
ALPHA_SUBJECT="feat: add alpha"
BETA_SUBJECT="feat: add beta"

# CHANGELOG.md the release commit adds. Only the [0.1.0] section belongs in the
# GitHub release body; the older section must stay out of it.
CHANGELOG="# Changelog

## [0.1.0] - 2026-01-01

### Added

- The widget.

## [0.0.1] - 2025-12-01

### Added

- The sprocket.
"

# A CHANGELOG.md whose newest section predates the release being published.
CHANGELOG_WITHOUT_SECTION="# Changelog

## [0.0.1] - 2025-12-01

### Added

- The sprocket.
"

setup() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)
}

teardown() {
	cleanup_tmpdir_root
}

# ── Fixtures ─────────────────────────────────────────────────────────────────

# Work repo whose main is pushed to its bare origin, with a fresh release marker
# raised and main checked out; prints the work dir.
setup_release_pair() {
	local work
	work=$(setup_pair release)
	git -C "$work" push -q origin main
	raise_release_marker "$work"
	printf '%s' "$work"
}

# setup_release_pair with an open release: v0.1 cut from main, carrying the
# release key 0.1.0 and pushed to origin, left on main; prints the work dir.
setup_open_release() {
	local work
	work=$(setup_release_pair)
	git -C "$work" branch v0.1 main
	git -C "$work" config branch.v0.1.release 0.1.0
	git -C "$work" push -q origin v0.1
	printf '%s' "$work"
}

# Branch $2 in repo $1, cut from $3, holding one commit; leaves HEAD where it was.
add_branch_with_commit() {
	local repo="$1" branch="$2" from="$3" head
	head=$(git -C "$repo" symbolic-ref --short HEAD)
	git -C "$repo" switch -q -c "$branch" "$from"
	commit_file "$repo" "${branch//\//-}.txt" "work on $branch"
	git -C "$repo" switch -q "$head"
}

# ── merge fixtures ───────────────────────────────────────────────────────────

# Work repo whose trunk $2 (default main) is seeded to origin, with a plan/$1
# branch two commits ahead checked out, the trunk recorded as its base and a
# fresh release marker raised; prints the work dir.
setup_plan_repo() {
	local slug="$1" trunk="${2:-main}" work
	work=$(setup_pair plan "$trunk")
	seed_origin "$work" "$trunk"
	git -C "$work" switch -q -c "plan/$slug"
	commit_file "$work" WIDGET "first"
	commit_file "$work" SPROCKET "second"
	git -C "$work" config "branch.plan/$slug.planBase" "$trunk"
	raise_release_marker "$work"
	printf '%s' "$work"
}

# Work repo whose main and feature/x are seeded to origin, with a plan/widget
# branch two commits ahead of feature/x checked out, feature/x recorded as its
# base and a fresh release marker raised; prints the work dir.
setup_plan_repo_based_on_feature() {
	local work
	work=$(setup_pair plan)
	git -C "$work" switch -q -c feature/x
	commit_file "$work" FEATURE "feature work"
	seed_origin "$work" main feature/x
	git -C "$work" switch -q -c plan/widget
	commit_file "$work" WIDGET "first"
	commit_file "$work" SPROCKET "second"
	git -C "$work" config branch.plan/widget.planBase feature/x
	raise_release_marker "$work"
	printf '%s' "$work"
}

# setup_open_release with v0.1 carrying the alpha and beta commits (each
# touching its own file) pushed to origin, and an empty plan/x cut from it
# recording v0.1 as its base; leaves HEAD on plan/x, prints the work dir.
setup_release_with_commits() {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" alpha.txt "$ALPHA_SUBJECT"
	commit_file "$work" beta.txt "$BETA_SUBJECT"
	git -C "$work" push -q origin v0.1
	git -C "$work" switch -q -c plan/x
	git -C "$work" config branch.plan/x.planBase v0.1
	printf '%s' "$work"
}

# setup_release_with_commits with plan/x holding a fixup for each release
# commit and one ordinary commit, and gh reporting a successful run for the
# tip; prints the work dir.
setup_fold_repo() {
	local work
	work=$(setup_release_with_commits)
	commit_file "$work" alpha.txt "fixup! $ALPHA_SUBJECT"
	commit_file "$work" beta.txt "fixup! $BETA_SUBJECT"
	commit_file "$work" widget.txt "feat: add the widget"
	stub_gh "$(gh_runs completed success)"
	printf '%s' "$work"
}

# setup_open_release with a v0.1 whose beta commit rewrites the alpha commit's
# file, and a plan/x holding an alpha fixup that collides with that rewrite;
# gh reports a successful run. Prints the work dir.
setup_conflicting_fold_repo() {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" alpha.txt "$ALPHA_SUBJECT"
	commit_file "$work" alpha.txt "$BETA_SUBJECT"
	git -C "$work" push -q origin v0.1
	git -C "$work" switch -q -c plan/x
	git -C "$work" config branch.plan/x.planBase v0.1
	commit_file "$work" alpha.txt "fixup! $ALPHA_SUBJECT"
	stub_gh "$(gh_runs completed success)"
	printf '%s' "$work"
}

# setup_open_release with two v0.1 commits sharing the alpha subject and a
# plan/x holding a fixup for it; gh reports a successful run. Prints the work dir.
setup_ambiguous_fold_repo() {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" alpha.txt "$ALPHA_SUBJECT"
	commit_file "$work" alpha2.txt "$ALPHA_SUBJECT"
	git -C "$work" push -q origin v0.1
	git -C "$work" switch -q -c plan/x
	git -C "$work" config branch.plan/x.planBase v0.1
	commit_file "$work" gamma.txt "fixup! $ALPHA_SUBJECT"
	stub_gh "$(gh_runs completed success)"
	printf '%s' "$work"
}

# Path of the squash message file for slug $2 in the repo at $1.
msg_path() {
	printf '%s/plan-squash/%s.msg' "$(git -C "$1" rev-parse --absolute-git-dir)" "$2"
}

# Write $3 as the squash message for slug $2 in the repo at $1.
write_msg() {
	local path
	path=$(msg_path "$1" "$2")
	mkdir -p "$(dirname "$path")"
	printf '%s' "$3" >"$path"
}

# Writes $PLAN_MSG as plan/widget's squash message in $1 and stubs gh with a
# successful CI run — the message and CI gates most merge tests don't mean to
# exercise.
ready_widget_merge() {
	write_msg "$1" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
}

# Wire $1's push url to a copy of its origin whose branch $2 points elsewhere,
# so a lease taken on the fetched sha finds a remote that has moved.
diverge_push_target() {
	local work="$1" branch="$2" other
	other="${work%/work}/moved.git"
	git clone -q --bare "$(bare_of "$work")" "$other"
	git -C "$other" update-ref "refs/heads/$branch" "$(git -C "$work" rev-parse main)"
	git -C "$work" config remote.origin.pushurl "$other"
}

# ── finish fixtures ──────────────────────────────────────────────────────────

# setup_open_release with v0.1 holding one commit beyond main, pushed to origin
# and checked out; prints the work dir.
setup_finish_repo() {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" alpha.txt "$ALPHA_SUBJECT"
	git -C "$work" push -q origin v0.1
	printf '%s' "$work"
}

# setup_finish_repo with a release commit for 0.1.0 on the tip, tagged v0.1.0
# and not yet pushed. The commit adds CHANGELOG.md holding $1 (default
# $CHANGELOG); an empty $1 leaves the repo without a changelog. Prints the work
# dir.
setup_tagged_release() {
	local work changelog="${1-$CHANGELOG}"
	work=$(setup_finish_repo)
	if [[ -n "$changelog" ]]; then
		printf '%s' "$changelog" >"$work/CHANGELOG.md"
		git -C "$work" add CHANGELOG.md
	fi
	printf '0.1.0\n' >"$work/VERSION"
	git -C "$work" add VERSION
	git -C "$work" -c commit.gpgsign=false commit -q -m "chore: release v0.1.0"
	git -C "$work" tag -a v0.1.0 -m v0.1.0
	printf '%s' "$work"
}

# setup_tagged_release (passing $1 on) with the tagged tip pushed to origin and
# gh reporting a successful run for it; prints the work dir.
setup_publish_repo() {
	local work
	work=$(setup_tagged_release "$@")
	git -C "$work" push -q origin v0.1
	stub_gh "$(gh_runs completed success)"
	printf '%s' "$work"
}

# ── Stubs ────────────────────────────────────────────────────────────────────

# Runs JSON a `gh run list` stub answers with: status $1, conclusion $2.
gh_runs() {
	jq -nc --arg status "$1" --arg conclusion "$2" '[{status: $status, conclusion: $conclusion}]'
}

# Where the gh stub records one line per invocation.
gh_log_path() {
	printf '%s/gh.log' "$TMPDIR_ROOT"
}

# Where the gh stub copies the body of the last --notes-file it was handed.
gh_notes_path() {
	printf '%s/gh.notes' "$TMPDIR_ROOT"
}

# Stub gh on PATH so `gh run list` prints the runs JSON $1 (honouring --jq) and
# `gh release view` succeeds only when $2 is "present" (default "absent"). Every
# invocation appends its argv to the gh log; a release call also logs the tags
# origin carries at that moment, and a --notes-file body is copied aside.
stub_gh() {
	local bin="$TMPDIR_ROOT/bin"
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\nruns=%q\nrelease_state=%q\nlog=%q\nnotes=%q\n' \
		"$1" "${2:-absent}" "$(gh_log_path)" "$(gh_notes_path)" >"$bin/gh"
	cat >>"$bin/gh" <<-'STUB'
		printf '%s\n' "$*" >>"$log"
		args=("$@")
		jq_expr=""
		for ((i = 0; i < $#; i++)); do
			case "${args[i]}" in
			--jq) jq_expr="${args[i + 1]}" ;;
			--notes-file) cat "${args[i + 1]}" >"$notes" ;;
			esac
		done
		if [[ "$1" == release ]]; then
			printf 'origin-tags: %s\n' \
				"$(git ls-remote --tags origin 2>/dev/null | sed 's|.*refs/tags/||' | tr '\n' ' ')" >>"$log"
			[[ "$2" != view || "$release_state" == present ]] || exit 1
			exit 0
		fi
		if [[ -n "$jq_expr" ]]; then
			printf '%s' "$runs" | jq -r "$jq_expr"
		else
			printf '%s' "$runs"
		fi
	STUB
	chmod +x "$bin/gh"
}

# Stub gh on PATH so every invocation fails like a broken client.
stub_gh_failure() {
	local bin="$TMPDIR_ROOT/bin"
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\nprintf "gh: unauthenticated\\n" >&2\nexit 1\n' >"$bin/gh"
	chmod +x "$bin/gh"
}

# Puts a git on PATH that fails like a dead remote whenever an argument equals
# $1; every other invocation reaches the real git.
stub_git_failing_on() {
	local bin="$TMPDIR_ROOT/bin" real_git
	real_git=$(command -v git)
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\nreal_git=%q\nneedle=%q\n' "$real_git" "$1" >"$bin/git"
	cat >>"$bin/git" <<-'STUB'
		for arg in "$@"; do
			if [[ "$arg" == "$needle" ]]; then
				printf 'fatal: unable to access origin: connection refused\n' >&2
				exit 128
			fi
		done
		exec "$real_git" "$@"
	STUB
	chmod +x "$bin/git"
}

# ── Invocation ───────────────────────────────────────────────────────────────

# Run release.sh from $1 with remaining args.
run_release() {
	local work="$1"
	shift
	run_script "$work" "$RELEASE_SCRIPT" "$@"
}

# Run release.sh merge from $1 with remaining args, stubs first on PATH.
run_merge() {
	local work="$1"
	shift
	run_script_on_path "$work" "$TMPDIR_ROOT/bin:$PATH" "$RELEASE_SCRIPT" merge "$@"
}

# Run release.sh finish from $1 with remaining args, stubs first on PATH.
run_finish() {
	local work="$1"
	shift
	run_script_on_path "$work" "$TMPDIR_ROOT/bin:$PATH" "$RELEASE_SCRIPT" finish "$@"
}

# Same, on a hermetic PATH holding only the tools the script needs — no gh,
# whatever the host installs.
run_merge_without_gh() {
	local work="$1" bin="$TMPDIR_ROOT/nogh" tool
	shift
	mkdir -p "$bin"
	for tool in bash git stat date rm; do
		ln -sf "$(command -v "$tool")" "$bin/$tool"
	done
	run_script_on_path "$work" "$bin" "$RELEASE_SCRIPT" merge "$@"
}

# ── Assertions ───────────────────────────────────────────────────────────────

# Config key $2 of repo $1 holds exactly $3.
assert_config_at() {
	local repo="$1" key="$2" want="$3" got
	got=$(git -C "$repo" config --get "$key") || got="<unset>"
	[[ "$got" == "$want" ]] || {
		printf '%s is %s, expected %s\n' "$key" "$got" "$want" >&2
		return 1
	}
}

# Branch $2 of repo $1 tracks exactly $3.
assert_upstream_at() {
	local repo="$1" branch="$2" want="$3" got
	got=$(git -C "$repo" rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null) || got="<none>"
	[[ "$got" == "$want" ]] || {
		printf '%s tracks %s, expected %s\n' "$branch" "$got" "$want" >&2
		return 1
	}
}

# The run's stdout begins with exactly the line $1.
assert_first_line() {
	local want="$1" got
	got=${RUN_STDOUT%%$'\n'*}
	[[ "$got" == "$want" ]] || {
		printf 'first line is "%s", expected "%s"\nstdout: %s\n' "$got" "$want" "$RUN_STDOUT" >&2
		return 1
	}
}

# Some line of the run's stdout is exactly $1.
assert_stdout_line() {
	local want="$1" line
	while IFS= read -r line; do
		[[ "$line" == "$want" ]] && return 0
	done <<<"$RUN_STDOUT"
	printf 'no stdout line is exactly "%s"\nstdout: %s\n' "$want" "$RUN_STDOUT" >&2
	return 1
}

# Tag $2 of repo $1 points at commit $3.
assert_tag_at() {
	local repo="$1" tag="$2" want="$3" got
	got=$(git -C "$repo" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null) || got="<missing>"
	[[ "$got" == "$want" ]] || {
		printf 'tag %s is %s, expected %s\n' "$tag" "$got" "$want" >&2
		return 1
	}
}

# The gh stub recorded a call containing $1.
assert_gh_log_includes() {
	local pattern="$1" log
	log=$(cat "$(gh_log_path)" 2>/dev/null) || log=""
	[[ "$log" == *"$pattern"* ]] || {
		printf 'missing "%s" in gh log:\n%s\n' "$pattern" "$log" >&2
		return 1
	}
}

# The gh stub recorded no call containing $1.
assert_gh_log_excludes() {
	local pattern="$1" log
	log=$(cat "$(gh_log_path)" 2>/dev/null) || log=""
	[[ "$log" != *"$pattern"* ]] || {
		printf 'unexpected "%s" in gh log:\n%s\n' "$pattern" "$log" >&2
		return 1
	}
}

# The body the gh stub was handed as --notes-file.
gh_notes() {
	cat "$(gh_notes_path)" 2>/dev/null
}

# The last commit on branch $2 of repo $1 carries message $3 verbatim.
assert_commit_message() {
	local work="$1" branch="$2" want="$3" got
	got=$(git -C "$work" log -1 --format=%B "$branch")
	# Both sides lose their trailing newline to the substitution, so this is
	# content equality under git's own trailing-newline normalisation.
	[[ "$got" == "$(printf '%s' "$want")" ]] || {
		printf 'commit message on %s is:\n%s\nexpected:\n%s\n' "$branch" "$got" "$want" >&2
		return 1
	}
}

# Blob at revision path $2 of repo $1 (as `git show` reads it) holds exactly $3.
assert_blob_at() {
	local repo="$1" rev="$2" want="$3" got
	got=$(git -C "$repo" show "$rev" 2>/dev/null) || got="<missing>"
	[[ "$got" == "$want" ]] || {
		printf '%s is "%s", expected "%s"\n' "$rev" "$got" "$want" >&2
		return 1
	}
}

# Subjects of the commits $2 carries beyond its fork point with main, in repo $1.
release_subjects() {
	git -C "$1" log --format=%s "$(git -C "$1" merge-base main "$2")..$2"
}

# The commits $2 carries beyond main in repo $1 have exactly the subjects $3.
assert_release_subjects() {
	local repo="$1" rev="$2" want="$3" got
	got=$(release_subjects "$repo" "$rev")
	[[ "$got" == "$want" ]] || {
		printf 'commits beyond main on %s are:\n%s\nexpected:\n%s\n' "$rev" "$got" "$want" >&2
		return 1
	}
}

# Sha of the commit reachable from $2 in repo $1 whose subject is exactly $3.
commit_by_subject() {
	local repo="$1" rev="$2" want="$3" sha subject
	while read -r sha subject; do
		[[ "$subject" == "$want" ]] || continue
		printf '%s' "$sha"
		return 0
	done < <(git -C "$repo" log --format='%H %s' "$rev")
	printf '<no commit with subject %s>' "$want"
}

# Snapshot of the repo at $1 a run could change: HEAD, local refs, local config,
# origin refs, work tree.
repo_state() {
	local work="$1"
	git -C "$work" symbolic-ref HEAD
	git -C "$work" for-each-ref --format='%(refname) %(objectname)'
	git -C "$work" config --list --local
	git -C "$(bare_of "$work")" for-each-ref --format='%(refname) %(objectname)'
	git -C "$work" status --porcelain --untracked-files=all
}

# ── Marker gate ──────────────────────────────────────────────────────────────

@test "marker gate: a start without the marker is refused naming /release" {
	local work state_before
	work=$(setup_release_pair)
	rm -f "$(release_marker_path "$work")"
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "/release"
	assert_repo_state "$work" "$state_before"
}

@test "marker gate: the missing marker is the reason even when later checks would fail too" {
	local work
	work=$(setup_release_pair)
	rm -f "$(release_marker_path "$work")"
	git -C "$work" switch -q -c feature/x
	printf 'dirty\n' >"$work/README"

	run_release "$work" start nonsense

	assert_refused
	assert_reason "/release"
}

@test "marker gate: a stale marker reads as absent" {
	local work
	work=$(setup_release_pair)
	backdate_release_marker "$work" "$STALE_OFFSET_MINUTES"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "/release"
	assert_ref_absent "$work" v1.2
}

@test "marker gate: a future-dated marker reads as absent" {
	local work
	work=$(setup_release_pair)
	backdate_release_marker "$work" "$FUTURE_OFFSET_MINUTES"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "/release"
	assert_ref_absent "$work" v1.2
}

@test "marker gate: a stat that answers neither dialect is named instead of reading as no marker" {
	local work bin
	work=$(setup_release_pair)
	bin=$(failing_stat_bin "$TMPDIR_ROOT/nostat")

	run_script_on_path "$work" "$bin:$PATH" "$RELEASE_SCRIPT" start 1.2.0

	assert_run_failed 1
	assert_reason "marker age cannot be read"
	assert_ref_absent "$work" v1.2
}

@test "marker gate: status runs without a marker" {
	local work
	work=$(setup_open_release)
	rm -f "$(release_marker_path "$work")"

	run_release "$work" status

	assert_run_ok
	assert_first_line "release: v0.1 0.1.0"
}

@test "marker gate: a merge without the marker is refused naming /release before the branch check" {
	local work
	work=$(setup_plan_repo widget)
	rm -f "$(release_marker_path "$work")"
	git -C "$work" switch -q main

	run_merge "$work"

	assert_refused
	assert_reason "/release"
	assert_stderr_excludes "is not a plan branch"
}

@test "marker gate: a finish without the marker is refused naming /release before the branch check" {
	local work
	work=$(setup_finish_repo)
	rm -f "$(release_marker_path "$work")"
	git -C "$work" switch -q main

	run_finish "$work" --check

	assert_refused
	assert_reason "/release"
	assert_stderr_excludes "not on a release branch"
}

# ── Arguments ────────────────────────────────────────────────────────────────

@test "arguments: --help prints the usage line on stdout and succeeds" {
	local work
	work=$(setup_release_pair)

	run_release "$work" --help

	assert_help_printed
}

@test "arguments: -h outside a git repo prints the usage line on stdout and succeeds" {
	local dir="$TMPDIR_ROOT/nogit"
	mkdir -p "$dir"
	export GIT_CEILING_DIRECTORIES="$TMPDIR_ROOT"

	run_release "$dir" -h

	assert_help_printed
}

@test "arguments: --help after a subcommand without the marker prints usage and changes nothing" {
	local work state_before
	work=$(setup_release_pair)
	rm -f "$(release_marker_path "$work")"
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 --help

	assert_help_printed
	assert_repo_state "$work" "$state_before"
	assert_absent "$(release_marker_path "$work")"
}

@test "arguments: an unknown subcommand is refused naming it with the usage line" {
	local work
	work=$(setup_release_pair)

	run_release "$work" bogus

	assert_refused
	assert_reason "unknown subcommand 'bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: no subcommand is refused with the usage line" {
	local work
	work=$(setup_release_pair)

	run_release "$work"

	assert_refused
	assert_reason "$USAGE_LINE"
}

@test "arguments: an unknown option is refused naming it with the usage line" {
	local work
	work=$(setup_release_pair)

	run_release "$work" start 1.2.0 --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: an unknown option after status is refused naming it with the usage line" {
	local work
	work=$(setup_open_release)

	run_release "$work" status --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: a bare argument after status is refused naming it with the usage line" {
	local work
	work=$(setup_open_release)

	run_release "$work" status extra

	assert_refused
	assert_reason "'extra'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: an unknown option after merge is refused naming it with the usage line" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: an unknown option after finish is refused naming it with the usage line" {
	local work
	work=$(setup_finish_repo)

	run_release "$work" finish --check --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

# ── start ────────────────────────────────────────────────────────────────────

@test "start: cuts vX.Y from main, records the version, pushes it with upstream, and ends on it" {
	local work main_before
	work=$(setup_release_pair)
	main_before=$(git -C "$work" rev-parse main)

	run_release "$work" start 1.2.0

	assert_run_ok
	assert_rev_at "$work" v1.2 "$main_before"
	assert_config_at "$work" branch.v1.2.release 1.2.0
	assert_ref_at "$(bare_of "$work")" v1.2 "$main_before"
	assert_upstream_at "$work" v1.2 origin/v1.2
	assert_on_branch "$work" v1.2
}

@test "start: a failed push keeps the branch and its key and exits 1 naming the push" {
	local work main_before
	work=$(setup_release_pair)
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"
	main_before=$(git -C "$work" rev-parse main)

	run_release "$work" start 1.2.0

	assert_run_failed 1
	assert_reason "pushing v1.2 to origin failed"
	assert_rev_at "$work" v1.2 "$main_before"
	assert_config_at "$work" branch.v1.2.release 1.2.0
	assert_ref_absent "$(bare_of "$work")" v1.2
}

@test "start: off main is refused naming the branch" {
	local work state_before
	work=$(setup_release_pair)
	git -C "$work" switch -q -c feature/x
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "feature/x"
	assert_reason "main"
	assert_repo_state "$work" "$state_before"
}

@test "start: an unstaged change is refused as unstaged" {
	local work
	work=$(setup_release_pair)
	printf 'dirty\n' >"$work/README"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "unstaged changes"
	assert_ref_absent "$work" v1.2
}

@test "start: a staged change is refused as staged" {
	local work
	work=$(setup_release_pair)
	printf 'staged\n' >"$work/README"
	git -C "$work" add README

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "staged changes"
	assert_ref_absent "$work" v1.2
}

@test "start: a main behind origin/main is refused as out of sync" {
	local work
	work=$(setup_release_pair)
	advance_origin_main "$work"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "differs from origin/main"
	assert_ref_absent "$work" v1.2
}

@test "start: an unreachable origin is refused as a failed fetch" {
	local work
	work=$(setup_release_pair)
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "'git fetch origin main' failed"
	assert_ref_absent "$work" v1.2
}

@test "start: an existing branch carrying a release key is refused naming it" {
	local work state_before
	work=$(setup_open_release)
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "v0.1"
	assert_repo_state "$work" "$state_before"
}

@test "start: an existing vX.Y branch is refused naming it" {
	local work state_before
	work=$(setup_release_pair)
	git -C "$work" branch v1.2 main
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "v1.2 already exists"
	assert_repo_state "$work" "$state_before"
}

@test "start: a version that is not X.Y.Z is refused naming it" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" start v1.2

	assert_refused
	assert_reason "'v1.2'"
	assert_repo_state "$work" "$state_before"
}

@test "start: a second bare argument is refused naming it" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 1.3.0

	assert_refused
	assert_reason "'1.3.0'"
	assert_repo_state "$work" "$state_before"
}

@test "start: a missing version is refused asking for one" {
	local work
	work=$(setup_release_pair)

	run_release "$work" start

	assert_refused
	assert_reason "start needs a version"
}

# ── start --adopt ────────────────────────────────────────────────────────────

@test "adopt: records the version on the current branch without cutting or pushing" {
	local work bare_before
	work=$(setup_release_pair)
	add_branch_with_commit "$work" v1.2 main
	git -C "$work" switch -q v1.2
	bare_before=$(git -C "$(bare_of "$work")" for-each-ref --format='%(refname) %(objectname)')

	run_release "$work" start 1.2.0 --adopt

	assert_run_ok
	assert_config_at "$work" branch.v1.2.release 1.2.0
	assert_on_branch "$work" v1.2
	[[ "$(git -C "$(bare_of "$work")" for-each-ref --format='%(refname) %(objectname)')" == "$bare_before" ]]
}

@test "adopt: on main is refused" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 --adopt

	assert_refused
	assert_reason "main"
	assert_repo_state "$work" "$state_before"
}

@test "adopt: a branch already carrying a release key is refused naming it" {
	local work state_before
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 --adopt

	assert_refused
	assert_reason "v0.1"
	assert_repo_state "$work" "$state_before"
}

@test "adopt: a branch that does not contain main is refused" {
	local work state_before
	work=$(setup_release_pair)
	add_branch_with_commit "$work" v1.2 main
	commit_file "$work" MOVED "main moved on"
	git -C "$work" switch -q v1.2
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 --adopt

	assert_refused
	assert_reason "does not contain main"
	assert_repo_state "$work" "$state_before"
}

# ── status ───────────────────────────────────────────────────────────────────

@test "status: with no release open prints exactly one line" {
	local work
	work=$(setup_release_pair)

	run_release "$work" status

	assert_run_ok
	[[ "$RUN_STDOUT" == "release: none" ]] || {
		printf 'stdout is:\n%s\nexpected only "release: none"\n' "$RUN_STDOUT" >&2
		return 1
	}
}

@test "status: from a plan branch the first line names the release branch and its version" {
	local work
	work=$(setup_open_release)
	add_branch_with_commit "$work" plan/widget v0.1
	git -C "$work" switch -q plan/widget

	run_release "$work" status

	assert_run_ok
	assert_first_line "release: v0.1 0.1.0"
}

@test "status: lists the commits the release carries beyond main" {
	local work short
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" FEATURE "feat: add the widget"
	short=$(git -C "$work" rev-parse --short v0.1)

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "$short feat: add the widget"
}

@test "status: lists only the unmerged plan branches recorded against the release" {
	local work
	work=$(setup_open_release)
	add_branch_with_commit "$work" plan/widget v0.1
	git -C "$work" config branch.plan/widget.planBase v0.1
	git -C "$work" branch plan/landed v0.1
	git -C "$work" config branch.plan/landed.planBase v0.1
	add_branch_with_commit "$work" plan/other main
	git -C "$work" config branch.plan/other.planBase main

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "plan/widget"
	assert_stdout_excludes "plan/landed"
	assert_stdout_excludes "plan/other"
}

@test "status: an untouched release is in sync with origin and holds nothing beyond main" {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "commits beyond main: none"
	assert_stdout_includes "unmerged plan branches: none"
	assert_stdout_includes "origin/v0.1: 0 ahead, 0 behind"
	assert_stdout_includes "main: is an ancestor of v0.1"
}

@test "status: reports the release ahead of origin from the tracking ref without fetching" {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" FEATURE "feat: add the widget"
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "origin/v0.1: 1 ahead, 0 behind"
	assert_stderr_excludes "fatal"
}

@test "status: reports the release behind origin" {
	local work
	work=$(setup_open_release)
	advance_origin_branch "$work" v0.1
	git -C "$work" fetch -q origin

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "origin/v0.1: 0 ahead, 1 behind"
}

@test "status: reports a release branch origin does not have" {
	local work
	work=$(setup_release_pair)
	git -C "$work" branch v0.1 main
	git -C "$work" config branch.v0.1.release 0.1.0

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "origin/v0.1: absent"
}

@test "status: reports main moved past the fork point" {
	local work
	work=$(setup_open_release)
	commit_file "$work" MOVED "main moved on"

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "main: has moved past the fork point"
}

# ── merge: branch resolution ─────────────────────────────────────────────────

@test "merge: naming two branches is refused" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" plan/widget plan/other

	assert_refused
	assert_reason "only one branch may be named"
}

@test "merge: no argument off a plan branch is refused naming the branch" {
	local work
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" switch -q -c feature/other

	run_merge "$work"

	assert_refused
	assert_reason "feature/other"
}

@test "merge: a detached HEAD with no argument is refused asking for the branch" {
	local work
	work=$(setup_plan_repo widget)
	git -C "$work" switch -q --detach HEAD

	run_merge "$work"

	assert_refused
	assert_reason "HEAD is detached"
}

@test "merge: a named plan branch that does not exist is refused" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" plan/absent

	assert_refused
	assert_reason "not a local branch"
}

@test "merge: an explicit plan branch is merged from main" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" switch -q main
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work" plan/widget

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
	assert_on_branch "$work" main
}

# ── merge: recorded base ─────────────────────────────────────────────────────

@test "merge: a recorded master takes the squash and is pushed to origin/master" {
	local work bare master_before squashed
	work=$(setup_plan_repo widget master)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	master_before=$(git -C "$work" rev-parse master)

	run_merge "$work"

	assert_run_ok
	assert_rev_at "$work" master^ "$master_before"
	assert_commit_message "$work" master "$PLAN_MSG"
	squashed=$(git -C "$work" rev-parse master)
	assert_ref_at "$bare" master "$squashed"
	assert_on_branch "$work" master
}

@test "merge: a plan branch with no recorded base is refused naming the key and plan-branch.sh" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" config --unset branch.plan/widget.planBase
	state_before=$(repo_state "$work")

	run_merge "$work"

	assert_refused
	assert_reason "branch.plan/widget.planBase"
	assert_reason "plan-branch.sh"
	assert_repo_state "$work" "$state_before"
}

@test "merge: the squash lands on the recorded branch and leaves main untouched" {
	local work bare feature_before main_before branch_tree squashed
	work=$(setup_plan_repo_based_on_feature)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	seed_origin "$work" plan/widget
	feature_before=$(git -C "$work" rev-parse feature/x)
	main_before=$(git -C "$work" rev-parse main)
	branch_tree=$(git -C "$work" rev-parse "plan/widget^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_stdout_includes "feature/x"
	assert_rev_at "$work" "feature/x^" "$feature_before"
	assert_rev_at "$work" "feature/x^{tree}" "$branch_tree"
	assert_commit_message "$work" feature/x "$PLAN_MSG"
	assert_rev_at "$work" main "$main_before"
	squashed=$(git -C "$work" rev-parse feature/x)
	assert_ref_at "$bare" feature/x "$squashed"
	assert_ref_at "$bare" main "$main_before"
	assert_ref_absent "$work" plan/widget
	assert_ref_absent "$bare" plan/widget
	assert_on_branch "$work" feature/x
}

@test "merge: a base behind its origin counterpart is refused as out of sync" {
	local work feature_before
	work=$(setup_plan_repo_based_on_feature)
	ready_widget_merge "$work"
	advance_origin_branch "$work" feature/x
	feature_before=$(git -C "$work" rev-parse feature/x)

	run_merge "$work"

	assert_refused
	assert_reason "differs from origin/feature/x"
	assert_rev_at "$work" feature/x "$feature_before"
	assert_ref_present "$work" plan/widget
}

@test "merge: a recorded branch that no longer exists locally is refused naming it" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" config branch.plan/widget.planBase feature/gone
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "feature/gone"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" plan/widget
}

@test "merge: a base holding a commit the plan branch lacks is refused until rebased" {
	local work feature_before
	work=$(setup_plan_repo_based_on_feature)
	ready_widget_merge "$work"
	git -C "$work" switch -q feature/x
	commit_file "$work" ahead.txt "feature moved ahead"
	git -C "$work" push -q origin feature/x
	git -C "$work" switch -q plan/widget
	feature_before=$(git -C "$work" rev-parse feature/x)

	run_merge "$work"

	assert_refused
	assert_reason "rebase"
	assert_rev_at "$work" feature/x "$feature_before"
	assert_ref_present "$work" plan/widget
}

# ── merge: clean tree ────────────────────────────────────────────────────────

@test "merge: an unstaged change is refused as unstaged" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	printf 'dirty\n' >"$work/README"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "unstaged changes"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: a staged change is refused as staged" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	printf 'staged\n' >"$work/README"
	git -C "$work" add README
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "staged changes"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: --force skips the CI gate only and still refuses an unstaged change" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	printf 'dirty\n' >"$work/README"
	state_before=$(repo_state "$work")

	run_merge "$work" --force

	assert_refused
	assert_reason "unstaged changes"
	assert_repo_state "$work" "$state_before"
}

# ── merge: message file ──────────────────────────────────────────────────────

@test "merge: a missing message file is refused naming its path" {
	local work main_before
	work=$(setup_plan_repo widget)
	stub_gh "$(gh_runs completed success)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "no squash message at $(msg_path "$work" widget)"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: an empty message file is refused as empty" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget ""
	stub_gh "$(gh_runs completed success)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "is empty"
	assert_rev_at "$work" main "$main_before"
}

# ── merge: base sync ─────────────────────────────────────────────────────────

@test "merge: a main behind origin/main is refused as out of sync" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	advance_origin_main "$work"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "differs from origin/main"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: an unreachable origin is refused as a failed fetch" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "'git fetch origin main' failed"
	assert_rev_at "$work" main "$main_before"
}

# ── merge: plan branch sync ──────────────────────────────────────────────────

@test "merge: an origin copy of the plan branch at another tip is refused as out of sync" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	seed_origin "$work" plan/widget
	git -C "$work" fetch -q origin
	commit_file "$work" LATER "third"
	state_before=$(repo_state "$work")

	run_merge "$work"

	assert_refused
	assert_reason "plan/widget"
	assert_reason "push"
	assert_repo_state "$work" "$state_before"
}

# ── merge: CI gate ───────────────────────────────────────────────────────────

@test "merge: a failed CI run is refused naming its conclusion" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed failure)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "failure"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: an unfinished CI run is refused naming its status" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs in_progress "")"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "in_progress"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: a missing gh without --force is refused naming gh" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	main_before=$(git -C "$work" rev-parse main)

	run_merge_without_gh "$work"

	assert_refused
	assert_reason "gh is not installed"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: a failing gh client is refused as a failed run lookup" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh_failure
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "'gh run list' failed"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: a missing CI run for the branch tip is refused as no run found" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh '[]'
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "no CI run found"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: --force merges despite a failed CI run" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed failure)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work" --force

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
}

# ── merge: squash ────────────────────────────────────────────────────────────

@test "merge: a never-pushed branch lands as one commit with the branch tree and the message verbatim, and is gone" {
	local work main_before branch_tree
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	main_before=$(git -C "$work" rev-parse main)
	branch_tree=$(git -C "$work" rev-parse "plan/widget^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
	assert_rev_at "$work" "main^{tree}" "$branch_tree"
	assert_commit_message "$work" main "$PLAN_MSG"
	assert_ref_absent "$work" plan/widget
	assert_ref_absent "$(bare_of "$work")" plan/widget
	assert_stderr_excludes "fatal"
	assert_stderr_excludes "ls-remote"
}

@test "merge: a branch equal to its fetched origin copy lands, and origin/main, both branch copies, and the message file follow" {
	local work bare msg squashed
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	seed_origin "$work" plan/widget
	git -C "$work" fetch -q origin

	run_merge "$work"

	assert_run_ok
	squashed=$(git -C "$work" rev-parse main)
	assert_ref_at "$bare" main "$squashed"
	assert_ref_absent "$work" plan/widget
	assert_ref_absent "$bare" plan/widget
	assert_absent "$msg"
	assert_on_branch "$work" main
}

@test "merge: a message body line starting with # survives the commit" {
	local work msg
	msg="fix(widget): drop the sprocket

#12 was the tracking issue.
"
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$msg"
	stub_gh "$(gh_runs completed success)"

	run_merge "$work"

	assert_run_ok
	assert_commit_message "$work" main "$msg"
}

# ── merge: push and cleanup failures ─────────────────────────────────────────

@test "merge: a failed push keeps the squash commit, the branch, and the message file" {
	local work main_before msg
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_run_failed 1
	assert_reason "pushing main to origin failed"
	assert_rev_at "$work" main^ "$main_before"
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}

@test "merge: a failing ls-remote is reported and leaves the branches in place" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	seed_origin "$work" plan/widget
	stub_git_failing_on ls-remote

	run_merge "$work"

	assert_run_failed 1
	assert_reason "ls-remote"
	assert_ref_at "$bare" main "$(git -C "$work" rev-parse main)"
	assert_ref_present "$bare" plan/widget
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}

@test "merge: a failing remote deletion is reported after the base is pushed" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	seed_origin "$work" plan/widget
	stub_git_failing_on --delete

	run_merge "$work"

	assert_run_failed 1
	assert_reason "deleting plan/widget from origin failed"
	assert_ref_at "$bare" main "$(git -C "$work" rev-parse main)"
	assert_ref_present "$bare" plan/widget
	assert_present "$msg"
}

@test "merge: a failing local branch deletion is reported after the base is pushed" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	stub_git_failing_on -D

	run_merge "$work"

	assert_run_failed 1
	assert_reason "deleting the local plan/widget failed"
	assert_ref_at "$bare" main "$(git -C "$work" rev-parse main)"
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}

# ── merge: fixup fold ────────────────────────────────────────────────────────

@test "merge: each fixup lands in its release commit and the plan work becomes one squash commit on top" {
	local work bare subjects_before tip_before plan_tree msg
	work=$(setup_fold_repo)
	bare=$(bare_of "$work")
	write_msg "$work" x "$PLAN_MSG"
	msg=$(msg_path "$work" x)
	seed_origin "$work" plan/x
	subjects_before=$(release_subjects "$work" v0.1)
	tip_before=$(git -C "$work" rev-parse v0.1)
	plan_tree=$(git -C "$work" rev-parse "plan/x^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_blob_at "$work" "$(commit_by_subject "$work" v0.1 "$ALPHA_SUBJECT"):alpha.txt" "fixup! $ALPHA_SUBJECT"
	assert_rev_at "$work" "v0.1^{tree}" "$plan_tree"
	assert_commit_message "$work" v0.1 "$PLAN_MSG"
	assert_ref_at "$bare" v0.1 "$(git -C "$work" rev-parse v0.1)"
	assert_ref_absent "$work" plan/x
	assert_ref_absent "$bare" plan/x
	assert_absent "$msg"
	assert_on_branch "$work" v0.1
	assert_stdout_includes "$tip_before"
}

@test "merge: an all-fixup branch folds without a squash commit and needs no message file" {
	local work subjects_before plan_tree
	work=$(setup_release_with_commits)
	commit_file "$work" alpha.txt "fixup! $ALPHA_SUBJECT"
	commit_file "$work" beta.txt "fixup! $BETA_SUBJECT"
	stub_gh "$(gh_runs completed success)"
	subjects_before=$(release_subjects "$work" v0.1)
	plan_tree=$(git -C "$work" rev-parse "plan/x^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_release_subjects "$work" v0.1 "$subjects_before"
	assert_rev_at "$work" "v0.1^{tree}" "$plan_tree"
	assert_ref_absent "$work" plan/x
	assert_on_branch "$work" v0.1
}

@test "merge: ordinary commits among the fixups still land as one squash commit" {
	local work subjects_before plan_tree
	work=$(setup_release_with_commits)
	commit_file "$work" widget.txt "feat: add the widget"
	commit_file "$work" alpha.txt "fixup! $ALPHA_SUBJECT"
	commit_file "$work" sprocket.txt "feat: add the sprocket"
	commit_file "$work" beta.txt "fixup! $BETA_SUBJECT"
	write_msg "$work" x "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	subjects_before=$(release_subjects "$work" v0.1)
	plan_tree=$(git -C "$work" rev-parse "plan/x^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_rev_at "$work" "v0.1^{tree}" "$plan_tree"
	assert_commit_message "$work" v0.1 "$PLAN_MSG"
}

@test "merge: an all-fixup fold moves origin's release branch and deletes the plan branch there" {
	local work bare
	work=$(setup_release_with_commits)
	commit_file "$work" alpha.txt "fixup! $ALPHA_SUBJECT"
	commit_file "$work" beta.txt "fixup! $BETA_SUBJECT"
	stub_gh "$(gh_runs completed success)"
	seed_origin "$work" plan/x
	bare=$(bare_of "$work")

	run_merge "$work"

	assert_run_ok
	assert_ref_at "$bare" v0.1 "$(git -C "$work" rev-parse v0.1)"
	assert_ref_absent "$bare" plan/x
}

@test "merge: a conflicting fixup aborts the rebase and leaves both branches as found" {
	local work plan_before base_before
	work=$(setup_conflicting_fold_repo)
	plan_before=$(git -C "$work" rev-parse plan/x)
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "fixup! $ALPHA_SUBJECT"
	assert_reason "the rebase was aborted"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_on_branch "$work" plan/x
	assert_absent "$(git -C "$work" rev-parse --absolute-git-dir)/rebase-merge"
}

@test "merge: a conflicting fixup named from another branch ends on the branch the run started from" {
	local work plan_before base_before
	work=$(setup_conflicting_fold_repo)
	git -C "$work" switch -q v0.1
	plan_before=$(git -C "$work" rev-parse plan/x)
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work" plan/x

	assert_refused
	assert_reason "fixup! $ALPHA_SUBJECT"
	assert_reason "the rebase was aborted"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_on_branch "$work" v0.1
	assert_absent "$(git -C "$work" rev-parse --absolute-git-dir)/rebase-merge"
}

@test "merge: a fixup on a base without a release key is refused as needing a release branch" {
	local work main_before
	work=$(setup_plan_repo widget)
	commit_file "$work" README "fixup! init"
	ready_widget_merge "$work"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "release branch"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" plan/widget
}

@test "merge: a fixup naming no release commit is refused naming the fixup" {
	local work base_before
	work=$(setup_release_with_commits)
	commit_file "$work" gamma.txt "fixup! feat: add gamma"
	stub_gh "$(gh_runs completed success)"
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "fixup! feat: add gamma"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

@test "merge: a fixup naming a commit older than the fork point is refused naming the fixup" {
	local work base_before
	work=$(setup_release_with_commits)
	commit_file "$work" gamma.txt "fixup! init"
	stub_gh "$(gh_runs completed success)"
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "fixup! init"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

@test "merge: a fixup naming two release commits is refused naming both" {
	local work base_before first second
	work=$(setup_ambiguous_fold_repo)
	base_before=$(git -C "$work" rev-parse v0.1)
	first=$(git -C "$work" rev-parse --short "v0.1^")
	second=$(git -C "$work" rev-parse --short v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "$first"
	assert_reason "$second"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

@test "merge: another plan branch recording the same base is refused naming it" {
	local work base_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	git -C "$work" branch plan/other v0.1
	git -C "$work" config branch.plan/other.planBase v0.1
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "plan/other"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

@test "merge: a rejected lease keeps the fold local and says the remote moved" {
	local work msg plan_tree
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	msg=$(msg_path "$work" x)
	plan_tree=$(git -C "$work" rev-parse "plan/x^{tree}")
	diverge_push_target "$work" v0.1

	run_merge "$work"

	assert_run_failed 1
	assert_reason "origin/v0.1 moved"
	assert_reason "git fetch"
	assert_rev_at "$work" "v0.1^{tree}" "$plan_tree"
	assert_commit_message "$work" v0.1 "$PLAN_MSG"
	assert_ref_present "$work" plan/x
	assert_present "$msg"
}

@test "merge: a failed move of the release branch says the fold is on the plan branch" {
	local work base_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	stub_git_failing_on --force
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_run_failed 1
	assert_reason "moving v0.1 onto the folded commits failed"
	assert_reason "the fold is on plan/x"
	assert_reason "v0.1 is untouched"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

# ── finish: mode flags ───────────────────────────────────────────────────────

@test "finish: no mode flag is refused with the usage line" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" finish

	assert_refused
	assert_reason "$USAGE_LINE"
	assert_repo_state "$work" "$state_before"
}

@test "finish: two mode flags are refused with the usage line" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" finish --check --publish

	assert_refused
	assert_reason "$USAGE_LINE"
	assert_repo_state "$work" "$state_before"
}

@test "finish: --force outside --publish is refused naming the flag" {
	local work state_before
	work=$(setup_finish_repo)
	state_before=$(repo_state "$work")

	run_release "$work" finish --check --force

	assert_refused
	assert_reason "--force"
	assert_repo_state "$work" "$state_before"
}

@test "finish: --gh-release outside --publish is refused naming the flag" {
	local work state_before
	work=$(setup_finish_repo)
	state_before=$(repo_state "$work")

	run_release "$work" finish --push --gh-release

	assert_refused
	assert_reason "--gh-release"
	assert_repo_state "$work" "$state_before"
}

# ── finish --check ───────────────────────────────────────────────────────────

@test "finish --check: off a release branch is refused" {
	local work state_before
	work=$(setup_finish_repo)
	git -C "$work" switch -q main
	state_before=$(repo_state "$work")

	run_finish "$work" --check

	assert_refused
	assert_reason "not on a release branch"
	assert_repo_state "$work" "$state_before"
}

@test "finish --check: an unstaged change is refused as unstaged" {
	local work
	work=$(setup_finish_repo)
	printf 'dirty\n' >"$work/README"

	run_finish "$work" --check

	assert_refused
	assert_reason "unstaged changes"
}

@test "finish --check: a staged change is refused as staged" {
	local work
	work=$(setup_finish_repo)
	printf 'staged\n' >"$work/README"
	git -C "$work" add README

	run_finish "$work" --check

	assert_refused
	assert_reason "staged changes"
}

@test "finish --check: a plan branch recording the release is refused naming it" {
	local work
	work=$(setup_finish_repo)
	add_branch_with_commit "$work" plan/widget v0.1
	git -C "$work" config branch.plan/widget.planBase v0.1

	run_finish "$work" --check

	assert_refused
	assert_reason "plan/widget"
}

@test "finish --check: a release ahead of its origin counterpart is refused as out of sync" {
	local work
	work=$(setup_finish_repo)
	commit_file "$work" gamma.txt "feat: add gamma"

	run_finish "$work" --check

	assert_refused
	assert_reason "differs from origin/v0.1"
}

@test "finish --check: an unreachable origin is refused as a failed fetch" {
	local work
	work=$(setup_finish_repo)
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"

	run_finish "$work" --check

	assert_refused
	assert_reason "git fetch origin"
	assert_reason "failed"
}

@test "finish --check: a main behind origin/main is refused as out of sync" {
	local work
	work=$(setup_finish_repo)
	advance_origin_main "$work"

	run_finish "$work" --check

	assert_refused
	assert_reason "differs from origin/main"
}

@test "finish --check: a main that has moved past the release is refused saying to rebase" {
	local work
	work=$(setup_finish_repo)
	git -C "$work" switch -q main
	commit_file "$work" MOVED "main moved on"
	git -C "$work" push -q origin main
	git -C "$work" switch -q v0.1

	run_finish "$work" --check

	assert_refused
	assert_reason "rebase"
}

@test "finish --check: a ready release prints the version as a line a skill can parse" {
	local work
	work=$(setup_finish_repo)

	run_finish "$work" --check

	assert_run_ok
	assert_stdout_line "version: 0.1.0"
}

# ── finish --push ────────────────────────────────────────────────────────────

@test "finish --push: a tip without the version tag is refused naming the tag it wants" {
	local work bare tip
	work=$(setup_finish_repo)
	bare=$(bare_of "$work")
	tip=$(git -C "$work" rev-parse v0.1)

	run_finish "$work" --push

	assert_refused
	assert_reason "tag"
	assert_reason "v0.1.0"
	assert_ref_at "$bare" v0.1 "$tip"
}

@test "finish --push: a tip that is not the release commit is refused naming the subject found" {
	local work
	work=$(setup_finish_repo)
	git -C "$work" tag -a v0.1.0 -m v0.1.0

	run_finish "$work" --push

	assert_refused
	assert_reason "$ALPHA_SUBJECT"
}

@test "finish --push: pushes the tagged release commit and prints its sha as a line a skill can parse" {
	local work tip
	work=$(setup_tagged_release)
	tip=$(git -C "$work" rev-parse v0.1)

	run_finish "$work" --push

	assert_run_ok
	assert_ref_at "$(bare_of "$work")" v0.1 "$tip"
	assert_stdout_line "commit: $tip"
	assert_on_branch "$work" v0.1
}

@test "finish --push: a rejected push changes nothing and exits 1 naming the push" {
	local work bare tip origin_before
	work=$(setup_tagged_release)
	bare=$(bare_of "$work")
	advance_origin_branch "$work" v0.1
	tip=$(git -C "$work" rev-parse v0.1)
	origin_before=$(git -C "$bare" rev-parse v0.1)

	run_finish "$work" --push

	assert_run_failed 1
	assert_reason "pushing v0.1 to origin failed"
	assert_rev_at "$work" v0.1 "$tip"
	assert_ref_at "$bare" v0.1 "$origin_before"
}

# ── finish --publish ─────────────────────────────────────────────────────────

@test "finish --publish: an unstaged change is refused as unstaged" {
	local work state_before
	work=$(setup_publish_repo)
	printf 'dirty\n' >"$work/README"
	state_before=$(repo_state "$work")

	run_finish "$work" --publish

	assert_refused
	assert_reason "unstaged changes"
	assert_repo_state "$work" "$state_before"
}

@test "finish --publish: a staged change is refused as staged" {
	local work state_before
	work=$(setup_publish_repo)
	printf 'staged\n' >"$work/README"
	git -C "$work" add README
	state_before=$(repo_state "$work")

	run_finish "$work" --publish

	assert_refused
	assert_reason "staged changes"
	assert_repo_state "$work" "$state_before"
}

@test "finish --publish: a plan branch recording the release is refused naming it" {
	local work state_before
	work=$(setup_publish_repo)
	add_branch_with_commit "$work" plan/widget v0.1
	git -C "$work" config branch.plan/widget.planBase v0.1
	state_before=$(repo_state "$work")

	run_finish "$work" --publish

	assert_refused
	assert_reason "plan/widget"
	assert_repo_state "$work" "$state_before"
}

@test "finish --publish: a failed CI run is refused naming its conclusion" {
	local work main_before
	work=$(setup_publish_repo)
	stub_gh "$(gh_runs completed failure)"
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "failure"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
	assert_config_at "$work" branch.v0.1.release 0.1.0
}

@test "finish --publish: --force publishes despite a failed CI run" {
	local work tip
	work=$(setup_publish_repo)
	stub_gh "$(gh_runs completed failure)"
	tip=$(git -C "$work" rev-parse v0.1)

	run_finish "$work" --publish --force

	assert_run_ok
	assert_rev_at "$work" main "$tip"
	assert_on_branch "$work" main
}

@test "finish --publish: a main behind origin/main is refused as out of sync" {
	local work main_before
	work=$(setup_publish_repo)
	advance_origin_main "$work"
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "differs from origin/main"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: a main that has moved past the release is refused as not an ancestor" {
	local work main_before
	work=$(setup_publish_repo)
	git -C "$work" switch -q main
	commit_file "$work" MOVED "main moved on"
	git -C "$work" push -q origin main
	git -C "$work" switch -q v0.1
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "ancestor"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: a tag that does not point at the tip is refused naming it" {
	local work main_before
	work=$(setup_publish_repo)
	git -C "$work" tag -d v0.1.0
	git -C "$work" tag v0.1.0 "v0.1^"
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "v0.1.0"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: a repo without the version tag is refused naming the missing tag" {
	local work main_before
	work=$(setup_publish_repo)
	git -C "$work" tag -d v0.1.0
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "no v0.1.0 tag"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: a release ahead of its origin counterpart is refused as out of sync" {
	local work main_before
	work=$(setup_publish_repo)
	advance_origin_branch "$work" v0.1
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "differs from origin/v0.1"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: fast-forwards main, pushes it with the tag, drops the branch and its key, and ends on main" {
	local work bare tip
	work=$(setup_publish_repo)
	bare=$(bare_of "$work")
	tip=$(git -C "$work" rev-parse v0.1)

	run_finish "$work" --publish

	assert_run_ok
	assert_rev_at "$work" main "$tip"
	assert_ref_at "$bare" main "$tip"
	assert_tag_at "$bare" v0.1.0 "$tip"
	assert_ref_absent "$work" v0.1
	assert_ref_absent "$bare" v0.1
	assert_config_at "$work" branch.v0.1.release "<unset>"
	assert_on_branch "$work" main
}

@test "finish --publish: a failed fast-forward of main names main, the branch and the tag as kept" {
	local work main_before tip
	work=$(setup_publish_repo)
	tip=$(git -C "$work" rev-parse v0.1)
	main_before=$(git -C "$work" rev-parse main)
	stub_git_failing_on --ff-only

	run_finish "$work" --publish

	assert_run_failed 1
	assert_reason "fast-forwarding main onto v0.1 failed"
	assert_reason "main is checked out and unchanged"
	assert_reason "v0.1 and its tag are kept"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
	assert_tag_at "$work" v0.1.0 "$tip"
}

@test "finish --publish --gh-release: creates the release from the changelog section once the tag is on origin" {
	local work notes
	work=$(setup_publish_repo)

	run_finish "$work" --publish --gh-release

	assert_run_ok
	assert_gh_log_includes "release create v0.1.0 --title v0.1.0 --notes-file"
	assert_gh_log_includes "origin-tags: v0.1.0"
	notes=$(gh_notes)
	[[ "$notes" == *"- The widget."* && "$notes" != *"- The sprocket."* ]] || {
		printf 'release body is:\n%s\nexpected only the [0.1.0] section\n' "$notes" >&2
		return 1
	}
}

@test "finish --publish --gh-release: an existing release is reported, not recreated" {
	local work
	work=$(setup_publish_repo)
	stub_gh "$(gh_runs completed success)" present

	run_finish "$work" --publish --gh-release

	assert_run_ok
	assert_stdout_includes "already exists"
	assert_gh_log_excludes "release create"
	assert_ref_absent "$work" v0.1
}

@test "finish --publish --gh-release: a changelog without the release section warns and creates an empty body" {
	local work
	work=$(setup_publish_repo "$CHANGELOG_WITHOUT_SECTION")

	run_finish "$work" --publish --gh-release

	assert_run_ok
	assert_stderr_includes "CHANGELOG.md"
	assert_gh_log_includes "release create v0.1.0"
	[[ -z "$(gh_notes)" ]] || {
		printf 'release body is:\n%s\nexpected an empty body\n' "$(gh_notes)" >&2
		return 1
	}
}

@test "finish --publish --gh-release: a repo without a changelog warns and creates an empty body" {
	local work
	work=$(setup_publish_repo "")

	run_finish "$work" --publish --gh-release

	assert_run_ok
	assert_stderr_includes "CHANGELOG.md"
	assert_gh_log_includes "release create v0.1.0"
	[[ -z "$(gh_notes)" ]] || {
		printf 'release body is:\n%s\nexpected an empty body\n' "$(gh_notes)" >&2
		return 1
	}
}

@test "finish --publish --gh-release: a failed push keeps main local, skips the release, and exits 1 naming the step" {
	local work bare tip main_before
	work=$(setup_publish_repo)
	bare=$(bare_of "$work")
	tip=$(git -C "$work" rev-parse v0.1)
	main_before=$(git -C "$bare" rev-parse main)
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"

	run_finish "$work" --publish --gh-release

	assert_run_failed 1
	assert_reason "pushing main"
	assert_reason "locally"
	assert_rev_at "$work" main "$tip"
	assert_ref_at "$bare" main "$main_before"
	assert_ref_present "$work" v0.1
	assert_gh_log_excludes "release create"
}
