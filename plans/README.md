# plans/

Spec-driven workflow: **a short written plan goes here before each module is built.**
One markdown file per module, numbered in build order.

## Convention

- One file per module, named `NN-short-slug.md` (e.g. `01-dlt-load.md`).
- Write the plan *before* coding the module; record what you'll build and why.
- When the module is done, the durable decisions graduate to `../DECISIONS.md`
  and the status updates in `../PROGRESS.md`.

## Suggested sequence (mirrors CONTEXT.md / PROGRESS.md)

| File | Module |
|------|--------|
| `01-snowflake-setup.md` | L2 — warehouse / db / schemas / role / user |
| `02-dlt-load.md`        | L1 — dlt hybrid pipeline + FX fetch → RAW |
| `03-dbt-staging.md`     | L3 — stg_* cleaned views |
| `04-dbt-intermediate.md`| L3 — business logic, macros, rejects routing |
| `05-dbt-marts.md`       | L3 — star schema (2 facts + dims + customer_summary) |
| `06-dbt-tests-docs.md`  | L4 — generic / singular / conditional tests + docs |
| `07-airflow-dag.md`     | L5 — Astro orchestration DAG |
| `08-bi.md`              | L6 — dashboards (tool TBD) |
