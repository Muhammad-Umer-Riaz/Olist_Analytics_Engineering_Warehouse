# CLAUDE.md

## What this project is

An **analytics-engineering showcase**: an ELT data warehouse on the Olist
Brazilian e-commerce dataset, built with **dlt → Snowflake → dbt Core → Airflow**,
surfaced through a BI layer. Depth over breadth — the goal is deep, demonstrable
competence with the modern data stack, with trustworthy, auditable data throughout.

**Domain:** E-commerce sales + operations analytics
**Owner:** Muhammad Umer Riaz — muhammad.umer2149@gmail.com

## How to orient yourself before doing anything

Read these files in order:
1. `CONTEXT.md` — the full project spec: what we're building, what's locked, what's
   provisional, and the architecture. This is the design source of truth.
2. `DECISIONS.md` — every major decision as an ADR (rationale + rejected
   alternatives). Check here before proposing any architectural change.
3. `PROGRESS.md` — the phase-by-phase build tracker. What's done, in progress, not started.
4. `plans/` — the per-phase plans (most recent = current focus).

## Teaching mode — read this first, it shapes every response

**This is the owner's first time using dbt, Snowflake, dlt, and Airflow.** He is a
strong analyst (industrial engineering, SQL, business framing) but new to this
tooling. Treat every step as a guided learning experience:

- **Explain before you run.** Before executing a command or writing a config, say
  in plain language what it does and why, and what the owner should expect to see.
- **Don't assume tool familiarity.** Spell out CLI commands, file locations, and UI
  steps. Where the owner must act in a web UI (Snowflake, Kaggle, Power BI), give
  click-by-click guidance — you generate, he drives.
- **Teach the concept, not just the fix.** When something breaks, explain the
  underlying concept so the knowledge sticks.
- **Connect to the business case.** The owner thinks in operations/procurement
  terms; tie modeling choices back to the analytics they enable.
- **Pace it.** One phase / one logical step at a time. Don't dump three modules at once.

## User preferences — follow these strictly

**Ask questions before acting on decisions that have downstream effects.** This
includes: schema/model changes, new dbt models or sources, folder-structure
changes, naming conventions, new dependencies, load strategy, and anything
architectural. A short question costs nothing; a wrong assumption wastes a session.

**Always ask before:**
- Adding a new data source (only the one FX API is in scope — see `DECISIONS.md` ADR-004)
- Changing the load strategy, fact grains, or customer-grain resolution
- New Python dependencies
- Git commits or pushes — always ask first, never assume
- Adding or removing files from the repo

**Be direct about mistakes.** If you made an assumption you should have asked
about, say so plainly. Directness over deflection.

**Don't over-summarize.** Explanation *during* the work is wanted (teaching mode);
a long recap of what was just done at the end is not. End when the work is done.

## Planning

- Save all plans to `plans/`
- Naming convention: `{sequence}.{plan-name}.md` (e.g. `1.snowflake-setup.md`,
  `2.dlt-load.md`, `3.dbt-staging.md`)
- Write a short plan before each Phase in `PROGRESS.md` begins
- Plans must be detailed enough to execute without ambiguity, and include at least
  one validation step per task
- Assess complexity before starting: ✅ Simple (single-pass) · ⚠️ Medium (may need
  iteration) · 🔴 Complex (break into sub-plans first)

## Development flow

1. **Plan** — write a short plan for the phase, save to `plans/`
2. **Explain** — walk the owner through what's about to happen (teaching mode)
3. **Build** — execute the plan, one step at a time
4. **Validate** — test against the plan's checklist; verify in Snowflake/dbt/Airflow
5. **Update** — mark steps in `PROGRESS.md`; record durable decisions in `DECISIONS.md`

## Git

- Commit messages must not contain any reference to Claude Code, Claude, or AI
  authorship — no `Co-Authored-By: Claude`, no `Generated with Claude Code`, no
  similar attribution of any kind
- Never commit without explicit instruction from the owner
- Never push to GitHub without explicit instruction from the owner
- Never create new files unless explicitly asked

## What NOT to do

- Do not relitigate the locked decisions in `CONTEXT.md §2` / `DECISIONS.md`
  (project scope, 9-table dataset, hybrid load, two facts, two-layer customer grain)
- Do not add data sources beyond the single FX API
- Do not make Airflow the loader — dlt loads; Airflow only orchestrates (ADR-003)
- Do not silently drop bad rows — quarantine them into a documented rejects table
  (pending Q6 confirmation, ADR-009). Trustworthy, auditable data is the project's DNA
- Do not overclaim in docs — honestly note what the project does and doesn't do
  (e.g. the static-data caveat on incremental loading)
