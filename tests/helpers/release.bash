#!/usr/bin/env bash
# Shared constants, fixtures, stubs, invocation wrappers, and assertions for the
# tests/test_release_*.bats suites. Loaded after helpers/hooks, whose repo
# builders and marker helpers these functions call.

# shellcheck disable=SC2034 # consumed by assert_help_printed in helpers/hooks.bash
USAGE_LINE="usage: release.sh start <X.Y.Z> [--adopt]
       release.sh status
       release.sh merge [plan/<slug>] [--force]
       release.sh finish (--check|--push|--publish) [--force] [--gh-release]"

# Message the merge fixtures write to $GIT_DIR/plan-squash/<slug>.msg.
PLAN_MSG="feat(widget): add the widget

Also fixes: the sprocket.
"

# Subjects of the commits the fold fixtures put on the release branch.
ALPHA_SUBJECT="feat: add alpha"
BETA_SUBJECT="feat: add beta"
GAMMA_SUBJECT="feat: add gamma"

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
# shellcheck disable=SC2034 # consumed by test_release_finish.bats, which loads this file
CHANGELOG_WITHOUT_SECTION="# Changelog

## [0.0.1] - 2025-12-01

### Added

- The sprocket.
"

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

# Commit file $2 with content $3 under subject $4 in the repo at $1 — commit_file
# with the two told apart, for fixtures whose content must repeat across subjects.
commit_as() {
	local repo="$1" name="$2" text="$3" subject="$4"
	printf '%s\n' "$text" >"$repo/$name"
	git -C "$repo" add "$name"
	git -C "$repo" -c commit.gpgsign=false commit -q -m "$subject"
}

# setup_open_release with v0.1 carrying the alpha commit and two commits sharing
# the beta subject, and a plan/x whose first ordinary commit makes exactly the
# change its trailing fixup makes, so the rebase replays it as empty; gh reports
# a successful run. Prints the work dir.
setup_emptied_fold_repo() {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" alpha.txt "$ALPHA_SUBJECT"
	commit_file "$work" beta.txt "$BETA_SUBJECT"
	commit_file "$work" beta2.txt "$BETA_SUBJECT"
	git -C "$work" push -q origin v0.1
	git -C "$work" switch -q -c plan/x
	git -C "$work" config branch.plan/x.planBase v0.1
	commit_as "$work" alpha.txt "patched alpha" "feat: patch alpha"
	commit_as "$work" alpha.txt "$ALPHA_SUBJECT" "feat: unpatch alpha"
	commit_as "$work" alpha.txt "patched alpha" "fixup! $ALPHA_SUBJECT"
	stub_gh "$(gh_runs completed success)"
	printf '%s' "$work"
}

# setup_release_pair with alpha, beta and gamma seeded on main, a v0.1 holding
# one commit per file, and a plan/x whose ordinary commit undoes the beta and
# gamma commits while its fixup for the alpha commit redoes both — so the rebase
# replays the beta and gamma commits as empty. gh reports a successful run;
# prints the work dir.
setup_vanishing_fold_repo() {
	local work
	work=$(setup_release_pair)
	commit_file "$work" alpha.txt "seed alpha"
	commit_file "$work" beta.txt "seed beta"
	commit_file "$work" gamma.txt "seed gamma"
	git -C "$work" push -q origin main
	git -C "$work" branch v0.1 main
	git -C "$work" config branch.v0.1.release 0.1.0
	git -C "$work" switch -q v0.1
	commit_file "$work" alpha.txt "$ALPHA_SUBJECT"
	commit_file "$work" beta.txt "$BETA_SUBJECT"
	commit_file "$work" gamma.txt "$GAMMA_SUBJECT"
	git -C "$work" push -q origin v0.1
	git -C "$work" switch -q -c plan/x
	git -C "$work" config branch.plan/x.planBase v0.1
	printf 'seed beta\n' >"$work/beta.txt"
	printf 'seed gamma\n' >"$work/gamma.txt"
	git -C "$work" add beta.txt gamma.txt
	git -C "$work" -c commit.gpgsign=false commit -q -m "chore: undo beta and gamma"
	printf '%s\n' "$BETA_SUBJECT" >"$work/beta.txt"
	printf '%s\n' "$GAMMA_SUBJECT" >"$work/gamma.txt"
	git -C "$work" add beta.txt gamma.txt
	git -C "$work" -c commit.gpgsign=false commit -q -m "fixup! $ALPHA_SUBJECT"
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

# Commit on branch $2 in a second clone of $1's origin, and install a pre-push
# hook in $1 that pushes that commit to the real origin before letting the run's
# own push through — so the push meets an origin that moved after the opening
# fetch took its lease. The hook removes itself, leaving a later push free.
move_origin_before_push() {
	local work="$1" branch="$2" other hook
	other="${work%/work}/second"
	git clone -q "$(bare_of "$work")" "$other"
	init_git_identity "$other"
	git -C "$other" switch -q "$branch"
	commit_file "$other" THEIRS "theirs"
	hook="$(git -C "$work" rev-parse --absolute-git-dir)/hooks/pre-push"
	mkdir -p "$(dirname "$hook")"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'rm -f %q\n' "$hook"
		printf 'env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C %q push -q origin %q\n' \
			"$other" "$branch"
	} >"$hook"
	chmod +x "$hook"
}

# setup_fold_repo whose merge run, made with HEAD on branch $1, met an origin
# that moved after its opening fetch and failed, with the recovery steps that
# run printed already carried out; prints the work dir.
setup_recovered_fold_repo() {
	local work
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	move_origin_before_push "$work" v0.1
	git -C "$work" switch -q "$1"
	run_merge "$work" plan/x
	run_printed_steps "$work"
	printf '%s' "$work"
}

# Install a pre-push hook in $1 that points origin at a missing path and then
# fails the push, so the push and every remote read after it meet a remote that
# cannot be reached at all.
unreachable_origin_before_push() {
	local work="$1" hook
	hook="$(git -C "$work" rev-parse --absolute-git-dir)/hooks/pre-push"
	mkdir -p "$(dirname "$hook")"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C %q config remote.origin.url %q\n' \
			"$work" "$TMPDIR_ROOT/missing.git"
		printf 'exit 1\n'
	} >"$hook"
	chmod +x "$hook"
}

# Install a pre-commit hook in $1 that fails every commit the script makes.
fail_commits() {
	local hook
	hook="$(git -C "$1" rev-parse --absolute-git-dir)/hooks/pre-commit"
	mkdir -p "$(dirname "$hook")"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$hook"
	chmod +x "$hook"
}

# Drop the hook fail_commits installed in $1, so commits succeed again.
allow_commits() {
	rm -f "$(git -C "$1" rev-parse --absolute-git-dir)/hooks/pre-commit"
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

# Run every 'git …' command the last run quoted in its message, in the order it
# quoted them, from the repo at $1; fails if a step fails or none was quoted.
run_printed_steps() {
	local work="$1" rest="$RUN_STDERR" step out ran=0
	while [[ "$rest" == *"'"* ]]; do
		rest="${rest#*\'}"
		step="${rest%%\'*}"
		rest="${rest#*\'}"
		[[ "$step" == git\ * ]] || continue
		out=$(cd "$work" && eval "$step" 2>&1) || {
			printf 'quoted step failed: %s\n%s\n' "$step" "$out" >&2
			return 1
		}
		ran=$((ran + 1))
	done
	((ran > 0)) || {
		printf 'no git steps quoted\nstderr: %s\n' "$RUN_STDERR" >&2
		return 1
	}
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

# Repo $1 has nothing staged, nothing modified and nothing untracked.
assert_tree_clean() {
	local repo="$1" got
	got=$(git -C "$repo" status --porcelain --untracked-files=all)
	[[ -z "$got" ]] || {
		printf 'expected a clean tree in %s, got:\n%s\n' "$repo" "$got" >&2
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

# HEAD in repo $1 is detached at commit $2.
assert_detached_at() {
	local repo="$1" want="$2" head
	if head=$(git -C "$repo" symbolic-ref -q HEAD); then
		printf 'HEAD is on %s, expected it detached at %s\n' "$head" "$want" >&2
		return 1
	fi
	assert_rev_at "$repo" HEAD "$want"
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

# repo_state for $1 without its remote-tracking refs, which the opening fetch of
# a run legitimately updates however the run then ends. Everything else the
# snapshot carries — HEAD, local branches, local config, the bare origin, the
# work tree — a refused run must leave exactly as it found it.
repo_state_except_tracking() {
	repo_state "$1" | sed '/^refs\/remotes\//d'
}

# Repo $1 still matches the repo_state_except_tracking() snapshot $2.
assert_repo_state_except_tracking() {
	local repo="$1" want="$2" got
	got=$(repo_state_except_tracking "$repo")
	[[ "$got" == "$want" ]] || {
		printf 'repo state changed:\n%s\nexpected:\n%s\n' "$got" "$want" >&2
		return 1
	}
}

# Merge in the repo at $1 is refused naming $2 and the linear-only reason,
# leaving the repo exactly as it was.
assert_merge_refuses_fold() {
	local work="$1" name="$2" state_before
	state_before=$(repo_state "$work")

	run_merge "$work"

	assert_refused
	assert_reason "$name"
	assert_reason "a fold replays only linear fixup! and ordinary commits"
	assert_repo_state "$work" "$state_before"
}
