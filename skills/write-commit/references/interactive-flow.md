# Interactive Commit Flow

**Load this reference when:** the user explicitly asked to commit ("commit", "commit changes",
"commit this"). Workflows that prescribe their own commit sequencing skip this flow entirely — they
use SKILL.md's message rules only.

1. **Gather context** — run and review:

   ```bash
   git status --short
   git diff HEAD
   git log --oneline -10   # anchor message style to the repo's history
   ```

   If the status shows no changes, stop and report that there is nothing to commit.

2. **Compose the message** — apply every rule in SKILL.md before writing a single word of the
   subject.

3. **Stage** — check `git diff --cached --name-only` first. If files are already staged that
   shouldn't be part of this commit, unstage them with `git restore --staged <path>`. Then add only
   the intended files and confirm with `git diff --cached --name-only` before committing.

4. **Confirm** — use AskUserQuestion to present the composed message and staged files for approval.
   Options: "Commit" (proceed), "Edit message" (user provides revised wording), "Cancel" (abort).
   Never run `git commit` without the user approving the final message.

5. **Commit** — preserve formatting with a quoted HEREDOC:

   ```bash
   git commit -m "$(cat <<'EOF'
   fix(api): reject empty email on signup

   Body paragraph if one is warranted.
   EOF
   )"
   ```

6. **Verify** — immediately after `git commit`, run in parallel:

   - `git log --oneline -1` — confirm the commit SHA and subject match what was intended
   - `git show --stat HEAD` — confirm exactly the intended files appear in the commit, no more, no
     less

   If the commit SHA is absent (command failed silently), or the file list doesn't match what was
   staged, **stop and surface the discrepancy** before continuing. Do not proceed to the next commit
   or any subsequent step until this is resolved.
