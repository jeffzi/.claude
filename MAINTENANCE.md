# .claude Repository Maintenance

## Marimo Documentation Setup

The marimo skill references documentation at `skills/marimo/marimo-docs/docs/api/` but this directory is **not tracked in git** (too large).

### Initial Setup

Clone the marimo repository locally:

```bash
cd /Users/jeffzi/.claude/skills/marimo
git clone --depth 1 https://github.com/marimo-team/marimo.git marimo-docs
```

### Updating Documentation

To pull the latest docs:

```bash
cd /Users/jeffzi/.claude/skills/marimo/marimo-docs
git pull
```

**Note:** The `marimo-docs/` directory is gitignored. Claude reads it from your local filesystem when using the skill.
