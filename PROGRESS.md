# PROGRESS.md

Living build tracker for the Olist ELT Warehouse. The project is broken into
**Phases**; work through them top to bottom, one step at a time. A short plan goes
in [`plans/`](./plans) before each phase begins (see `CLAUDE.md`).

**Convention:** `[ ]` = Not started · `[-]` = In progress · `[x]` = Completed · `[~]` = Dropped

_Last updated: 2026-06-22_

---

## Phase 0 — Project Setup & Environment  `[x]`

Get the local toolchain and accounts ready. (Owner drives account signups; Claude generates + guides.)

- `[x]` Scaffold repo skeleton (folders, `.gitignore`, README skeleton, tracking files)
- `[x]` Install Python 3.12 (python.org) alongside the existing Store 3.13
- `[x]` Create Python virtual environment (`.venv` on 3.12) and install `requirements.txt`
- `[x]` Verify tool installs — dlt 1.28.0, dbt-core 1.11.11 + snowflake adapter 1.11.5, `pip check` clean
- `[x]` Pin installed versions in `requirements.txt` for reproducibility
- `[x]` Kaggle: 9 CSVs present in `data/raw/` (already downloaded)
- `[x]` Confirm Snowflake account available — account `NEB29791` (AWS), role ACCOUNTADMIN
- `[~]` Install the Astro CLI — deferred to Phase 7

## Phase 1 — Snowflake Warehouse Setup (L2)  `[x]`

Stand up the warehouse objects. Owner runs SQL in the Snowflake UI; Claude generates the SQL + explains each statement.

- `[x]` Generate setup SQL in `snowflake/` (warehouse, database, role, user, grants)
- `[x]` Create `RAW`, `STAGING`, `INTERMEDIATE`, `MARTS` schemas
- `[x]` Create a dedicated role + user for dlt and dbt to connect with (two scoped service users — see ADR-012)
- `[x]` Confirm a local connection works (credentials reach the warehouse) — both users verified; transformer DENIED `RAW` (least privilege proven)

## Phase 2 — Load Layer: dlt (L1)  `[x]`

Land raw data correctly. dlt is the loader (never Airflow — see `DECISIONS.md` ADR-003). See ADR-013.

- `[x]` Initialize the dlt project in `dlt/` with the Snowflake destination (`dlt/load_olist.py`, self-contained `dlt/.dlt/`)
- `[x]` Configure connection + secrets (key-pair via `dlt/.dlt/secrets.toml`, gitignored; `private_key_path` → `.keys/olist_loader.p8`)
- `[x]` Full-refresh the **5** reference/dim tables (products, sellers, geolocation, category_translation, **customers**) → `RAW`
- `[x]` Merge the 4 transactional tables (orders, order_items, payments, reviews) → `RAW`; **cursor** incremental on orders + reviews (real timestamps), merge-on-PK for order_items + payments (no cursor) — RAW kept 1:1 (ADR-013)
- `[x]` Seed incrementals in two passes (through 2017, then 2018 as the "new" batch)
- `[x]` Fetch FX rates (Frankfurter, BRL→USD/EUR, long format) → `RAW.fx_rates` (1,088 rows)
- `[x]` Verify RAW row counts match the source CSVs (all 9 exact; parsed with a real CSV reader, not line-count)

## Phase 3 — Transform: dbt Staging (L3)  `[x]`

1:1 cleaned views, one hard problem each. See `DECISIONS.md` ADR-014 + `plans/3.dbt-staging.md`.

- `[x]` Initialize the dbt project (manual scaffold), configure `profiles.yml` (key-pair, `--profiles-dir .`), `dbt debug` passes; `generate_schema_name` override routes models into `STAGING`
- `[x]` Declare `RAW` sources (`olist_raw`, 10 tables)
- `[x]` Build 10 `stg_olist__*` views: cast (VARCHAR→`timestamp_ntz`) + light-touch rename (`lenght`→`length`); drop `_dlt_*`; collapse geolocation to 1 row/zip (median coords + deterministic modal city). **Category translation kept as its own 1:1 model; PT→EN join deferred to intermediate/marts (refines CONTEXT §4)**
- `[x]` Add staging tests (32: PK unique+not_null, composite via `dbt_utils`, accepted_values) — all pass

## Phase 4 — Transform: dbt Intermediate (L3)  `[x]`

Business logic + reusable macros. See `DECISIONS.md` ADR-015 + `plans/4.dbt-intermediate.md`. 24/24 tests pass.

- `[x]` Build macros: `delivery_days()`, `is_late()`, `order_item_revenue()`, `brl_to()` (FX conversion). **RFM bucketing + AOV deferred to Phase 5** (person/mart grain — ADR-015)
- `[x]` Collapse payment installments → 1 row/order (`int_olist__payments_pivoted`: dominant method + multi-method flag)
- `[x]` Dedup multi-review orders (`int_olist__reviews_deduped`: latest wins; removed 551 extra reviews)
- `[x]` PT→EN category join (`int_olist__products_enriched`, deferred from staging); FX gap-fill (`int_olist__fx_rates_filled`, LOCF + leading back-fill)
- `[x]` **Q6 confirmed (ADR-009/015):** 3-state reconciliation flag (kept) + consolidated `int_olist__rejects` (0 orphans, 1 `order_no_payment`)

## Phase 5 — Transform: dbt Marts (L3)  `[x]`

The star schema — the real modeling work. See `DECISIONS.md` ADR-016 + `plans/5.dbt-marts.md`. 8 models, 46/46 tests pass.

- `[x]` Dimensions: `dim_customers` (99,441), `dim_products` (32,951), `dim_sellers` (3,095), `dim_dates` (1,096; full 2016–2018 + BR holiday seed), `dim_geography` (19,015, conformed). Keying = **hybrid** (natural keys for entities; `date_key` YYYYMMDD surrogate; zip natural key). All materialized as **tables**.
- `[x]` `fct_order_items` at order-item grain (112,650, no fan-out): revenue BRL + **item-grain FX** (USD/EUR on purchase date)
- `[x]` `fct_orders` at order grain (99,441, no fan-out): delivery, payment, review, 3-state reconciliation + 3 role-playing date keys
- `[x]` `customer_summary` at person grain (96,096 = distinct `customer_unique_id`): RFM (NTILE 5) + AOV + historical CLV; `rfm_bucket`/`aov` macros built here

## Phase 6 — Test & Document (L4)  `[x]`

Trustworthy, auditable data — honor the Provenance DNA. See `plans/6.test-and-document.md`. **52 marts tests: 49 PASS, 3 documented WARN, 0 ERROR.**

- `[x]` Generic tests: unique, not_null, relationships, accepted_values — comprehensive across all layers (no new generics needed in Phase 6; coverage already complete)
- `[x]` Singular tests (`dbt/tests/`): `assert_no_negative_money`, `assert_delivered_after_purchase`, `assert_fct_items_reconcile_to_orders` (cross-fact, 0 mismatches), `assert_delivered_orders_have_delivery_date`. **No-orphan / payment-reconcile-gate intentionally skipped** — orphans already covered by fact-FK `relationships`; reconciliation *mismatches* are flagged-and-kept (3-state), not a fail gate (ADR-009/015)
- `[x]` Conditional null test per Q6: delivered ⇒ delivery date present, at **warn** severity (surfaces 8 known Olist source anomalies; documented in ADR-009)
- `[x]` Added deferred `zip → dim_geography` relationship tests (warn): 278 customer + 7 seller zips absent from geolocation (known coverage gap)
- `[x]` Generated dbt docs + lineage graph → `figures/dbt-lineage-dag.png`, `dbt-docs-project-tree.png`, `dbt-docs-database-tree.png`

## Phase 7 — Orchestrate: Airflow (L5)  `[x]`

Wire it all into one DAG with real dependencies. See `DECISIONS.md` ADR-017 + `plans/7.airflow-orchestration.md`. **Full DAG green in 3m35s; 52 task nodes (49 dbt via Cosmos); MARTS rebuilt to exact Phase 5/6 counts.**

- `[x]` Astro CLI installed; `astro dev init` in `airflow/` → Astro Runtime 3.2-5 (**Airflow 3.2.2**). Dependency-isolated image: `dbt_venv` + `dlt_venv` (ADR-017 D2); Airflow env gets only `astronomer-cosmos`==1.14.2 + snowflake provider
- `[x]` DAG `olist_elt`: `dlt_load_olist` (runs `load_olist.py` unchanged via `dlt_venv`, creds from loader Connection) → **Cosmos `DbtTaskGroup`** (model-level run+test, transformer Connection) → `dbt_docs_generate`. Two Airflow Connections = ADR-012 least-privilege carried into Airflow; key delivery loader=file / transformer=content (ADR-017 D4). Project files mounted via `docker-compose.override.yml`
- `[x]` Retries (`retries=2`) + explicit failure branch (`notify_failure`, `trigger_rule=one_failed`); `schedule=None` (static dump → trigger on demand)
- `[x]` Ran locally end-to-end & verified: 49 dbt tasks pass (3 known WARN stay warn, 0 ERROR), `notify_failure` skipped on success, MARTS counts match (99,441 / 112,650 / 96,096). Each task pre-flighted in isolation (`airflow tasks test`) first

## Phase 8 — BI Layer (L6)  `[~]` in progress

Reads `MARTS`. **Tool decided: Power BI + `.pbip` + `pbi-cli`** (ADR-011, ADR-018).

- `[x]` Decide BI tool — **Power BI**, `.pbip` text format, built with `pbi-cli` (ADR-011)
- `[x]` Snowflake `OLIST_REPORTER` role (read MARTS only) + service user — least privilege proven (denied on RAW). Auth = **password** (untyped user; PBI build lacked key-pair) — role scoping unchanged (ADR-012 carried in)
- `[x]` Connect Power BI Desktop → `MARTS` (Import mode), loaded 8 mart tables at exact counts
- `[x]` **Semantic model built as code via pbi-cli**: full star (12 relationships incl. role-playing dates + geography snowflake), **21 measures** in folders; numbers reconcile (Orders 99,441 · Customers 96,096 · Revenue R$15.84M)
- `[x]` **Page 1 (Sales & Revenue) built as code**: 4 KPI cards + revenue-over-time + revenue-by-category/state + orders-by-payment-type (8 visuals)
- `[~]` **NEXT SESSION (reporting):** Page 2 (Delivery & Ops), Page 3 (RFM), filter out `(Blank)` categories, theme/formatting, move measures to a dedicated `_Measures` table, capture dashboard figures
- Tooling: **pbi-cli must be git `master` (3.11.2), not PyPI 1.0.6** (PyPI is frozen/ancient, no report layer); **Power BI Desktop must be current** (writes PBIR schema 2.7.0; the old Mar-2025 build couldn't open it). See ADR-018 + `[[pbi-cli-connection-workaround]]` memory.

## Phase 9 — Polish & Publish  `[ ]`

- `[ ]` Write the full `README.md` (architecture, setup, honest caveats — incl. static-data caveat on incrementals)
- `[ ]` Capture figures: ERD, dbt lineage DAG, dashboard screenshots → `figures/`
- `[ ]` Final review of `DECISIONS.md`
- `[ ]` Push to GitHub (only on explicit owner instruction)

---

## Open decisions (need an owner call — see `DECISIONS.md`)

- `[x]` **BI tool** — **resolved 2026-06-22:** Power BI + `.pbip` + `pbi-cli` (ADR-011).
- `[x]` **Q6 — null / orphan handling** — **confirmed 2026-06-17 (Phase 4):** Hybrid; reconciliation mismatches flagged-and-kept, only broken rows quarantined. (ADR-009 / ADR-015)

## Owner-driven steps (Claude generates + guides, cannot do directly)

- Snowflake web UI setup
- Power BI Desktop (if chosen)
- Accepting Kaggle dataset terms / downloading the CSVs
