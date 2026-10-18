# Fork Dispatch — Multi-Group Step 4

Read this before dispatching step 4's forks: one fork per transitive file group.

Each fork's prompt names the checkpoint path and its group's finding numbers, and tells the fork to:

1. Read those findings' blocks from the checkpoint.
2. Load the leaf's step-4 skills before editing.
3. Check each finding against the leaf's surfacing rules before applying it. A finding they route
   away is not applied, however `confirmed` it is.
4. Apply the remaining findings one at a time, in checkpoint order.
5. Return one line per finding: `FIXED: <finding N — rule satisfied>`, `FAILED: <finding N —
   reason>`, or `SURFACED: <finding N — surfacing rule>`.

A fork never writes the checkpoint and never runs repo-wide verification. The parent sets each
finding's `Status:` from the returns as forks land — `fixed` from `FIXED`, `report-only: <reason>`
from `FAILED`, `report-only: <surfacing rule>` from `SURFACED` — then verifies once in step 5.
