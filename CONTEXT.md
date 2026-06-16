# CONTEXT.md — Olist Analytics Engineering Warehouse

> Handoff for a fresh Claude Code session. Read this top to bottom before writing any code.
> This is a spec-driven build. Write a short plan before each module, record decisions as you go.

---

## 1. What are we building, and why?

A focused **analytics-engineering showcase**: an ELT data warehouse on the Olist Brazilian
e-commerce dataset, built with **dlt + Snowflake + dbt + Airflow**, surfaced through a BI layer.

The point of the project is **depth on the modern data stack**, not breadth. It exists to add a
tool-specific analytics-engineering piece to the owner's portfolio — proving deep competence with
dbt dimensional modeling, Snowflake, orchestration, and trustworthy data handling. It deliberately
does NOT try to be a sprawling multi-source platform (a separate portfolio project already covers
breadth). Optimize every decision for **correctness, modeling judgment, and polish per piece**.

The owner is an Industrial Engineer pivoting toward data/analytics roles (operations analyst,
data analyst, analytics engineer). His methodology is spec-driven and ADR-heavy. His portfolio
identity centers on **trustworthy, auditable data** (see his "Provenance" project: human review
gate, audit log, every value traceable). Honor that DNA here.

**Reference repo for the spine (NOT to copy):** jv-mendes07/elt_data_warehouse_snowflake.
We deliberately improve on two of its weaknesses: (a) it used Airflow AS the loader — we don't;
(b) its transformation layer was thin — ours is not.

---

## 2. What's locked? (decided, do not relitigate)

These were resolved through a structured interview. Treat as settled.

- **Project type:** Focused analytics-engineering showcase (depth over breadth).
- **Domain:** E-commerce sales + operations analytics on real Olist data.
- **Dataset:** Full **nine-table** Olist release + the separate **marketing funnel** set is NOT
  in scope (we chose the 9-table core, not the funnel). 52 columns total across 9 files.
- **Stack (non-negotiable anchors):** dlt → Snowflake → dbt Core → Airflow. BI tool: SEE SECTION 5.
- **Loader:** **dlt** does extract-and-load. Airflow ORCHESTRATES dlt; it is never the loader itself.
- **External sources:** Exactly **ONE** — an **FX rate API** (BRL→USD/EUR) to fix the intrinsic
  missing-currency defect in Olist prices. Frankfurter API (free, no key) is the default choice.
  Do NOT add more sources unless explicitly told to later.
- **Loading strategy:** **Hybrid.** Full-refresh the 4 small reference tables
  (products, sellers, geolocation, category_translation); **incremental-merge** the 4 large
  transactional tables (orders, order_items, payments, reviews) on a timestamp cursor.
  Seed incrementals in two passes (e.g. through 2017, then 2018 as the "new" batch).
  README must state honestly that the source is a static historical dump and the incremental
  setup demonstrates the mechanism, not response to genuinely arriving data.
- **Customer grain (the key trap):** customer_id is per-order; customer_unique_id is the real person.
  Resolution = **two-layer**: fct keeps `customer_id` as join key, `dim_customers` carries
  `customer_unique_id` as the linking attribute, and a separate person-level customer-summary
  model handles RFM / CLV. Keep order-grain joins and person-grain analytics separate.
- **Two fact tables (not one):**
  - `fct_order_items` at **order-item grain** — revenue, freight, product, seller analysis.
  - `fct_orders` at **order grain** — delivery performance, payment, review analysis.
  Document WHY they're split (forcing one grain breaks either revenue or delivery).

---

## 3. What's provisional? (sensible default set; owner may revisit)

- **Null / orphan handling (Q6 — owner deferred, default set to avoid the worst auto-choice):**
  Default = **Hybrid (Option C)**. Keep operationally meaningful gaps as signal (undelivered orders,
  orders with no review = legitimate left-join nulls; conditional tests, e.g. delivery date
  not_null only where status='delivered'). **Quarantine** genuinely broken rows (unreconcilable
  payments, orphaned keys) into a documented **rejects table** with a reason column — never silently
  drop them. This echoes the owner's Provenance audit DNA. **FLAG THIS TO THE OWNER EARLY** in the
  build and confirm before finalizing the test suite — he explicitly deferred this decision.
- **FX provider:** Frankfurter is the default; ECB or another free source is acceptable if it loads
  more cleanly. Confirm if you switch.
- **Distance enrichment (buyer↔seller, computed from existing lat/lng):** nice-to-have ONLY, add
  only if time allows after the core is solid. Not a starting assumption.

---

## 4. The architecture (layer / tool / why)

```
L0 SOURCE        9 Olist CSVs (Kaggle)            real, messy, relational
L1 LOAD (EL)     dlt -> Snowflake RAW             Airflow orchestrates dlt (not the loader)
                 + FX API (Frankfurter) -> RAW    one external source, fixes currency defect
L2 WAREHOUSE     Snowflake                         RAW -> STAGING -> INTERMEDIATE -> MARTS
                 (180-day DataCamp account)
L3 TRANSFORM     dbt Core
   staging/      stg_* 1:1 cleaned views          cast, rename, ONE hard problem each;
                                                   collapse geolocation to 1 row/zip;
                                                   join category translation -> English
   intermediate/ business logic + macros          collapse payment installments -> 1/order;
                                                   dedup multi-review orders; delivery-days /
                                                   late flags; FX conversion; rejects routing
   marts/        star schema (2 facts + dims)      see Section 2 for fact grains
                 dims: dim_customers, dim_products, dim_sellers, dim_dates, dim_geography
                 + customer_summary (person-grain RFM/CLV)
L4 TEST + DOCS   dbt tests + dbt docs              generic (unique, not_null, relationships,
                                                   accepted_values: order_status, payment_type,
                                                   review_score 1-5) + singular (no negative
                                                   price/freight, delivered>=purchase, payment
                                                   reconciles, no orphan fact keys) + conditional
                                                   null rules per Section 3
L5 ORCHESTRATE   Airflow (Astro CLI local)        DAG: dlt_load_olist (parallel tasks) +
                                                   fetch_fx  ->  dbt run  ->  dbt test  ->  dbt docs
                                                   real dependency graph, retries, failure branch
L6 BI            SEE SECTION 5                      reads MARTS
```

**Macros to build (reusable business logic — this is where depth shows):**
`delivery_days()`, `is_late()`, revenue/AOV logic, RFM bucketing, BRL→target FX conversion.

**Grain facts to respect (the real work):**
- orders = 1 row/order; order_items = 1 row/item (finest sales grain)
- payments = multiple rows/order (installments/splits) — collapse in intermediate
- reviews = not every order has one; a few have two — dedup in intermediate
- geolocation = many rows/zip, dirty city spellings — collapse in staging
- categories arrive in Portuguese — translate in staging

---

## 5. What's the immediate next step + the one open decision?

**One decision still open before the build is fully specified: the BI tool.**
- **Power BI** — recommended. Recognized by the data/ops-analyst roles he's targeting, native
  Snowflake connector, reuses his existing strength.
- **Evidence.dev** — BI-as-code in SQL, lives in the repo, no hosting, reads very
  analytics-engineer, but less recruiter-recognized.
Owner to pick. Until then, build L0–L5 fully; BI is the last layer.

**Immediate next steps, in order:**
1. Confirm the owner has the 9 CSVs downloaded from Kaggle and where they live.
2. Scaffold the repo (dlt project, dbt project, Airflow/Astro, .gitignore, README skeleton).
3. Set up Snowflake objects (warehouse, database, RAW/STAGING/INTERMEDIATE/MARTS schemas, role, user)
   — owner drives the Snowflake UI/SQL; you generate the SQL and talk him through it.
4. Build L1: dlt pipeline (hybrid load) + FX fetch. Get RAW landing correctly.
5. Build L3 staging, then intermediate (FLAG the Q6 null/rejects decision to owner here), then marts.
6. Build L4 tests + docs. 7. Wire L5 Airflow DAG. 8. BI once chosen.

**Working agreement:** spec-driven. Short written plan before each module. Record architectural
decisions with rationale + rejected alternatives (ADR style) as you go — the owner values this and
it becomes portfolio material. Honest voice throughout: no overclaiming, document what the project
does and does not do (e.g. the static-data caveat on incremental loading).

**Things Claude Code cannot do for him (he drives, you generate + guide):** Snowflake web UI setup,
Power BI Desktop, accepting Kaggle dataset terms.
