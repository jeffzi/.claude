---
name: tsgo-lsp
description: >
  Config carrier, not an instruction skill. Registers the TypeScript 7 native language server
  (tsgo --lsp) so LSP works in projects that pin typescript@7, which ships no tsserver.js.
user-invocable: false
disable-model-invocation: true
lspServers:
  typescript:
    command: tsgo
    args: ["--lsp", "--stdio"]
    extensionToLanguage:
      ".ts": typescript
      ".tsx": typescriptreact
      ".mts": typescript
      ".cts": typescript
      ".js": javascript
      ".jsx": javascriptreact
      ".mjs": javascript
      ".cjs": javascript
---

# tsgo LSP registration

This file exists for its frontmatter. Claude Code's `skill-as-plugin` loader hoists `lspServers`
from a skill's frontmatter into a synthetic plugin manifest, which is the supported way to register
a language server from `~/.claude` — `settings.json` has no top-level `lspServers` key.

## Why it replaces the `typescript-lsp` plugin

That plugin spawns `typescript-language-server`, which requires a `tsserver.js` and refuses to start
without one:

```text
Could not find a valid TypeScript installation. Please ensure that the "typescript"
dependency is installed in the workspace or that a valid `tsserver.path` is specified.
```

TypeScript 7 is the native Go port. Its package ships `lib/tsc.js`, `lib/version.cjs`, and a
platform binary — no `tsserver.js` — so any project pinning `typescript@7` gets no LSP at all. The
server has no fallback: it fails identically in a directory with no TypeScript installed.

`tsgo` speaks LSP directly over `--lsp --stdio` at the same version the project compiles with, so
hover and diagnostics agree with `tsc`. Both servers are registered under the name `typescript`;
`typescript-lsp` is disabled in `settings.json` so they don't compete.

## Requirement

`tsgo` must be on `PATH`:

```bash
npm install -g @typescript/native-preview
```

If it is missing, TypeScript LSP silently goes dead rather than falling back — re-enable the
`typescript-lsp` plugin in `settings.json` to restore the old behavior.
