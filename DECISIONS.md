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

---

## Provisional decisions (sensible defaults; owner may revisit)

## ADR-008 — FX provider: Frankfurter (default)
**Status:** Provisional · **Date:** 2026-06-16
**Decision:** Use Frankfurter API by default; ECB or another free source is
acceptable if it loads more cleanly. **Confirm if switching.**

## ADR-009 — Null / orphan handling (Q6)
**Status:** Provisional — **owner deferred; confirm before finalizing L4 tests** · **Date:** 2026-06-16
**Decision (default):** Hybrid. Keep operationally meaningful gaps as signal
(undelivered orders, no-review orders = legitimate left-join nulls; conditional
tests, e.g. delivery date not_null only where status='delivered'). **Quarantine**
genuinely broken rows (unreconcilable payments, orphaned keys) into a documented
**rejects table** with a reason column — never silently drop them.
**Rationale:** Echoes the owner's "Provenance" audit DNA (every value traceable).
**Action:** Flag to owner early in the build (at the intermediate layer) and confirm.

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
