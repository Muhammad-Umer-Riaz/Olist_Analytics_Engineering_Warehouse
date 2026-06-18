# DECISIONS.md — Architecture Decision Record (ADR) Log

A running log of architectural decisions, with rationale and rejected
alternatives. This is portfolio material: it shows *why*, not just *what*.

**Format for new entries:**

```
## ADR-NNN — <title>
**Status:** Accepted | Provisional | Open | Superseded
**Date:** YYYY-MM-DD
**Context:** <the problem / forces at play>
**Decision:** <what we chose>
**Rationale:** <why>
**Rejected alternatives:** <what we did not choose, and why>
```

The decisions below were seeded from `CONTEXT.md` at project kickoff
(2026-06-16). §2 = locked, §3 = provisional, §5 = open.

---

## ADR-001 — Project scope: focused analytics-engineering showcase
**Status:** Accepted · **Date:** 2026-06-16
**Context:** The portfolio already has a breadth project; this one needs depth.
**Decision:** Build a focused depth-over-breadth showcase on the modern data stack.
**Rationale:** Proves deep competence with dbt dimensional modeling, Snowflake,
orchestration, and trustworthy data handling — optimizing for correctness,
modeling judgment, and polish per piece.
**Rejected alternatives:** A sprawling multi-source platform (covered elsewhere).

## ADR-002 — Dataset: the 9-table Olist core
**Status:** Accepted · **Date:** 2026-06-16
**Context:** Olist ships a 9-table relational core plus a separate marketing funnel set.
**Decision:** Use the full nine-table release (52 columns); the marketing funnel set is out of scope.
**Rationale:** The 9-table core supplies rich sales + operations analytics without scope creep.
**Rejected alternatives:** Adding the funnel set — breadth we deliberately avoid.

## ADR-003 — dlt is the loader; Airflow only orchestrates
**Status:** Accepted · **Date:** 2026-06-16
**Context:** The reference repo (jv-mendes07/elt_data_warehouse_snowflake) used Airflow *as* the loader.
**Decision:** dlt performs extract-and-load; Airflow orchestrates dlt and is never the loader itself.
**Rationale:** Cleaner separation of concerns; corrects a weakness of the reference repo.
**Rejected alternatives:** Airflow-as-loader (the reference repo's approach).

## ADR-004 — Exactly one external source: an FX rate API
**Status:** Accepted · **Date:** 2026-06-16
**Context:** Olist prices lack a currency dimension (intrinsic defect).
**Decision:** Add exactly one external source — an FX rate API (BRL→USD/EUR).
Frankfurter (free, no key) is the default provider.
**Rationale:** Fixes a real data defect; keeps the project focused.
**Rejected alternatives:** Adding more sources (out of scope unless told otherwise).
_See ADR-008 for the provisional provider choice._

## ADR-005 — Hybrid loading strategy
**Status:** Accepted · **Date:** 2026-06-16
**Context:** Olist has 4 small reference tables and 4 large transactional tables.
**Decision:** Full-refresh the 4 reference tables (products, sellers, geolocation,
category_translation); incremental-merge the 4 transactional tables (orders,
order_items, payments, reviews) on a timestamp cursor. Seed incrementals in two
passes (through 2017, then 2018 as the "new" batch).
**Rationale:** Demonstrates both load patterns; matches table volatility.
**Honest caveat (must appear in README):** the source is a static historical dump;
the incremental setup demonstrates the *mechanism*, not response to genuinely arriving data.
**Rejected alternatives:** Full-refresh everything (hides the incremental skill).

## ADR-006 — Customer grain: two-layer resolution
**Status:** Accepted · **Date:** 2026-06-16
**Context:** `customer_id` is per-order; `customer_unique_id` is the real person (the key trap).
**Decision:** Facts keep `customer_id` as the join key; `dim_customers` carries
`customer_unique_id` as a linking attribute; a separate person-level
customer-summary model handles RFM / CLV.
**Rationale:** Keeps order-grain joins and person-grain analytics correct and separate.
**Rejected alternatives:** Collapsing to a single customer grain (breaks one or the other).

## ADR-007 — Two fact tables, not one
**Status:** Accepted · **Date:** 2026-06-16
**Context:** Revenue analysis and delivery analysis live at different grains.
**Decision:** `fct_order_items` at order-item grain (revenue, freight, product,
seller); `fct_orders` at order grain (delivery, payment, review).
**Rationale:** Forcing one grain breaks either revenue or delivery analysis.
**Rejected alternatives:** A single fact table.

## ADR-012 — Snowflake RBAC: two scoped service users, key-pair auth, least privilege
**Status:** Accepted · **Date:** 2026-06-16
**Context:** dlt (load) and dbt (transform) both need to connect to Snowflake. The
project's DNA is trustworthy, auditable data, so the warehouse access model must
enforce separation of concerns rather than share one all-powerful login.
**Decision:** Two functional roles + two `TYPE = SERVICE` users, one per tool:
- `OLIST_LOADER` → `OLIST_LOADER_SVC` (dlt): writes `RAW`; also `CREATE SCHEMA ON
  DATABASE OLIST` for dlt's `RAW_STAGING` merge scratch.
- `OLIST_TRANSFORMER` → `OLIST_TRANSFORMER_SVC` (dbt): reads `RAW` (incl. future
  tables/views via a future grant), writes `STAGING`/`INTERMEDIATE`/`MARTS`.
Ownership = **Option C**: `SYSADMIN` owns warehouse + database + schemas; custom
roles get privilege grants, not object ownership. DDL is **role-switched** so each
object is created by the role that should own it (`SYSADMIN` infra, `ACCOUNTADMIN`
resource monitor, `SECURITYADMIN` roles/users/grants). Auth is **key-pair** only
(SERVICE users cannot use passwords); unencrypted PKCS#8 private keys live in
`.keys/` (gitignored), public keys embedded in committed `snowflake/setup.sql`. A
`OLIST_WH_MONITOR` resource monitor caps `OLIST_WH` at 30 credits/month.
**Rationale:** Least privilege is provable, not aspirational — verified that
`OLIST_TRANSFORMER` is physically DENIED writing `RAW` (`verify_connection.py`).
Key-pair auth suits headless tools and avoids password sprawl. Role-switched DDL
models real Snowflake admin hygiene instead of doing everything as ACCOUNTADMIN.
**Rejected alternatives:** One shared user/role (no separation, no auditability);
password auth (weaker for service accounts); managed-access schemas (heavier than a
single future grant for this scope); custom roles owning objects (Option A/B —
muddier ownership than SYSADMIN-owns-infra).

## ADR-013 — Phase 2 dlt load: RAW stays 1:1; cursor where the data allows
**Status:** Accepted · **Date:** 2026-06-16
**Context:** ADR-005 mandates incremental-merge on "a timestamp cursor" for the 4
transactional tables, and `setup.sql` calls RAW a 1:1 landing zone. Inspecting the
real CSVs surfaced two conflicts: (a) `customers` (the 9th table) is in neither of
ADR-005's buckets; (b) `order_payments` has **no** date column and `order_items` has
only a shipping deadline — so neither can carry a real timestamp cursor without
injecting a derived column, which would break RAW's 1:1 fidelity.
**Decision:**
- `customers` → **full-refresh** (replace). So 5 full-refresh (products, sellers,
  geolocation, product_category_name_translation, customers) + 4 merge.
- **RAW stays strictly 1:1** — no derived columns. Therefore cursor-based incremental
  (`dlt.sources.incremental`) only on `orders` (`order_purchase_timestamp`) and
  `order_reviews` (`review_creation_date`). `order_items` / `order_payments` use
  **merge on composite PK, no cursor**; their two seed passes are split by
  parent-order-id membership.
- Merge keys (verified): orders `order_id`; order_items `(order_id, order_item_id)`;
  order_payments `(order_id, payment_sequential)`; order_reviews `(review_id, order_id)`
  — `review_id` alone is NOT unique (98,410 distinct vs 99,224 rows).
- Two-pass seed: pass 1 = through 2017, pass 2 = 2018 (`orders`/`reviews` split on their
  own cursor; `order_items`/`order_payments` on parent-order membership).
- Extraction = pandas `@dlt.resource` per table (`dtype=str` on zip prefixes to keep
  leading zeros); FX = Frankfurter long format (`rate_date, base, quote, rate`).
- New deps: `pandas`, and `pyarrow` via dlt's `parquet` extra (required to load
  pandas DataFrames). Self-contained dlt project under `dlt/`; key-pair auth via
  `private_key_path`.
**Rationale:** Honesty over a tidy-but-false uniform-cursor story. All 4 transactional
tables demonstrate idempotent merge; 2 of 4 demonstrate true cursor extraction —
documented as such (README caveat). Keeping RAW 1:1 protects provenance (the project's
DNA). Verified: every RAW table matches its parsed CSV count exactly after both passes.
**Rejected alternatives:** Injecting a derived `order_purchase_timestamp` into
order_items/payments for a uniform cursor (breaks RAW 1:1); forcing `customers` into the
incremental group (no cursor exists); the dlt filesystem-readers source (more abstraction,
weaker leading-zero control at this scale).

## ADR-014 — Phase 3 dbt staging: conventions, schema routing, geolocation collapse, typing boundary
**Status:** Accepted · **Date:** 2026-06-17
**Context:** First dbt layer (L3). Needed project conventions (naming, schema routing), a
connection model, and resolution of two hard cleaning problems (geolocation, category
translation) plus the load→transform typing boundary (RAW landed timestamps as VARCHAR).
Plan grilled (`/grill-me`) before build.
**Decision:**
- **Project/connection:** dbt Core, self-contained in `dbt/` (manual scaffold, not interactive
  `dbt init`). `profiles.yml` local + gitignored; key-pair auth as `OLIST_TRANSFORMER_SVC`
  (role `OLIST_TRANSFORMER`); run with `--profiles-dir .`.
- **Naming (dbt-Labs standard):** `models/staging/olist/stg_olist__<entity>.sql`,
  `_olist__sources.yml`, `_olist__models.yml`; source `olist_raw` over `OLIST.RAW` (10 tables).
- **Materialization/schema:** staging = **views** in `STAGING`. `generate_schema_name`
  overridden so `+schema` is used **verbatim** (avoids dbt's default `STAGING_STAGING`
  concatenation). No CREATE SCHEMA pre-grant — schemas pre-exist; dbt only creates missing ones.
- **Typing:** staging owns casting (RAW stays 1:1 text). **Hard `::timestamp_ntz`** casts
  (fail-fast); NTZ because Olist times are local Brazil, no offset. **Drop all `_dlt_*`**
  columns (lineage stays recoverable in untouched RAW).
- **Renames (light-touch):** fix `product_*_lenght`→`length`; keep zip-prefix names
  entity-specific; otherwise mirror RAW exactly.
- **Geolocation collapse** to 1 row/zip: `MEDIAN(lat/lng)` + **deterministic** modal
  city/state (`ROW_NUMBER` by count desc, then alphabetical) — not bare `MODE()`; keep
  coord-NULL zips. (Collapses 1,000,163 → 19,015.)
- **Category translation:** `stg_olist__products` stays strictly 1:1; translation is its own
  staging model; the PT→EN join is **deferred** to intermediate/marts — **refines `CONTEXT.md
  §4`**, which had pencilled the join into staging.
- **Dependency:** added `dbt_utils` (composite-PK tests now; surrogate keys later).
- **Tests (moderate):** PK unique + not_null on every model (composite keys via
  `dbt_utils.unique_combination_of_columns`), accepted_values on `order_status`,
  `payment_type`, `review_score`. Generic-test args nested under `arguments:` (dbt 1.11
  forward-compat). Heavy singular + cross-model tests deferred to Phase 6.
**Rationale:** Establishes recognizable dbt-Labs conventions; keeps RAW provenance intact while
staging owns correctness; reproducible geolocation; honest typing. **Verified:** 10 views built,
row counts reconcile to RAW exactly (geolocation collapsed as expected), 32/32 tests pass, no
deprecations.
**Rejected alternatives:** interactive `dbt init` (fights the existing `dbt/` layout); default
`STAGING_STAGING` schema; `try_cast` (silently hides bad data); enriching `stg_products` with
the English category (breaks 1:1 traceability); bare `MODE()` (non-deterministic ties);
hand-rolled composite-uniqueness tests (`dbt_utils` is the standard).

## ADR-015 — Phase 4 dbt intermediate: business logic, FX gap-fill, 3-state reconciliation, auditable rejects
**Status:** Accepted · **Date:** 2026-06-17
**Context:** First business-logic layer (L3 intermediate), feeding the Phase 5 star schema. Needed
reusable macros, grain collapses (payments→order, reviews→order), the deferred PT→EN category join,
the currency-defect fix (FX gap-fill + conversion), and resolution of Q6/ADR-009 (null vs orphan vs
broken). Plan grilled (`/grill-me`) and **every threshold set against the real CSV data** before build.
**Decision:**
- **Layer config:** intermediate = **views** in `INTERMEDIATE` (inspectable; table/incremental
  deferred to marts). Naming `int_olist__<entity>_<verb>`.
- **Macros (built where first used):** `delivery_days`, `is_late` (NULL when undelivered),
  `order_item_revenue` = price+freight, `brl_to` = round(amount×rate,2). **RFM bucketing + AOV
  deferred to Phase 5** (person/mart grain); **item-grain FX deferred to Phase 5** (reuses `brl_to`
  + `int_olist__fx_rates_filled`). Refines CONTEXT §4 — same deferral pattern as ADR-014.
- **FX gap-fill (`int_olist__fx_rates_filled`):** 1 row per (calendar_date, quote_currency) over the
  **full extent** least(min order, min rate) → greatest(max order, max rate); **LOCF forward-fill +
  leading back-fill**; `rate not_null` = fail-loud coverage guard. Convert on
  **`order_purchase_timestamp::date`**; rate is BRL→quote (USD = BRL×rate). **Lesson:** `dbt_utils.
  date_spine` is **end-EXCLUSIVE** — add 1 day to the end bound (caught a dropped final day, 2018-10-17).
- **Payments collapse (`int_olist__payments_pivoted`, 1/order):** total_payment_value, payment_count,
  max_installments, distinct_payment_types, is_multi_method; `primary_payment_type` = argmax sum(value)
  with **deterministic alphabetical tie-break**. `not_defined` kept.
- **Review dedup (`int_olist__reviews_deduped`, 1/order):** keep **latest** (creation date, then answer
  ts nulls-last, then review_id). order_id unique; review_id intentionally not unique.
- **Category (`int_olist__products_enriched`):** deferred PT→EN join via LEFT JOIN; untranslated = kept
  NULL (signal, 623 products), never a reject.
- **Reconciliation (Q6/ADR-009):** sum(payment_value) vs sum(price+freight) at order grain, tolerance
  **±0.01 BRL absolute**. **3-state** `is_payment_reconciled` (TRUE/FALSE/**NULL when not assessable**)
  + signed `payment_reconciliation_diff` on `int_olist__orders_enriched`. Discrepancies are **flagged
  and kept** (264 overpaid = legitimate financing, 39 underpaid; audit via `where not
  is_payment_reconciled`) — **not** quarantined.
- **Rejects (`int_olist__rejects`):** consolidated quarantine of genuinely-broken/excluded rows only —
  3 orphan guards (items/payments/reviews) + `order_no_payment`. `rejected_at` from `run_started_at`.
**Verified against data:** orphans = **0** across all three child tables (Olist FK-clean — guards kept
as standing gates for incremental loads); **1** reject (`order_no_payment`, a delivered order); **775**
payment-no-item orders kept as canceled/unavailable signal (reconciliation NULL); FX spine 776 dates ×
2 = 1,552 rows, **0 null rates**, covers 2016-09-02 → 2018-10-17; orders_enriched 99,441 rows (no
fan-out): **98,362 reconciled / 303 mismatched / 776 not-assessable**; **24/24 intermediate tests pass**.
**Note (decimal vs float):** mismatch count is **303**, not the 378 from the pandas pre-check — exact
`number(10,2)` arithmetic correctly reconciles **273 exactly-one-cent** orders that float noise inflated.
**Rejected alternatives:** quarantining reconciliation mismatches (silent-drops legitimate financing
revenue); a 2-state reconciliation flag (miscasts canceled orders as mismatches); interpolated/nearest
FX (invents or leaks rates); array or most-frequent `payment_type` (loses value-weighting / re-opens
ties); dropping the 0-row orphan guards (they protect future incremental loads).

## ADR-016 — Phase 5 dbt marts: star schema, hybrid keys, conformed geography, role-playing dates
**Status:** Accepted · **Date:** 2026-06-18
**Context:** The BI-facing star schema (L3 marts), built on the Phase 4 intermediate
layer. Locked anchors: two facts not one (ADR-007), two-layer customer grain
(ADR-006). Owner's learning goal: justify each view-vs-table call + learn surrogate
keys / star schema. Plan grilled (`/grill-me`); decisions D1–D8 below.
**Decision:**
- **D1 Keying = HYBRID.** Keep opaque natural keys (`customer_id`, `product_id`,
  `seller_id`, `order_id`) as entity-dim join keys — already unique/stable, no SCD.
  Surrogate only where it earns it: `date_key` (YYYYMMDD int) for `dim_dates`; zip
  prefix as natural key for `dim_geography`. (Don't cargo-cult a hash over a hash.)
- **D2 Geography = CONFORMED `dim_geography`** keyed on zip; holds city/state/lat/lng
  once; `dim_customers`/`dim_sellers` carry zip as FK. Accepts a mild snowflake.
- **D3 Materialization = ALL marts `table`, no incremental.** BI reads them
  repeatedly; upstream is all views (a mart-view recomputes the whole DAG/query).
  Incremental skipped (static source; already demonstrated at the dlt load layer).
- **D4 `dim_dates` = full calendar years 2016-01-01→2018-12-31** (`date_spine`,
  end-exclusive → +1 day) + **BR national-holiday seed** `seeds/br_holidays.csv`
  (incl. Easter-derived Carnival/Good Friday/Corpus Christi). ISO weekday/week
  (`dayofweekiso`/`weekiso`) so the dim is session-independent. Static seed ≠ live
  source (ADR-004 holds). Seed lands in STAGING (transformer can't write RAW/create
  schemas, ADR-012).
- **D5 Role-playing dates = 3 roles + raw timestamps.** `fct_orders` carries
  purchase / delivered-customer (null when undelivered = signal) / estimated date
  keys; `fct_order_items` carries purchase date key. Approved/carrier = raw ts only.
- **D6 Item-grain FX = revenue only → USD+EUR.** `fct_order_items` keeps
  price/freight/revenue BRL, adds `revenue_usd|eur` = `brl_to(revenue, rate)` on the
  order's purchase date (same anchor as `fct_orders` → the two facts reconcile).
  Inner-join items→orders enforces "no orphan fact keys" (orphans documented in
  `int_olist__rejects`).
- **D7 `customer_summary` monetary = item revenue (price+freight).** Person grain
  (`customer_unique_id`). Merchant-received money (excludes card-issuer financing —
  the 264 overpaid orders). Recency/Monetary via NTILE(5) (deterministic tie-break);
  **Frequency scored BY VALUE** (`least(frequency,5)`) — NTILE on frequency is wrong
  here (Olist is ~97% one-time buyers; a quintile forces ~2/5 of single-purchase
  customers into f>=4 and mislabels them "Loyal"). Recency vs dataset max order date
  (static); AOV + **historical** CLV (=monetary, labeled honestly). New macros
  `aov`, `rfm_bucket`.
- **D8 City/state = native on dims + zip FK for coordinates.** `dim_customers`/
  `dim_sellers` keep their source city/state (full coverage), carry zip FK to
  `dim_geography` for lat/lng. Refines D2 so city/state has no coverage gap.
**Verified against data:** 8 models built as tables, **46/46 marts tests pass**
(incl. all fact-FK `relationships` → the star joins). No fan-out: fct_orders =
99,441, fct_order_items = 112,650 (= stg order_items), customer_summary = 96,096
(= distinct `customer_unique_id`). dim_dates = 1,096 days (2016 leap).
**Honest caveats:** Olist is ~97% one-time buyers, so Frequency is scored by value
(not NTILE — a quintile mislabels one-time buyers as "Loyal"; caught when "Loyal"
came out as the largest segment on the first build, then fixed). Segmentation
correctly leans on Recency/Monetary. CLV is historical,
not predictive. `zip→dim_geography` is NOT relationship-tested as an error (known
coverage gap; revisit as warn-severity in Phase 6).
**Rejected alternatives:** full surrogate keys on every dim (hashing already-unique
hashes, no SCD/decoupling benefit); natural keys only (skips the surrogate concept);
denormalizing geography into each dim (duplicates city/state, drops the conformed
dim); mart-as-view (recomputes the DAG per BI query); incremental facts (academic on
a static source); converting price/freight separately (cent-rounding drift vs the
BRL revenue definition); payment-value monetary (inflated by financing that never
reaches the merchant).

---

## Provisional decisions (sensible defaults; owner may revisit)

## ADR-008 — FX provider: Frankfurter (default)
**Status:** Provisional · **Date:** 2026-06-16
**Decision:** Use Frankfurter API by default; ECB or another free source is
acceptable if it loads more cleanly. **Confirm if switching.**

## ADR-009 — Null / orphan handling (Q6)
**Status:** Accepted — **confirmed with owner 2026-06-17 (Phase 4); see ADR-015 for implementation** · **Date:** 2026-06-16
**Decision:** Hybrid. Keep operationally meaningful gaps as signal (undelivered orders,
no-review orders = legitimate left-join nulls; conditional tests). **Quarantine** genuinely
broken rows (orphaned keys; structurally missing payment) into a documented **rejects table**
with a reason column — never silently drop them.
**Refinement confirmed in Phase 4 (ADR-015):** payment-reconciliation *mismatches* are **flagged
and kept** (3-state `is_payment_reconciled`), **not** quarantined — the data showed most are
legitimate credit-card financing fees, so quarantining them would silent-drop real revenue. The
rejects table holds only genuinely-broken/excluded rows (orphans = 0; `order_no_payment` = 1).
**Validated in Phase 6 (singular tests):** the conditional-null rule (status `delivered` ⇒
delivery date present) is asserted as a singular test at **warn** severity — it surfaces 8 known
Olist source anomalies (orders marked delivered with no customer-delivery timestamp; 7 of 8 still
reached the carrier, so it's a data-capture gap, not a fake delivery). Kept in the fact and made
visible, not quarantined — consistent with the hybrid policy above. README caveat to follow.
**Rationale:** Echoes the owner's "Provenance" audit DNA (every value traceable).

## ADR-010 — Distance enrichment (buyer↔seller)
**Status:** Provisional (nice-to-have) · **Date:** 2026-06-16
**Decision:** Compute buyer↔seller distance from existing lat/lng **only if time
allows** after the core is solid. Not a starting assumption.

---

## Open decisions (pending owner)

## ADR-011 — BI tool
**Status:** Open — pending owner · **Date:** 2026-06-16
**Context:** Last layer (L6); reads MARTS.
**Options:**
- **Power BI** (recommended) — recognized by target data/ops-analyst roles, native
  Snowflake connector, reuses existing strength.
- **Evidence.dev** — BI-as-code in SQL, lives in the repo, no hosting, reads very
  analytics-engineer, but less recruiter-recognized.
**Decision:** _Pending._ Build L0–L5 fully first; BI is last.
