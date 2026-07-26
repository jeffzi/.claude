# SKILL.md Frontmatter Reference

Full reference for YAML frontmatter fields, string substitutions, and advanced patterns. All fields
are optional; only `description` is recommended.

## Contents

- [Fields](#fields)
- [String substitutions](#string-substitutions)
- [Advanced: dynamic context injection](#advanced-dynamic-context-injection)
- [Advanced: subagent execution (`context: fork`)](#advanced-subagent-execution-context-fork)
- [Description budget and truncation](#description-budget-and-truncation)
- [Who-invokes matrix](#who-invokes-matrix)

---

## Fields

| Field                      | Purpose                                                                                                                          |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `name`                     | Display name. Defaults to directory name. Lowercase letters, numbers, hyphens only (max 64 chars).                               |
| `description`              | What the skill does and when to use it. Front-load the key use case — truncated at 250 chars per entry.                          |
| `argument-hint`            | Autocomplete hint shown when typing `/skill-name`. Example: `[issue-number]` or `[filename] [format]`.                           |
| `disable-model-invocation` | `true` prevents Claude from auto-loading. Manual `/name` invocation only. Default: `false`.                                      |
| `user-invocable`           | `false` hides from the `/` menu. Claude can still auto-load. Default: `true`.                                                    |
| `allowed-tools`            | Tools Claude can use without permission prompts when skill is active. Space-separated or YAML list.                              |
| `model`                    | Model override, **slash invocation only**. E.g., `haiku`, `sonnet`, `opus`, or full model ID. See below.                         |
| `effort`                   | Effort level override, **slash invocation only**. `low`, `medium`, `high`, `max`. See below.                                     |
| `context`                  | Set to `fork` to run in an isolated subagent context.                                                                            |
| `agent`                    | Subagent type when `context: fork` is set. `Explore`, `Plan`, `general-purpose`, or custom agent.                                |
| `hooks`                    | Hooks scoped to this skill's lifecycle.                                                                                          |
| `paths`                    | Glob patterns that auto-activate the skill when matching files are in play. Comma-separated or YAML list. Trades away `Skill()`. |
| `shell`                    | `bash` (default) or `powershell` for `!` commands.                                                                               |

### `model` and `effort` apply on the slash path only

Both fields take effect only when the user invokes the skill as `/skill-name`. They are **inert**
when the skill is loaded through the `Skill()` tool, and inert inside a subagent — in both cases the
surrounding turn's model and effort govern, and the declaration does nothing.

The upstream docs do not carry this qualifier. `references/claude/skills.md` describes both fields
as applying "when this skill is active", and `references/claude/effort.md` as applying "for the
duration of that skill's execution". Neither distinguishes the invocation path. The observed
behavior does: a skill declaring `model: sonnet`, loaded via `Skill()` in an opus session, runs
every subsequent turn on opus.

**Verify which happened, split by path:**

| Path                | Where to read the effective model                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Slash-invoked skill | Top-level `.message.model` on the assistant records of the invoking turn, in the session JSONL. No `resolvedModel` field. |
| Dispatched agent    | `.message.model` in `<session>/subagents/agent-<agentId>.jsonl`, keyed by the sibling `.meta.json`'s `toolUseId`.         |

Treat `resolvedModel` as a cross-check only — it is absent from skill turns and misreports
dispatches.

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

`max` is Opus 4.6 only — errors on other models. Pair `model: haiku` with `effort: low`. Pair
`model: opus` with `effort: high` or `max`.

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
moment it is needed. This is not hypothetical: every `code-*` and `test-*` leaf carried `paths`
until the keys were removed, which is why TypeScript tests worked (`test-ts` never had one) while
TypeScript production code did not.

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

| Variable               | Description                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| `$ARGUMENTS`           | Everything passed after the skill name. Appended as `ARGUMENTS: <value>` if not present in body. |
| `$ARGUMENTS[N]`        | Specific argument by 0-based index. `$ARGUMENTS[0]` = first.                                     |
| `$N`                   | Shorthand for `$ARGUMENTS[N]`. `$0` = first, `$1` = second.                                      |
| `${CLAUDE_SESSION_ID}` | Current session ID. Use for logging, session-specific file paths.                                |
| `${CLAUDE_SKILL_DIR}`  | Directory containing this SKILL.md. Use to reference bundled scripts/files regardless of cwd.    |

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

- **Per-skill cap: 250 chars.** Descriptions longer than 250 chars are truncated in the skill
  listing. Front-load the key use case in the first sentence.
- **Total budget: 1% of context window** (8000-char fallback). If you have many skills, descriptions
  get shortened to fit. Stripping keywords breaks auto-invocation.
- **Override:** set `SLASH_COMMAND_TOOL_CHAR_BUDGET` env var.

---

## Who-invokes matrix

| Frontmatter                      | User can `/invoke` | Claude can auto-invoke | Description in context                 |
| -------------------------------- | ------------------ | ---------------------- | -------------------------------------- |
| (default)                        | ✓                  | ✓                      | Always                                 |
| `disable-model-invocation: true` | ✓                  | ✗                      | Never (loads only when user invokes)   |
| `user-invocable: false`          | ✗                  | ✓                      | Always                                 |
| both                             | ✗                  | ✗                      | (unreachable — skill can't be invoked) |

**`disable-model-invocation: true`** — side-effecting workflows, manual-only (`/commit`, `/deploy`,
`/upgrade-py`).

**`user-invocable: false`** — background knowledge not actionable as a command (reference skills
like `code-py`, `legacy-system-context`). `/code-py` isn't a meaningful action.

---

## Related

- **Extended thinking:** include the word `ultrathink` anywhere in the skill body to enable extended
  thinking when the skill is active.
- **Permission control:** `Skill(name)` for exact match, `Skill(name *)` for prefix match with args
  in `/permissions` deny/allow rules.
- **Auto-discovery from nested dirs:** `.claude/skills/` is discovered from subdirectories when
  working with files inside them (monorepo support).
