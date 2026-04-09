#!/usr/bin/env bash
set -euo pipefail

CONFIG="${HOME}/.claude/skills.json"
LOCAL_SKILLS_DIR="${HOME}/.claude/skills"
GITIGNORE="${HOME}/.claude/.gitignore"

command -v git >/dev/null || {
	printf "Error: git is required\n" >&2
	exit 1
}
command -v jq >/dev/null || {
	printf "Error: jq is required\n" >&2
	exit 1
}

[[ -f "$CONFIG" ]] || {
	printf "Error: config not found: %s\n" "$CONFIG" >&2
	exit 1
}

synced_skills=()

clone_repo() {
	local repo="$1"
	local tmp_dir="$2"
	git clone --filter=blob:none --no-checkout --depth=1 \
		"https://github.com/${repo}.git" "$tmp_dir" --quiet
}

install_skill() {
	local src="$1"
	local skill="$2"
	local repo="$3"
	local dst="${LOCAL_SKILLS_DIR}/${skill}"

	if [[ ! -d "$src" ]]; then
		printf "Warning: skill '%s' not found in %s, skipping\n" "$skill" "$repo" >&2
		return
	fi

	if [[ -d "$dst" ]]; then
		printf "  Updating: %s\n" "$skill"
	else
		printf "  Installing: %s\n" "$skill"
	fi

	cp -r "$src" "${LOCAL_SKILLS_DIR}/"
}

update_gitignore() {
	local entries_file tmp skill
	entries_file=$(mktemp)
	for skill in "${synced_skills[@]}"; do
		printf "skills/%s/\n" "$skill" >>"$entries_file"
	done

	tmp=$(mktemp)
	awk -v ef="$entries_file" '
		/# SYNC-SKILLS:BEGIN/ { print; while ((getline line < ef) > 0) print line; skip=1; next }
		/# SYNC-SKILLS:END/   { skip=0 }
		!skip                 { print }
	' "$GITIGNORE" >"$tmp"
	mv "$tmp" "$GITIGNORE"
	rm -f "$entries_file"
}

process_repo() {
	local repo="$1"
	local tmp_dir
	tmp_dir=$(mktemp -d -t "sync-skills.XXXXXX")

	local root_skill
	root_skill=$(jq -r --arg r "$repo" '.[$r].root_skill // empty' "$CONFIG")

	if [[ -n "$root_skill" ]]; then
		printf "Processing %s (root skill: %s)...\n" "$repo" "$root_skill"
		clone_repo "$repo" "$tmp_dir"
		local dst="${LOCAL_SKILLS_DIR}/${root_skill}"
		if [[ -d "$dst" ]]; then
			printf "  Updating: %s\n" "$root_skill"
		else
			printf "  Installing: %s\n" "$root_skill"
		fi
		mkdir -p "$dst"
		git -C "$tmp_dir" archive HEAD | tar -x -C "$dst"
		synced_skills+=("$root_skill")
	else
		local skills_dir
		skills_dir=$(jq -r --arg r "$repo" '.[$r].skills_dir' "$CONFIG")

		local skills=()
		mapfile -t skills < <(jq -r --arg r "$repo" '.[$r].skills[]' "$CONFIG")

		if [[ ${#skills[@]} -eq 0 ]]; then
			printf "Skipping %s: no skills listed\n" "$repo"
			trap - EXIT
			rm -rf "$tmp_dir"
			return
		fi

		printf "Processing %s (%d skills)...\n" "$repo" "${#skills[@]}"
		clone_repo "$repo" "$tmp_dir"
		cd "$tmp_dir"
		git sparse-checkout init --cone

		local sparse_paths=()
		local skill
		for skill in "${skills[@]}"; do
			sparse_paths+=("${skills_dir}/${skill}")
		done
		git sparse-checkout set "${sparse_paths[@]}"
		git checkout --quiet

		for skill in "${skills[@]}"; do
			install_skill "${tmp_dir}/${skills_dir}/${skill}" "$skill" "$repo"
		done
		synced_skills+=("${skills[@]}")
	fi

	trap - EXIT
	rm -rf "$tmp_dir"
	cd "${HOME}"
}

mapfile -t repos < <(jq -r 'keys[]' "$CONFIG")

for repo in "${repos[@]}"; do
	process_repo "$repo"
done

update_gitignore
printf "Done.\n"
