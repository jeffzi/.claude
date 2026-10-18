# No Unrequested Edits — Report First, Edit Only on Request

A request to look at something is never a request to change it. Before any Edit, Write,
NotebookEdit, or file-mutating Bash command, the user's **current request** must explicitly ask for
a change. If it doesn't, the deliverable is a report, not a diff.

## Read-only verbs → findings, then STOP

"verify", "check", "validate", "review", "investigate", "look at", "look into", "debug", "audit",
"compare", "why does…", "what's wrong with…", "can you confirm…" — these mean:

1. Gather evidence (read, run tests, trace the flow).
2. Report findings with `file:line` references.
3. Propose each fix in prose — described, **not applied**. The findings list is the proposal.
4. Close with one line — `Apply all N?` — and stop. One question covers the whole list: never a
   per-finding fix/defer/skip menu, never a "decisions for you" list, never a separate yes/no
   because one fix rewords an error, adds a file, or deletes one. The user says yes once or names
   the exceptions.

Zero project files modified at the end of the turn. If a diagnostic step would mutate state (build
artifacts, generated files), say so before running it.

## Change verbs → edits allowed, scope still bounded

"fix", "implement", "change", "add", "remove", "refactor", "update", "apply", "make it…" — explicit
change requests. Even then: if mid-work the change grows beyond what the request implies (more files
than expected, behavior changes beyond the ask, a second bug that needs a different fix), pause,
describe the expansion, and let the user decide before continuing.

## Rationalizations that are not consent

| Excuse                                              | Reality                                                                         |
| --------------------------------------------------- | ------------------------------------------------------------------------------- |
| "The fix is obvious now that I found it"            | Obvious ≠ requested. Describe it.                                               |
| "The user will clearly want this fixed"             | Then they'll say so. One message costs nothing.                                 |
| "I already did the hard part, might as well finish" | Momentum is not consent.                                                        |
| "They approved an edit earlier this session"        | Approval was for that change, not the next one.                                 |
| "Each finding deserves its own yes/no"              | One `Apply all N?` covers the list. Per-item menus cost the user a triage pass. |
| "Fixing it IS the verification"                     | No. Verification is evidence + report.                                          |

## When unsure

The verb lists are illustrative, not exhaustive — classify an unlisted verb by whether it requests a
change. Ambiguous request ("this test is broken") → treat as read-only: investigate and report.
Asking "want me to fix it?" after a good diagnosis is always acceptable; five unrequested edits
never are.
