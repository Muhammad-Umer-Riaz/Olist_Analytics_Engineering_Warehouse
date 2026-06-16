# PROGRESS.md

Living build tracker for the Olist ELT Warehouse. Update as each module lands.
Spec-driven workflow: a short plan goes in [`plans/`](./plans) before each module.

_Last updated: 2026-06-16_

---

## Module status (L0 → L6)

| Layer | Module | Tool | Status |
|-------|--------|------|--------|
| L0 | Source — 9 Olist CSVs downloaded & placed in `data/raw/` | Kaggle | ☐ Not started |
| —  | Repo skeleton (folders, .gitignore, tracking files) | — | ☑ Done |
| L1 | Load (EL) — dlt pipeline (hybrid) + FX fetch → RAW | dlt | ☐ Not started |
| L2 | Warehouse — wh / db / schemas / role / user setup | Snowflake | ☐ Not started |
| L3 | Transform — staging → intermediate → marts | dbt Core | ☐ Not started |
| L4 | Test + Docs — generic / singular / conditional tests | dbt | ☐ Not started |
| L5 | Orchestrate — Airflow DAG (Astro CLI local) | Airflow | ☐ Not started |
| L6 | BI — dashboards reading MARTS | TBD | ☐ Not started |

Legend: Convention: [ ] = Not started | [-] = In progress | [x] = Completed | [~] = Dropped

---

## Immediate next steps (from CONTEXT.md §5)

1. Confirm the 9 Olist CSVs are downloaded from Kaggle and placed in `data/raw/`.
2. ~~Scaffold the repo (folders, .gitignore, README skeleton, tracking files).~~ ☑
3. Set up Snowflake objects (warehouse, database, RAW/STAGING/INTERMEDIATE/MARTS
   schemas, role, user) — owner drives the Snowflake UI/SQL; Claude generates SQL + guides.
4. Build L1: dlt pipeline (hybrid load) + FX fetch. Get RAW landing correctly.
5. Build L3 staging → intermediate (**flag the Q6 null/rejects decision here**) → marts.
6. Build L4 tests + docs.
7. Wire L5 Airflow DAG.
8. Build L6 BI once the tool is chosen.

---

## Open items (need an owner decision)

- **BI tool** — Power BI (recommended) vs Evidence.dev. Decide before L6. See `DECISIONS.md`.
- **Q6 — null / orphan handling** — provisional default is Hybrid (keep meaningful
  gaps as signal; quarantine broken rows into a documented rejects table).
  **Confirm before finalizing the L4 test suite.** See `DECISIONS.md`.

---

## Owner-driven steps (Claude generates + guides, cannot do directly)

- Snowflake web UI setup.
- Power BI Desktop (if chosen).
- Accepting Kaggle dataset terms / downloading the CSVs.
