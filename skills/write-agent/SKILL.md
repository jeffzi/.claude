---
name: write-agent
description: |
  Use when creating Claude Code subagents, editing files in .claude/agents/, or fixing agents that
  fail to trigger, return malformed output, or request tools they lack. For skills (instructions
  loaded into the main context), use write-skill instead.
argument-hint: "[agent name or purpose]"
---

# Writing Effective Subagents

Agent authoring is skill authoring plus structural concerns. A subagent is an isolated context
window with a **replaced system prompt**, a **restricted tool set**, and a **single return
message**. Every authoring decision flows from those three facts.

The Iron Law from `Skill(write-skill)` applies: **no agent without a failing test first.** Run the
authoring scenario without this skill, watch the baseline fail, then draft.

## When to use

- Creating or editing a file in `.claude/agents/` or `~/.claude/agents/`
- Designing an agent for auto-delegation by parent Claude
- Fixing an agent that fails to trigger, returns malformed output, or requests tools it lacks
- Deciding between a subagent, a skill, or `context: fork` in an existing skill

**Not for:**

- Writing a SKILL.md — use `Skill(write-skill)`. Skills run in the main context; agents do not.
- Adding `context: fork` to an existing skill — that's a skill edit under `Skill(write-skill)`.

## Subagent vs skill vs context: fork

| You want to…                                                        | Use                               |
| ------------------------------------------------------------------- | --------------------------------- |
| Inject reusable instructions into the current conversation          | **Skill**                         |
| Enforce a rule under pressure                                       | **Skill** (discipline type)       |
| Isolate verbose tool output from main context (search, exploration) | **Subagent**                      |
| Give a task its own model, tools, or permissions                    | **Subagent**                      |
| Fork an isolated runner from inside a skill                         | **`context: fork`** in the skill  |
| Run a long-running task without blocking parent                     | **Subagent** (`background: true`) |

**Agents cannot spawn agents.** If the work needs nested delegation, do it from the main
conversation or use a skill instead.

## The four contracts

Every agent definition answers four questions. Get all four right before shipping.

1. **Trigger** — what makes parent Claude delegate to this agent? (the `description`)
2. **Tool surface** — what tools can the agent call? (`tools` / `disallowedTools`)
3. **System prompt** — what is the agent? (the markdown body, which _replaces_ the default)
4. **Return contract** — what message does the agent hand back? (the output format specified in the
   body)

A failure in any one of these four breaks the agent.

## Writing the description

Same CSO rules as `Skill(write-skill)`: third person, triggering conditions only, no workflow
summary. Two style conventions are valid:

- **"Use when ..."** — neutral, inherits skill-description conventions
- **"Use PROACTIVELY ..."** — signals auto-delegation intent, common in Claude Code examples

Pick one. Keep the description under 250 characters — it gets truncated in the agent listing parent
Claude sees, and the part after the cutoff is invisible during delegation decisions.

### Workflow summary leak — the most common failure

```yaml
# BAD — "Returns ranked findings" summarizes what the agent does
description: Use proactively to audit Python for security issues. Returns ranked findings with file:line locations and concrete fixes.

# GOOD — triggering conditions only
description: Use PROACTIVELY after edits to Python files to audit for SQL injection, hardcoded secrets, unsafe deserialization, path traversal, and command injection.
```

### Auto-delegation is a routing hint, not a harness trigger

"Use PROACTIVELY" tells parent Claude _when to delegate_. It does NOT cause the harness to
auto-invoke on file events. For event-based triggering, configure a PostToolUse hook in
`settings.json` that dispatches the agent — see `Skill(update-config)`. Agents have no `paths:`
frontmatter field; that's a skill-only feature.

## Tool surface

Default to the **smallest allowlist** that lets the agent do its job. Every tool granted widens
blast radius and dilutes focus.

```yaml
tools: Read, Grep, Glob # read-only investigator
tools: Read, Edit, Bash, Grep, Glob # code modifier
```

Use `disallowedTools` only when you want to inherit the full tool set minus a few items (rare).

### Instruction/tool consistency — verify before shipping

**Every action the system prompt instructs the agent to take must correspond to an allowed tool.**
This failure is invisible at authoring time and breaks at runtime.

```markdown
# BAD — tools: Read, Grep, Glob (no Write)

After each review, update your memory file at .claude/agent-memory/<name>/MEMORY.md with findings.

# GOOD — tools: Read, Grep, Glob

Return findings in the output block below. You cannot modify files — report only.
```

When you add an instruction, check the `tools:` line. If the verb doesn't map to an allowed tool,
either add the tool or change the instruction.

## System prompt design

**The system prompt REPLACES the Claude Code default.** The agent loses:

- Default tool-usage guidance (Bash vs dedicated tools, commit conventions)
- Default style and verbosity rules
- Any global CLAUDE.md persona shaping (project CLAUDE.md is still loaded)

If the agent needs those behaviors, restate them. Do not assume inheritance.

**Fresh context.** The agent does not see the parent conversation — only the invocation prompt
parent Claude writes. Never reference "the user's earlier request" or "the file you just edited."
State explicitly what input the agent receives.

**Voice: second person, imperative.** Address the agent: "You are X. You do Y." Not "I will Y" or
"The agent should Y."

### Standard body shape

```markdown
# Agent Name

You are a [role]. [One-sentence purpose.]

## When you are invoked

[What inputs the agent receives. What it should read first.]

## What you do

[Core procedure, numbered or bulleted.]

## Rules

[Constraints, non-goals, edge cases.]

## Output format

[Exact format of the return message — see Return contract below.]
```

## Return contract

**The entire message the agent emits becomes ONE turn in the parent conversation.** Parent Claude
has to read and act on it. Design the output so parsing is trivial.

- Specify an exact output format in the system prompt (headers, blocks, structured block)
- Put machine-parseable fields first if parent Claude extracts them (`STATUS:`, `FILE:`, `LINE:`)
- Cap verbosity — a 2000-line agent response costs parent context
- Give the agent a "no findings" template so empty results don't trigger re-runs

Example structured return (from `tdd-cycle`):

```text
TEST_FILE: tests/test_foo.py
TEST_NAME: test_handles_empty_input
TEST_COMMAND: uv run pytest tests/test_foo.py::test_handles_empty_input -x
FAILURE_OUTPUT: AssertionError: expected [], got None
STATUS: FAILED_CORRECTLY
```

## Frontmatter decisions

Required: `name`, `description`. Quick decisions for the common optional fields:

| Field           | Default       | Pick differently when                                                                                     |
| --------------- | ------------- | --------------------------------------------------------------------------------------------------------- |
| `model`         | inherits      | Reasoning-heavy → `opus`; judgment on bounded input → `sonnet`; mechanical lookup → `haiku`               |
| `tools`         | all inherited | ALWAYS restrict — set an explicit allowlist                                                               |
| `memory`        | none          | Agent benefits from persistent learning across runs                                                       |
| `isolation`     | none          | Modifies files + parallel runs could conflict → `worktree`                                                |
| `background`    | `false`       | Long-running task, parent should continue other work                                                      |
| `effort`        | inherits      | **Always pin.** Unset inherits session effort, silently degrades. `high` for reasoning, `low` for lookups |
| `color`         | none          | Visual identification in multi-agent sessions                                                             |
| `initialPrompt` | none          | First message the agent should self-submit at startup                                                     |

### How `model` actually resolves

Four things can set an agent's model. The first one present wins:

1. **`CLAUDE_CODE_SUBAGENT_MODEL`** in the environment or `settings.json` `env`
2. **The `model` parameter on the dispatching `Agent` call**
3. **The agent's `model:` frontmatter**
4. **The session model**

The env var is the trap: it outranks even an explicit per-call `model`, so a stray
`CLAUDE_CODE_SUBAGENT_MODEL: haiku` silently downgrades every agent in the repo while every
frontmatter file still reads `opus`. Check it before concluding an agent's declaration is wrong.

Because frontmatter sits at rank 3, a caller that passes `model` overrides it. Agents meant to
govern their own tier should be dispatched with **no `model` parameter**, and the calling skill
should say so — the house phrasing is "do NOT set model — the agent defines its own".

Unlike skill frontmatter, agent `model`/`effort` are live on every dispatch path. There is no
slash-only qualifier.

**Verify what resolved:** read `.message.model` in `<session>/subagents/agent-<agentId>.jsonl`,
keyed by the sibling `.meta.json`'s `toolUseId`. Treat `resolvedModel` as a cross-check only — it is
known to misreport dispatches. (For the skill side, the instrument is different: top-level
`.message.model` on the invoking turn. See `write-skill/references/frontmatter.md`.)

**Fields that do NOT exist for agents** (common confusion with skills):

- `paths:` — skill-only, auto-activates on matching file types
- `user-invocable:` — skill-only
- `disable-model-invocation:` — skill-only
- `argument-hint:` — skill-only

## Common mistakes

| Mistake                                     | Fix                                                           |
| ------------------------------------------- | ------------------------------------------------------------- |
| Workflow summary in description             | Remove "Returns X" / "Produces Y" — describe triggers only    |
| Description > 250 chars                     | Trim lists; front-load the primary trigger                    |
| System prompt instructs a tool not granted  | Check `tools:` — every verb must map to an allowed tool       |
| Guessed filesystem paths in body            | Verify paths against docs or omit — don't hallucinate         |
| Treats "use proactively" as auto-trigger    | It's a routing hint to parent Claude, not a harness hook      |
| Expects parent conversation context         | Agent has fresh context — state inputs explicitly             |
| Uses `paths:` frontmatter                   | That's a skill field; agents don't have it                    |
| Tries to spawn sub-agents                   | Agents cannot spawn agents; chain from main or use a skill    |
| No return contract                          | Specify exact output format — parent has to parse the message |
| Inherits all tools                          | Always set an explicit allowlist                              |
| Leaves `effort` unset                       | Always pin — unset inherits session effort, silently degrades |
| First-person voice in system prompt         | Use second-person imperative to the agent                     |
| Assumes default Claude Code behaviors apply | System prompt REPLACES default — restate what you need        |

## Testing your agent

Load `Skill(write-skill)` and apply its RED → GREEN → REFACTOR loop. Agent authoring is a technique
skill — the baseline test is **spawn an isolated agent, give it the Claude Code agent docs, and ask
it to author your target agent**. Observe the failures, then write the skill/draft to address them.

**Application tests for the finished agent:**

1. **Real-task test** — invoke the agent on 2-3 realistic scenarios. Does the output match the
   return contract? Can parent Claude parse it?
2. **Boundary test** — give the agent input outside its scope. Does it refuse gracefully or
   hallucinate?
3. **Tool-exhaustion test** — can the agent do everything its prompt instructs using only its
   allowed tools? Watch for "tool not available" errors.
4. **Return-size test** — for a large realistic input, is the returned message reasonably sized?

**Trigger validation** (same as write-skill): 5-8 should-trigger and 5-8 should-not-trigger prompts.
Does the description activate on the right ones without false positives?

## Deployment checklist

After writing ANY agent, STOP and complete this checklist before shipping.

### RED phase — baseline

- [ ] Ran baseline: asked an isolated agent to author this without the skill
- [ ] Documented failures and rationalizations verbatim
- [ ] Decided: subagent, skill, or `context: fork`

### Frontmatter

- [ ] `name`: letters, numbers, hyphens only
- [ ] `description`: ≤ 250 chars, third person, no workflow summary
- [ ] `tools`: explicit allowlist (not "all tools")
- [ ] `model`: chosen deliberately, not default-copied — and `CLAUDE_CODE_SUBAGENT_MODEL` confirmed
      absent, since it silently outranks this field
- [ ] `effort`: pinned explicitly — never left unset

### Body

- [ ] Voice: second person, imperative ("You are X. You do Y.")
- [ ] Fresh context acknowledged — states what inputs the agent receives
- [ ] Every instruction maps to an allowed tool
- [ ] Output format specified with exact structure
- [ ] No hallucinated filesystem paths
- [ ] "When NOT to use" section if the agent has a peer it could be confused with

### Testing

- [ ] Application test on 2+ realistic scenarios
- [ ] Boundary test — agent refuses out-of-scope input gracefully
- [ ] Tool-exhaustion test — agent completes without "tool not available"
- [ ] Trigger validation — description activates on right prompts only

## Attribution

Extends `Skill(write-skill)`. Authoring discipline and TDD methodology adapted from
[obra/superpowers/writing-skills](https://github.com/obra/superpowers/tree/main/skills/writing-skills)
by Jesse Vincent.
