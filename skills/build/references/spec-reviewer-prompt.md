# Spec Compliance Reviewer — moved

The reviewer is now a defined agent: `~/.claude/agents/spec-reviewer.md` (canonical instructions,
output contract, and the `Missing:`/`Extra:`/`Misunderstood:` prefix requirement live there).

The plan-executor dispatches it directly with the task's verbatim spec text, the implementation
files, and the test files — no prompt template to fill. On `SPEC_STATUS: FAIL`, remediation routing
stays with the orchestrator: see the FAIL path in `~/.claude/agents/plan-executor.md`.
