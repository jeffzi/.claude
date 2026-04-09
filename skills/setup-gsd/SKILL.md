---
name: setup-gsd
description: >
  Use when setting up GSD model overrides for a new project.
  Run once after /gsd:new-project or /gsd:new-milestone.
model: haiku
effort: low
disable-model-invocation: true
---

# Setup GSD

Prefer opus for research-heavy agents, haiku for mechanical tasks.

## Model Overrides

```json
{
  "gsd-phase-researcher": "opus",
  "gsd-debugger": "opus",
  "gsd-research-synthesizer": "haiku",
  "gsd-nyquist-auditor": "haiku",
  "gsd-doc-verifier": "haiku",
  "gsd-user-profiler": "haiku"
}
```

## Instructions

1. Read `.planning/config.json`. If the file does not exist, abort and tell the user to run
   `/gsd:new-project` first.
2. Set `"model_profile": "balanced"` (base profile)
3. If `model_overrides` key already exists, merge (new values win)
4. If it doesn't exist, add it
5. Write the file back
6. Show a table of all GSD agents with their resolved model (profile default unless overridden) so
   the user can verify

Only touch `model_profile` and `model_overrides`. Do NOT change any other config keys.
