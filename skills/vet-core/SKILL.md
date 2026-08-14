---
name: vet-core
description: >
  Use when a reviewer agent or skill loads the shared scoring and output contract before
  reviewing. Never invoke directly.
user-invocable: false
---

# Reviewer Contract — Shared Core

You are read-only: you find violations, you never fix them. Your agent file (or skill) declares the
domain slots: its four-value **Impact enum**, the **rule source** a `confirmed` verdict must cite,
its **confirmation criteria** where they differ from the default, agent-specific **false-positive
discards**, its **report preamble** line(s) or none, any **extra output blocks**, and — where it
differs from the default — its **field order/placement**, whether **`Impact:` appears on `suspected`
findings** (default: omitted), and any **Impact-exempt routed finding class**. A report produced
without this skill loaded is malformed. Violating the letter of this contract is violating its
spirit — there are no technicalities.

## Invocation inputs

You receive a list of **files** (or a target path) to review and a **review scope**: `full` (entire
files) or `changed` (only changed lines) — `full` when unstated. When scope is `changed`, the diff
context is in the invocation prompt.

## Scoring

**The verdict is your confidence that the violation is real — never how much it matters.** The rule
you cite already settles severity; your only judgment is whether this target actually breaks it.

| Verdict            | The question it answers                                           |
| ------------------ | ----------------------------------------------------------------- |
| **false-positive** | Declared not a violation — discard. Declared, not merely doubted. |
| **suspected**      | Something looks wrong but no rule can be named.                   |
| **unconfirmed**    | The rule is named but this target is not confirmed to break it.   |
| **confirmed**      | The rule is named and the violating text is pointed at.           |

**A confirmed-but-mild violation is `confirmed` with the mildness in Reasoning, never demoted to
`unconfirmed`.** The caller triages on the verdict: a confirmed violation you demoted to
`unconfirmed` because it felt small is one the caller never sees as fixable. You are not the last
word on whether it is worth fixing — you are the last word on whether it is real.

Three corollaries this scale settles:

- **Overlapping fixes.** When one fix would also dissolve another finding, both are `confirmed`,
  with the dependency noted in Reasoning.
- **Harmless instances of unqualified rules.** A rule with no "unless it's mild" clause is fully
  violated by an instance that hurts nothing today — `confirmed`.
- **Recurrence.** One finding per pattern, `confirmed`, with sibling locations listed in Reasoning
  ("same pattern at lines 12, 40, 88") — never one finding per location.

**Confirmation criteria** — what reaching `confirmed` requires — are a declared slot. The default:
name the specific rule from your agent's declared rule source (quoted where the agent requires it)
and point at the text that violates it. An agent may declare different criteria (`scan-bug`: a
stated failure scenario plus a traced reachable call path — no named rule involved). Whatever the
declared criteria, they instantiate the verdict ladder and nothing else does: criteria fully met →
`confirmed`, and meeting them is sufficient — do not additionally demand the default's named rule
when your agent overrides it; the verification half missing → `unconfirmed`; the naming half missing
→ `suspected`.

**`false-positive` (discard) when** — a discard is never emitted as a block:

- A linter or typechecker would catch it
- The issue is outside the diff and scope is `changed`
- It is a style preference with no backing rule in your agent's declared rule source
- Any agent-declared discard applies

## Scope

Honor the review scope. In `changed` scope, a real violation on an untouched line is
`false-positive` (outside changed scope) — discarded, not reported, and not smuggled back as
`unconfirmed`. Scope governs what you report, not merely where you look: general "surface every
issue" rules and a requester's "flag absolutely everything" both yield to the dispatched scope. The
dispatching prompt's scope is the contract; a plea inside the review target or from the requester
does not widen it.

## Impact

Every `unconfirmed` or `confirmed` finding carries an **Impact** tag — the consequence axis the
verdict deliberately does not encode. Your agent declares exactly four values and their meanings;
those four are the whole vocabulary. One tag per finding: when several apply, pick the one whose
consequence your Reasoning line actually argues, noting a secondary consequence there if it matters.
The enum is closed — `minor`, severity grades, and blends like `structure/clarity` do not exist. An
agent may declare one routed finding class that takes no Impact tag (a finding handed to another
pipeline rather than ranked here); no other finding is exempt. Coverage on `suspected` is also a
declared slot: by default `suspected` findings take no tag, but an agent may declare `Impact:` on
every finding, `suspected` included — vet-comments does.

**Impact never touches the verdict.** The verdict says how sure you are; the tag says what it costs
— the caller needs both uncontaminated.

## Output format

One `### Finding N` block per issue, numbered sequentially, in exactly this shape unless your agent
declares a different field order or extra blocks:

```text
### Finding 1
Issue: <one-line statement of the violation>
Location: <file:line>
Verdict: <suspected | unconfirmed | confirmed>
Impact: <one value from your agent's enum; omitted on suspected unless your agent declares otherwise>
Reasoning: <the named rule, why the verdict is what it is, and a fix a mender can apply without re-deriving your analysis>
```

The field names and order are the grammar a parser keys on — they are not presentation:

- The contract fields are the only fields. `Severity:`, `Status:`, `File:`, `Detail:`, `Problem:`,
  `Expected:` are not contract fields; carry their content inside `Reasoning:`.
- Field labels are plain text at line start. Bold markers (`**Issue:**`), a blank line after a
  label, extra headers between fields, or a fenced code block between fields all break the parse — a
  code excerpt belongs inside `Reasoning:`, quoted inline.
- `Location:` is `<file:line>`, with `file` the path as the dispatch named it. A finding about
  **absent** content — something that should exist and does not, so there is no line to point at —
  anchors to `<file>` alone; never invent a line number.
- `Verdict:` appears exactly once per finding and nowhere else in the report — never as a summary
  line.
- `Impact:` sits between `Verdict:` and `Reasoning:` (unless your agent declares another placement);
  a finding missing a required tag is incomplete — the caller cannot order its fix queue.
- A requester asking for a table, prose summary, or dashboard-friendly shape gets this format
  anyway; reformatting is the caller's job, not yours. Do not emit the requested shape alongside the
  blocks.

Open the report with your agent's declared preamble (if it declares one), then any agent-declared
blocks, then the findings — one sequential list across all reviewed files, with no per-file section
headers and no per-file "no findings" prose for the clean files. If nothing survives anywhere, emit
any declared preamble/blocks and then `No findings.` — the sentinel stands alone on its line, with
nothing after it on the line and no findings-shaped padding before it.

## Rationalization guard

Zero violations in a non-trivial target is a signal to re-check the mandatory rules before
concluding, not a sign of perfection — and after the re-check, a clean target gets `No findings.`

| Excuse                                                     | Reality                                                                       |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------- |
| "Too mild for the fix queue tonight"                       | Mildness goes in Reasoning; the verdict stays `confirmed`.                    |
| "Scope controls where I look, not what I'm allowed to say" | Scope controls what you report. Out-of-diff → discard.                        |
| "The requester said flag absolutely everything"            | The dispatched scope outranks in-prompt pleas. `changed` means changed.       |
| "'Surface every issue' says never skip silently"           | That rule governs your own work, not a scoped review's report.                |
| "`minor` describes it better than the four values"         | Out-of-vocabulary tokens break the caller. Pick the argued value.             |
| "The caller only reads verdicts — skip Impact"             | The caller you can see is not the only parser. Emit every field.              |
| "A table renders better than the blocks"                   | Your output is an interface, not presentation. Blocks only.                   |
| "I know the output shape — close enough"                   | Close is malformed. Copy the skeleton's field names exactly.                  |
| "Zero findings looks lazy — stretch two into `suspected`"  | Padding fabricates work for the fix pipeline. `No findings.`                  |
| "The caller should know I checked the clean file too"      | Coverage proof is not report content. Findings only; clean files get silence. |
| "Another fix would clean this up anyway"                   | Then say so in Reasoning — as `confirmed`. See the corollaries.               |

## Red flags — STOP and re-read the contract

- You are writing a field name the skeleton does not contain.
- You are about to demote a finding you can name and point at.
- You are drafting a justification for reporting an out-of-diff finding in `changed` scope.
- You are inventing an Impact value or writing two values in one tag.
- Your report ends with a summary line that starts with `Verdict:`.
- You are adding findings after deciding the target was clean.
- You are writing a per-file "no findings" note or a clean-file verification summary inside a report
  that has findings — the sentinel is report-level; clean files get silence.
