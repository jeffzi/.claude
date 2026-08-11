# SKILL.md Frontmatter Reference

Full reference for YAML frontmatter fields, string substitutions, and advanced patterns. All fields
are optional; only `description` is recommended.

## Contents

- [Fields](#fields)
- [String substitutions](#string-substitutions)
- [Advanced: dynamic context injection](#advanced-dynamic-context-injection)
- [Advanced: subagent execution (`context: fork`)](#advanced-subagent-execution-context-fork)
- [Description budget and truncation](#description-budget-and-truncation)
- [Portability beyond Claude Code](#portability-beyond-claude-code)
- [Who-invokes matrix](#who-invokes-matrix)

---

## Fields

| Field                      | Purpose                                                                                                                                      |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`                     | Display name. Defaults to directory name. Lowercase letters, numbers, hyphens only (max 64 chars). Required for claude.ai/API uploads.       |
| `description`              | What the skill does and when to use it. Front-load the key use case — combined with `when_to_use`, truncated at 1,536 chars.                 |
| `when_to_use`              | Extra trigger phrases or example requests. Appended to `description` in the listing; shares the 1,536-char cap.                              |
| `argument-hint`            | Autocomplete hint shown when typing `/skill-name`. Example: `[issue-number]` or `[filename] [format]`.                                       |
| `arguments`                | Named positional arguments for `$name` substitution. Space-separated string or YAML list; names map to positions in order.                   |
| `disable-model-invocation` | `true` prevents Claude from auto-loading. Manual `/name` only. Also blocks subagent preloading and scheduled-task prompts. Default: `false`. |
| `user-invocable`           | `false` hides from the `/` menu. Claude can still auto-load. Default: `true`.                                                                |
| `allowed-tools`            | Tools pre-approved during the turn that invokes the skill — the grant clears on the next user message. Space-separated or YAML list.         |
| `disallowed-tools`         | Tools removed from the pool while the skill is active; also clears on the next user message.                                                 |
| `model`                    | Model override, **slash invocation only**. E.g., `haiku`, `sonnet`, `opus`, or full model ID. See below.                                     |
| `effort`                   | Effort level override, **slash invocation only**. `low`, `medium`, `high`, `xhigh`, `max`. See below.                                        |
| `context`                  | Set to `fork` to run in an isolated subagent context.                                                                                        |
| `agent`                    | Subagent type when `context: fork` is set. `Explore`, `Plan`, `general-purpose`, or custom agent.                                            |
| `background`               | With `context: fork` only: `false` waits for the fork's result in the invoking turn. Default: `true`.                                        |
| `hooks`                    | Hooks scoped to this skill's lifecycle.                                                                                                      |
| `paths`                    | Glob patterns that auto-activate the skill when matching files are in play. Comma-separated or YAML list. Trades away `Skill()`.             |
| `shell`                    | `bash` (default) or `powershell` for `!` commands.                                                                                           |
| `metadata`                 | Free-form YAML map for your own tooling. Claude Code ignores its contents.                                                                   |
| `license`, `compatibility` | Agent Skills spec fields; accepted but not acted on by Claude Code. See [Portability](#portability-beyond-claude-code).                      |

### `model` and `effort` apply on the slash path only

Both fields take effect only when the user invokes the skill as `/skill-name`. They are **inert**
when the skill is loaded through the `Skill()` tool, and inert inside a subagent — in both cases the
surrounding turn's model and effort govern, and the declaration does nothing.

The upstream docs do not carry this qualifier. `references/claude/skills.md` describes both fields
as applying "when this skill is active", and `references/claude/effort.md` as applying "for the
duration of that skill's execution". Neither distinguishes the invocation path. The observed
behavior does: a skill declaring `model: sonnet`, loaded via `Skill()` in an opus session, runs
every subsequent turn on opus.

To verify which model actually ran, read `.message.model` from the assistant records in the session
JSONL (for a dispatched agent, in its subagent JSONL). Treat `resolvedModel` as a cross-check only —
it is absent from skill turns and misreports dispatches.

### When to declare them

A live declaration **overrides the user's `/model` choice for the entire turn**. That is a real
cost, so it needs a real justification.

| Reachable by                                     | Action                                                                       |
| ------------------------------------------------ | ---------------------------------------------------------------------------- |
| Slash only (`disable-model-invocation: true`)    | Always live. Declare **only** with a stated reason; otherwise omit both.     |
| `Skill()` and slash, slash-invoked in practice   | Declare **only** with a stated reason; otherwise omit both.                  |
| `Skill()` and slash, effectively never slash-run | **Omit both.** The declaration is dead weight that misleads the next reader. |

A stated reason means a genuine quality floor for the workflow — "this skill adjudicates a diff and
the cheap tier gets it wrong". Liveness alone is not a reason. Load-only skills (`code-core`,
`test-core`, the language leaves) should carry neither field.

### `effort` selection guide

When you do declare `effort` on a slash-invoked skill:

| Skill type                          | Recommended     | Reasoning                                  |
| ----------------------------------- | --------------- | ------------------------------------------ |
| Commit, release, sync, scaffolding  | `low`           | Sequential steps, no design decisions      |
| Code review, issue triage           | `medium`        | Pattern recognition, bounded scope         |
| Security audit, architecture review | `high`          | Threat modeling, cross-component reasoning |
| Multi-agent orchestration, research | `high` or `max` | Deep exploration, planning                 |

Available levels depend on the model — verify before declaring `max`. Pair `model: haiku` with
`effort: low`. Pair `model: opus` with `effort: high` or `max`.

### `allowed-tools` syntax

Accepts tool names with optional argument patterns:

```yaml
allowed-tools: Read, Grep, Glob # simple tools
allowed-tools: Bash(git *), Bash(npm test:*) # scoped Bash
allowed-tools: Edit(CHANGELOG.md), Read, Grep # path-scoped Edit
```

### `paths` syntax

```yaml
paths: "**/*.py" # single pattern
paths: "**/*.ts, **/*.tsx" # comma-separated
paths: # YAML list
  - "**/test_*.py"
  - "**/conftest.py"
```

### `paths` removes the skill from explicit `Skill()` dispatch

Declaring `paths` makes the skill path-activated **instead of** registry-listed, not in addition to
it. A skill with `paths` does not appear in the available-skills listing, and calling it by name
fails:

```text
Skill(code-ts)
→ Error: Unknown skill: code-ts. Did you mean code-tstl?
```

The file is present and its frontmatter is valid — `paths` is a recognized key. It simply is not
reachable by name until a matching file is in play, which is too late for any instruction that says
"load this skill first."

That makes `paths` incompatible with hub-and-leaf dispatch. `rules/skill-loading.md` and
`code-core`'s Language Dispatch table both instruct an explicit `Skill(code-{lang})` call, and the
hub fires before any source file has been read — so the leaf is guaranteed absent at exactly the
moment it is needed.

**Choose one:**

| Goal                                       | Setting                                         |
| ------------------------------------------ | ----------------------------------------------- |
| Another skill or rule loads it by name     | Omit `paths`. Explicit dispatch needs the name. |
| Fires on its own when a file type shows up | Use `paths`. Never call it via `Skill()`.       |

Auto-activation and named dispatch are mutually exclusive. Wanting both means picking named dispatch
and letting the hub decide, since the hub can always reach a registered skill but nothing can reach
an unregistered one.

---

## String substitutions

Available inside SKILL.md body (replaced at invocation time):

| Variable                | Description                                                                                      |
| ----------------------- | ------------------------------------------------------------------------------------------------ |
| `$ARGUMENTS`            | Everything passed after the skill name. Appended as `ARGUMENTS: <value>` if not present in body. |
| `$ARGUMENTS[N]`         | Specific argument by 0-based index. `$ARGUMENTS[0]` = first.                                     |
| `$N`                    | Shorthand for `$ARGUMENTS[N]`. `$0` = first, `$1` = second.                                      |
| `$name`                 | Named argument declared in the `arguments` frontmatter list; names map to positions in order.    |
| `${CLAUDE_SESSION_ID}`  | Current session ID. Use for logging, session-specific file paths.                                |
| `${CLAUDE_SKILL_DIR}`   | Directory containing this SKILL.md. Use to reference bundled scripts/files regardless of cwd.    |
| `${CLAUDE_PROJECT_DIR}` | Project root directory — same path hooks receive. Use for project-local scripts.                 |
| `${CLAUDE_EFFORT}`      | Current effort level (`low`–`max`). Use to adapt instructions to the active effort setting.      |

Substitution runs over the whole SKILL.md body, including code spans and fences. To mention
`$ARGUMENTS`, a `$N` index, or a declared argument name literally, escape it with a backslash
(`\$ARGUMENTS`); an unescaped token is replaced at invocation. The backslash escape covers only
those tokens — for `${CLAUDE_*}` variables, break the token up (e.g. write `CLAUDE_SKILL_DIR`
without the `${}` wrapper) instead.

**Example:**

```yaml
---
name: migrate-component
description: Migrate a component from one framework to another
---

Migrate the $0 component from $1 to $2. Preserve all existing behavior and tests.
```

Running `/migrate-component SearchBar React Vue` substitutes positionally.

---

## Advanced: dynamic context injection

The `` !`<command>` `` syntax runs shell commands **before** the skill content reaches Claude.
Output replaces the placeholder. This is preprocessing — Claude sees the rendered result, not the
command.

```yaml
---
name: pr-summary
description: Summarize changes in a pull request
allowed-tools: Bash(gh *)
---

## Pull request context
- PR diff: !`gh pr diff`
- PR comments: !`gh pr view --comments`
- Changed files: !`gh pr diff --name-only`

## Your task
Summarize this pull request...
```

For multi-line commands, use a fenced `` ```! `` block:

````markdown
## Environment

```!
node --version
npm --version
git status --short
```
````

**When to use:** any time the skill body would tell Claude to "run `git status` first" — inject the
output directly instead. The data arrives pre-rendered, saving a round trip.

**Disabled by:** `"disableSkillShellExecution": true` in settings (managed settings enforcement).
Each command is replaced with `[shell command execution disabled by policy]`.

---

## Advanced: subagent execution (`context: fork`)

Runs the skill in an isolated subagent. The skill body becomes the subagent's prompt. The subagent
has no access to the main conversation's history.

```yaml
---
name: deep-research
description: Research a topic thoroughly
context: fork
agent: Explore
---

Research $ARGUMENTS thoroughly:
1. Find relevant files using Glob and Grep
2. Read and analyze the code
3. Summarize findings with specific file references
```

**Only makes sense** for skills with explicit task instructions. Reference-content skills ("use
these API conventions") fail silently — subagent receives guidelines but no actionable prompt.

**`agent` field** picks the subagent environment: `Explore`, `Plan`, `general-purpose`, or a custom
agent from `.claude/agents/`. Defaults to `general-purpose`.

---

## Description budget and truncation

- **Per-skill cap: 1,536 chars** for the combined `description` + `when_to_use` text in the skill
  listing. Front-load the key use case in the first sentence.
- With many skills, hosts shorten descriptions to fit an overall budget — stripping keywords breaks
  auto-invocation, another reason to front-load.

---

## Portability beyond Claude Code

claude.ai skill uploads, the Skills API, and other Agent Skills hosts (including Codex) accept only
the spec's six frontmatter fields: `name`, `description`, `license`, `compatibility`, `metadata`,
`allowed-tools`. Any other key (`argument-hint`, `context`, ...) fails packaging or upload with a
hard error, and Claude Code-only body features such as dynamic context injection don't run there.
Keep to the six spec fields when a skill must travel; Claude Code loads spec-compliant frontmatter
unchanged.

---

## Who-invokes matrix

| Frontmatter                      | User can `/invoke` | Claude can auto-invoke | Description in context                 |
| -------------------------------- | ------------------ | ---------------------- | -------------------------------------- |
| (default)                        | ✓                  | ✓                      | Always                                 |
| `disable-model-invocation: true` | ✓                  | ✗                      | Never (loads only when user invokes)   |
| `user-invocable: false`          | ✗                  | ✓                      | Always                                 |
| both                             | ✗                  | ✗                      | (unreachable — skill can't be invoked) |

**`disable-model-invocation: true`** — side-effecting workflows, manual-only (`/commit`, `/deploy`,
`/upgrade-py`). The description is never shown to the model, so write it human-facing: a one-line
summary for the `/` menu, no "Use when..." trigger lists.

**`user-invocable: false`** — background knowledge not actionable as a command (reference skills
like `code-py`, `legacy-system-context`). `/code-py` isn't a meaningful action.

---

## Related

- **Extended thinking:** include the word `ultrathink` anywhere in the skill body to enable extended
  thinking when the skill is active.
