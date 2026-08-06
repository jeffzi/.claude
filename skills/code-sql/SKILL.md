---
name: code-sql
description: >
  Use when writing or reviewing any SQL — queries, dbt models, DDL, migrations — in any
  dialect, before choosing any schema, table, or column name. Use when tempted to invent
  naming conventions, import outside prefixes (stg_/fct_), or uppercase keywords —
  the house conventions already decide these. Not for Redshift dialect specifics — that
  is code-sql-redshift, loaded from here. Applies to *.sql files and SQL inside dbt models.
user-invocable: false
---

# SQL Conventions — Naming and Style

**This skill extends `Skill(code-core)`.** It is loaded via the Language Dispatch table for `.sql`
files and SQL embedded in dbt models.

**Core principle: names are the warehouse's public API.** Tables and columns outlive every
application that queries them; a rename breaks dashboards silently. Naming is decided by these
conventions, never per-session taste — an agent that "sets conventions" for a new model is
overwriting conventions that already exist. Violating the letter of these conventions is violating
their spirit — no technicalities, no per-model exemptions.

## Domain Skill Detection

| Signal                      | Skill to load       |
| --------------------------- | ------------------- |
| Redshift/Spectrum mentioned | `code-sql-redshift` |

Only load skills that are actually installed. If a skill fails to load, continue without it.

## Tables — `TYPE_SUBJECT[_NAME]`

| TYPE   | Meaning                                                        |
| ------ | -------------------------------------------------------------- |
| `raw`  | Untransformed data from an external source                     |
| `dim`  | Dimension: slowly changing attributes of an entity             |
| `fact` | Fact: point-in-time measurements/metrics of a business process |

SUBJECT is the warehouse subject area (`ua`, `ad`, …); NAME is optional, ideally one word: `raw_ua`,
`fact_ua`, `dim_user`.

- Singular, collective names: `activity` not `activities`, `order_detail` not `order_details` —
  masters sort before details and there is no plural to misguess.
- Never `fct_`, `stg_`, `tbl_`, or any other prefix outside the TYPE table above.
- Never give a table the same name as one of its columns, or vice versa.

## Columns

Singular names, always: `click_count` not `clicks_count`. Exception: industry-accepted forms keep
their plural — `days_since_install`, never `day_since_install`. Suffixes and prefixes carry the type
— use them instead of inventing:

| Suffix                                         | Meaning                                            |
| ---------------------------------------------- | -------------------------------------------------- |
| `_ds`                                          | date(stamp)                                        |
| `_ts`                                          | time(stamp)                                        |
| `_status` / `_type`                            | flag value / bounded categorical                   |
| `_id` / `_key` / `_pk`                         | source identifier / system join key / primary key  |
| `_dX`                                          | X days since install (`retention_d7`)              |
| `_revenue` / `_net_revenue` / `_gross_revenue` | revenue (decimal)                                  |
| `_prop` / `_pct` / `_pctl`                     | proportion [0,1] / unbounded percent / percentile  |
| `_name` / `_count` / `_amt`                    | **sparingly**, only when needed to avoid confusion |

Prefixes: `is_` / `has_` for booleans, `total_` for sums, `pred_` for predicted values.

Baseline reflexes this table replaces:

```text
✗ spend_date, valid_from_at        ✓ spend_ds, valid_from_ts
✗ _loaded_at (leading underscore)  ✓ loaded_ts — names start with a letter
✗ retention_d7_rate                ✓ retention_d7_prop (bounded 0–1)
✗ gross_revenue_usd                ✓ gross_revenue — currency is a warehouse invariant
✗ payer_cnt, click_cnt             ✓ payer_count, click_count — `_count`, never `_cnt`
```

## Query Structure

| Area        | Rule                                                                                                                                           |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Joins       | Write the type: `inner join`, never bare `join`. Never comma joins, incl. `lateral`.                                                           |
| Joins       | **Prefer `using (col)` over `on a.col = b.col`** whenever the key columns share a name.                                                        |
| Aliases     | Never single-letter (`a`, `b`) — full table/CTE name when short, descriptive when long.                                                        |
| Aliases     | Alias with `as`, always: `sum(x) as total_x`, never `sum(x) total_x`.                                                                          |
| Columns     | Qualify every column in a multi-table query. Rename ambiguous source columns at the first select: `id` → `account_id`.                         |
| CTEs        | CTEs over subqueries, at the top. One logical unit of work each; short name + comment over a sentence-length name.                             |
| Aggregation | Non-aggregated columns first, aggregates after. Grouped columns leading the select list → positional `group by 1, 2, 3` (same for `order by`). |
| Aggregation | Never `group by all` — it silently changes grain when a column is added.                                                                       |
| Expressions | `!=` never `<>` · `where` over `having` when either works · `union all` unless dedup is the intent · booleans `true`/`false`, never `1`/`0`.   |
| Expressions | Repeated equality on one column → simple CASE: `case field_id when 1 then 'date' … end`.                                                       |
| Comments    | `code-core`'s no-TODO rule covers every comment — a doc-link placeholder is still a `TODO`; file an issue.                                     |
| Comments    | A non-obvious calculation gets a one-line comment plus a link to the canonical metric definition, where one exists.                            |

## Formatting

Formatting is owned by **sqlfmt** (shandy-sqlfmt, the tool that reads `[tool.sqlfmt]` — not the
identically named Go formatter) — never hand-tune indentation or line breaks; the formatter rewrites
them. Line length comes from the project's `[tool.sqlfmt]` config.

- **Lowercase SQL keywords, always.** Never uppercase, not even in DDL. Uppercase is the strongest
  model reflex in SQL — write lowercase from the start, never leave it for sqlfmt to fix.

## Rationalizations That Mean You're About to Fail

| Excuse                                        | Reality                                                        |
| --------------------------------------------- | -------------------------------------------------------------- |
| "No conventions exist here, so I'll set them" | They exist — this file. Apply them.                            |
| "stg_/fct_ prefixes are the common standard"  | The house prefixes are `fact_`, `dim_`, `raw_` — only.         |
| "_usd documents the currency"                 | Revenue columns end in `_revenue`; currency is not per-column. |
| "Leading underscore marks metadata columns"   | Names start with a letter: `loaded_ts`, `extracted_ts`.        |
| "Uppercase keywords are standard SQL"         | Lowercase here, unconditionally.                               |
| "Plural table names read more naturally"      | Singular is the contract; plurals fork into irregular forms.   |
| "`on` is more explicit than `using`"          | `using (col)` is the house form when key names match.          |
| "Bare `join` defaults to inner anyway"        | The type is written out: `inner join`, every time.             |
| "`group by all` is DRY and safer"             | It hides grain changes. List columns or positions.             |

## Red Flags — Stop and Fix

- A `create table` or dbt model with plural name, or `fct_`/`stg_`/`tbl_` prefix.
- A column ending `_date`, `_at`, `_rate`, `_amount`, or a currency code.
- A name starting or ending with an underscore, or containing consecutive underscores.
- An uppercase SQL keyword.
- A bare `join`, a comma join, or a single-letter table alias.
- `group by all`, `<>`, `having` doing a `where`'s job, or a `TODO` comment.
- An unqualified column in a multi-table select, or a bare `id`/`name`/`type` surviving past the
  first select.

## Verification

Run `sqlfmt <file>` before completion. Naming cannot be linted — review every new name against the
tables above before shipping.
