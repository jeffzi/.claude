# Project-Owned Keys

Keys the template ships with a default value but the project may freely override. Exclude from every
reconcile bucket — read them (so they aren't miscounted as removals) but keep their value as-is.
Never surface as drift.

| File                             | Owned keys                                                 |
| -------------------------------- | ---------------------------------------------------------- |
| `fallow.json` → `.fallowrc.json` | `entry`                                                    |
| `cspell.json`                    | `words`                                                    |
| `tsconfig.build.json`            | `outDir`, `rootDir`, `include`                             |
| `tsconfig.json`                  | `paths`                                                    |
| `vitest.config.ts`               | `coverage.thresholds` values                               |
| `AGENTS.md`                      | Every section except `## Commands`                         |
| `package.json`                   | Every top-level key except `scripts` and `devDependencies` |

Within `devDependencies`, version ranges are project-owned — only the key set is reconciled
(presence/absence); version bumps are `/upgrade-ts`'s job.

Everything else is a house rule — in particular `tsconfig.json` `include` and `noEmit`, which carry
the tests-are-type-checked rule: `tsconfig.json` is the check/editor config covering `src` +
`tests`, `tsconfig.build.json` is the emit config covering `src` only.
