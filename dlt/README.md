# `dlt/` — Extract & Load (L1)

The **dlt** pipeline that lands the source data into Snowflake `RAW`. dlt is the loader;
Airflow only orchestrates it ([ADR-003](../DECISIONS.md)).

## Contents

| File | What it does |
|------|--------------|
| `load_olist.py` | The whole pipeline — extracts the 9 Olist CSVs from `data/raw/` and the Frankfurter FX rates, and loads them to `OLIST.RAW` on Snowflake. |
| `.dlt/` | dlt project config. `config.toml` is committed; `secrets.toml` (Snowflake key-pair creds) is **gitignored**. |

## Load strategy ([ADR-005](../DECISIONS.md), [ADR-013](../DECISIONS.md))

- **Hybrid:** the 5 small reference/dimension tables are **full-refreshed**; the 4 large
  transactional tables are **merge-loaded** for idempotency.
- **Cursor where the data allows:** only `orders` and `order_reviews` carry a real timestamp,
  so they use true `dlt.sources.incremental` cursor extraction; `order_items` and
  `order_payments` have no date column and **merge on their composite primary key** instead.
- **`RAW` stays strictly 1:1** with the source — no derived columns — to protect provenance.
- Incrementals are seeded in **two passes** (through 2017, then 2018 as the "new" batch) to
  exercise the merge path on an otherwise static dump.

## Run it

1. Put the Snowflake **loader** key-pair creds in `.dlt/secrets.toml` (private key at
   `../.keys/olist_loader.p8`, gitignored — see [`../.keys/README.md`](../.keys/README.md)).
2. `python load_olist.py` — runs both seed passes and the FX fetch, then verifies RAW row
   counts against the source CSVs.
