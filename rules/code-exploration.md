---
paths:
  - "**/*.py"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.rs"
  - "**/*.go"
  - "**/*.lua"
  - "**/*.swift"
  - "**/*.sh"
---

# Code Exploration Protocol

When exploring a codebase, orient before drilling:

1. **Structure first** — use LSP `documentSymbol` or Grep for function/class signatures. Never read
   a file end-to-end.
2. **Targeted reads** — identify 2-3 relevant functions, read only those with line offset.
3. **Cross-reference** — use Grep or LSP `findReferences` to trace callers if needed.
