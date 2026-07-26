# CLAUDE.md Quality Reference

## Scoring Rubric

Total: 100 points across six criteria. Grade thresholds: A (90-100), B (70-89), C (50-69), D
(30-49), F (0-29).

### Commands/Workflows (20 points)

| Score | Criteria                                                             |
| ----- | -------------------------------------------------------------------- |
| 20    | All essential commands (build, test, lint, dev, deploy) with context |
| 15    | Most commands present, some missing context                          |
| 10    | Basic commands only, no workflow                                     |
| 5     | Few commands, many missing                                           |
| 0     | No commands documented                                               |

### Architecture Clarity (20 points)

| Score | Criteria                                                                 |
| ----- | ------------------------------------------------------------------------ |
| 20    | Key directories explained, module relationships, entry points, data flow |
| 15    | Good structure overview, minor gaps                                      |
| 10    | Basic directory listing only                                             |
| 5     | Vague or incomplete                                                      |
| 0     | No architecture info                                                     |

### Non-Obvious Patterns (15 points)

| Score | Criteria                                                                       |
| ----- | ------------------------------------------------------------------------------ |
| 15    | Gotchas, workarounds, edge cases, "why we do it this way" for unusual patterns |
| 10    | Some patterns documented                                                       |
| 5     | Minimal pattern documentation                                                  |
| 0     | No patterns or gotchas                                                         |

### Conciseness (15 points)

| Score | Criteria                                                                       |
| ----- | ------------------------------------------------------------------------------ |
| 15    | Dense, valuable — every line earns its place, no redundancy with code comments |
| 10    | Mostly concise, some padding                                                   |
| 5     | Verbose in places                                                              |
| 0     | Mostly filler or restates obvious code                                         |

### Currency (15 points)

| Score | Criteria                                                    |
| ----- | ----------------------------------------------------------- |
| 15    | Commands work, file references accurate, tech stack current |
| 10    | Mostly current, minor staleness                             |
| 5     | Several outdated references                                 |
| 0     | Severely outdated                                           |

### Actionability (15 points)

| Score | Criteria                                              |
| ----- | ----------------------------------------------------- |
| 15    | Commands copy-paste ready, steps concrete, paths real |
| 10    | Mostly actionable                                     |
| 5     | Some vague instructions                               |
| 0     | Vague or theoretical                                  |

## Red Flags

- Commands that would fail (wrong paths, missing deps)
- References to deleted files/folders
- Outdated tech versions
- Copy-paste from templates without customization
- Generic advice not specific to the project
- `TODO` items never completed
- Duplicate info across multiple CLAUDE.md files

---

## Update Guidelines

### What TO add

| Category              | Example                                                            | Why                                            |
| --------------------- | ------------------------------------------------------------------ | ---------------------------------------------- |
| Commands/workflows    | `npm run build:prod` — full production build with optimization     | Saves future sessions from rediscovering these |
| Gotchas               | Tests must run sequentially (`--runInBand`) due to shared DB state | Prevents repeating debugging sessions          |
| Package relationships | `auth` module depends on `crypto` being initialized first          | Architecture knowledge not obvious from code   |
| Testing patterns      | For API endpoints: use `supertest` with `tests/setup.ts`           | Establishes patterns that work                 |
| Configuration quirks  | `NEXT_PUBLIC_*` vars must be set at build time, not runtime        | Environment-specific knowledge                 |

### What NOT to add

| Category               | Bad example                                               | Why                                    |
| ---------------------- | --------------------------------------------------------- | -------------------------------------- |
| Obvious code info      | "The `UserService` class handles user operations"         | The class name already says this       |
| Generic best practices | "Always write tests for new features"                     | Universal advice, not project-specific |
| One-off fixes          | "We fixed a bug in commit abc123 where login didn't work" | Won't recur; clutters the file         |
| Verbose explanations   | Multi-paragraph JWT explainer when one line suffices      | Context window is precious             |

---

## Templates

Use only the sections relevant to the project. These are starting points — customize for the
specific codebase.

### Minimal (project root)

````markdown
# <Project Name>

<One-line description>

## Commands

| Command     | Description   |
| ----------- | ------------- |
| `<command>` | <description> |

## Architecture

```
<structure>
```

## Gotchas

- <gotcha>
````

### Comprehensive (project root)

````markdown
# <Project Name>

<One-line description>

## Commands

| Command     | Description   |
| ----------- | ------------- |
| `<command>` | <description> |

## Architecture

```
<structure>
```

## Key Files

- `<path>` - <purpose>

## Code Style

- <convention>

## Environment

- `<VAR>` - <purpose>

## Testing

- `<command>` - <what it tests>

## Gotchas

- <gotcha>
````

### Package/Module

For packages within a monorepo or distinct modules.

````markdown
# <Package Name>

<Purpose of this package>

## Usage

```
<import/usage example>
```

## Key Exports

- `<export>` - <purpose>

## Dependencies

- `<dependency>` - <why needed>

## Notes

- <important note>
````

### Monorepo Root

```markdown
# <Monorepo Name>

<Description>

## Packages

| Package  | Description | Path     |
| -------- | ----------- | -------- |
| `<name>` | <purpose>   | `<path>` |

## Commands

| Command     | Description   |
| ----------- | ------------- |
| `<command>` | <description> |

## Cross-Package Patterns

- <shared pattern>
- <generation/sync pattern>
```

---

## CLAUDE.md File Types

| Type           | Location                 | Purpose                                      |
| -------------- | ------------------------ | -------------------------------------------- |
| Project root   | `./CLAUDE.md`            | Primary project context (checked in, shared) |
| Local override | `./.claude.local.md`     | Personal/local settings (gitignored)         |
| Global default | `~/.claude/CLAUDE.md`    | User-wide defaults across all projects       |
| Package        | `./packages/*/CLAUDE.md` | Module-level context in monorepos            |
| Subdirectory   | Any nested location      | Feature/domain-specific context              |

Claude auto-discovers CLAUDE.md files in parent directories — monorepo setups work automatically.
