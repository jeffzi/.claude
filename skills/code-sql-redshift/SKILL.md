---
name: code-sql-redshift
description: >
  Use when writing SQL, DDL, or dbt models targeting Amazon Redshift (provisioned or
  Serverless), including Spectrum external tables. Use before asserting a SQL feature
  does or does not exist on Redshift — especially QUALIFY — before setting dist keys,
  sort keys, or column encodings, before wrapping a query in a CTE just to reuse a
  select alias, and before a bulk UPDATE on a large table. Loaded by code-sql on
  Redshift targets; not for other warehouses or generic SQL style.
user-invocable: false
---

# Redshift SQL — Pinned Dialect Facts and Tuning Defaults

**This skill extends `Skill(code-sql)`.** Its job is to pin volatile Redshift facts where model
memory is unreliable — baseline agents asserted both that QUALIFY works and that "Redshift's parser
rejects it" — and to stop stale tuning reflexes. When a fact below conflicts with what you remember,
this file wins; if you suspect this file has drifted — every fact below was verified 2026-08, dated
inline where more precision matters — verify against the AWS docs before asserting either way.

## QUALIFY is supported

Redshift supports `QUALIFY` to filter window-function results without a subquery. **When `QUALIFY`
directly follows `FROM`, the FROM relation must have an alias.** An intervening clause (`WHERE`,
`GROUP BY`) lifts the requirement — which is why the folk fix `where true` appears to "enable"
QUALIFY. The alias is the direct fix.

```sql
-- fails: qualify directly follows from, and the relation has no alias
select *
from raw_app.event
qualify row_number() over (partition by event_id order by event_ts desc) = 1

-- works: alias satisfies the rule
select *
from raw_app.event as event
qualify row_number() over (partition by event_id order by event_ts desc) = 1
```

Never assert QUALIFY is unsupported, and never rewrite to the `row_number()` subquery "for
portability" — the target is Redshift; portability is not a requirement here.

## Lateral alias reuse — no CTE wrapper needed

A select-list expression can reference an alias defined earlier in the same `select`. Never wrap a
query in a CTE or subquery just to reuse an aggregate:

```sql
select
    count(*) as order_count,
    count(case when last_status = 'done' then 1 end) as converted_count,
    round(100.0 * converted_count / order_count, 2) as conversion_pct
from fact_order
```

For share-of-total, use `ratio_to_report(expr) over ()` instead of `expr / sum(expr) over ()` — and
the alias it reads can itself be a reused one.

## getdate(), not current_timestamp

`getdate()` returns `timestamp without time zone` natively — it compares against `timestamp` columns
with no cast. `current_timestamp` is timezone-typed and invites type-mismatch errors.

## ORDER BY after UNION/INTERSECT/EXCEPT takes no expressions

On a set-operator result, `order by` accepts only result column names or positions. To order by an
expression, wrap the union in a CTE and order in the outer query:

```sql
with unioned as (
    select country_name from dim_country
    union all
    select 'All'
)
select * from unioned
order by (country_name = 'All') desc, country_name
```

## Bulk UPDATE on a large table — diff with EXCEPT first

Redshift UPDATEs are internally delete + insert; a self-join subquery in the `FROM` clause forces
two full scans of the same table and can hang for hours at billions of rows. Compute the target rows
with `EXCEPT` into a temp table (deduped, merge-joined — no self hash join), then run the UPDATE
against the small temp table:

```sql
create temp table rows_to_fix as
select distinct app_id, mediation, ds
from fact_ad_impression
where is_reconciled = false and source_name = 'appsflyer'
except
select distinct app_id, mediation, ds
from raw_mediation;

update fact_ad_impression
set is_reconciled = true
from rows_to_fix
where fact_ad_impression.app_id = rows_to_fix.app_id
  and fact_ad_impression.mediation = rows_to_fix.mediation
  and fact_ad_impression.ds = rows_to_fix.ds
  and fact_ad_impression.source_name = 'appsflyer'
  and fact_ad_impression.is_reconciled = false;
```

This pattern took a hanging UPDATE on a 9B-row table from "killed after hours" to minutes.

## DATEDIFF counts boundary crossings, not elapsed time

`datediff(year, '2009-12-31', '2010-01-01')` returns **1** — one year boundary was crossed, though a
day elapsed. Same for every date part. When elapsed intervals matter, diff at a finer grain and
convert, or compare truncated dates deliberately.

## Table tuning: AUTO first

`DISTSTYLE AUTO`, `SORTKEY AUTO`, and `ENCODE AUTO` are the defaults, and Automatic Table
Optimization adjusts them from observed workload. They are correct for staging tables, small tables,
and any table without a measured access pattern.

Hand-set `distkey`/`sortkey` only with a stated reason tied to a known workload (e.g. colocating a
large fact with its dimension on the join key, date sortkey for the dominant range filter) — and say
so in the model config or DDL comment. Never hand-assign per-column encodings "to be safe":
unmeasured guesses override AUTO and opt the table out of ATO.

## UDFs: SQL or Lambda, never Python

Python UDFs reached end of support June 30, 2026 (enforcement is phased). Never write a new one.

## Views over Spectrum external tables need late binding

A regular view over an external table fails — create it `with no schema binding`.

## Rationalizations That Mean You're About to Fail

| Excuse                                        | Reality                                                       |
| --------------------------------------------- | ------------------------------------------------------------- |
| "Redshift doesn't support QUALIFY"            | Stale. Supported — see the alias rule above.                  |
| "The subquery form is more portable"          | The target is Redshift only. Use QUALIFY.                     |
| "Explicit encodings can't hurt"               | They replace AUTO with unmeasured guesses and opt out of ATO. |
| "A CTE is needed to reuse that aggregate"     | Lateral alias reuse works inside one select. No wrapper.      |
| "The self-join UPDATE will finish eventually" | Two full scans at billions of rows. EXCEPT-diff first.        |
| "Every serious table needs dist/sort keys"    | AUTO + ATO is the default; manual keys need a stated reason.  |
| "I remember the docs saying X"                | Dated facts above outrank memory; verify drift via AWS docs.  |

## Red Flags — Stop and Fix

- Asserting a Redshift feature exists or doesn't without checking this file first.
- `encode` on every column of a staging or small table.
- A `distkey`/`sortkey` with no stated workload reason.
- A new Python UDF.
- A CTE or subquery whose only purpose is reusing a select alias.
- `expr / sum(expr) over ()` where `ratio_to_report` fits.
- `current_timestamp` compared against a `timestamp` column.
- A bulk UPDATE on a large table driven by a self-join subquery.
