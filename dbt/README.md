# `dbt/` — Transform & Test (L3 / L4)

The **dbt Core** project that turns `RAW` into the BI-facing star schema, and tests it. This is
where most of the project's work lives: **24 models**, **52 tests**, and a layered
`staging → intermediate → marts` flow.

## Structure

| Path | What's there |
|------|--------------|
| `models/staging/olist/` | 10 `stg_olist__*` **views** — 1:1 cleaned (cast, rename, one hard problem each, e.g. the geolocation collapse). [ADR-014](../DECISIONS.md) |
| `models/intermediate/` | Business logic **views** — grain collapses, FX gap-fill, 3-state reconciliation, and the auditable `rejects` table. [ADR-015](../DECISIONS.md) |
| `models/marts/` | The star schema as **tables** — `fct_order_items`, `fct_orders`, 5 conformed dims, and `customer_summary`. [ADR-016](../DECISIONS.md) |
| `macros/` | Reusable logic: `delivery_days`, `is_late`, `order_item_revenue`, `brl_to`, `rfm_bucket`, `aov`, plus a `generate_schema_name` override. |
| `tests/` | Singular tests — no-negative-money, delivered-after-purchase, the two facts reconcile, delivered-orders-have-a-date. |
| `seeds/` | The Brazilian national-holiday calendar feeding `dim_dates`. |

## Conventions

- dbt-Labs naming (`stg_<source>__<entity>`, `_<source>__sources.yml`, etc.).
- Schema routing via a `generate_schema_name` override so models land in `STAGING` /
  `INTERMEDIATE` / `MARTS` verbatim (no `STAGING_STAGING` concatenation).
- `profiles.yml` is local + gitignored; connects as the **transformer** service user
  (key-pair, role `OLIST_TRANSFORMER`).

## Run it

```bash
dbt build --profiles-dir .     # run + test staging → intermediate → marts
dbt docs generate              # build the lineage graph + catalog
```

Full rationale for every modelling choice is in [`../DECISIONS.md`](../DECISIONS.md)
(ADR-014 staging · ADR-015 intermediate · ADR-016 marts).
