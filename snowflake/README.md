# `snowflake/` — Warehouse Setup & Access (L2)

The SQL and checks that stand up the Snowflake warehouse and enforce its **least-privilege**
access model ([ADR-012](../DECISIONS.md)).

## Contents

| File | What it does |
|------|--------------|
| `setup.sql` | Idempotent DDL: creates the warehouse, the `OLIST` database, the four schemas (`RAW`·`STAGING`·`INTERMEDIATE`·`MARTS`), the functional roles, the service users, grants, and a credit resource monitor. |
| `verify_connection.py` | Proves the access model — confirms the transformer user is physically **denied** writing `RAW` (least privilege is verified, not assumed). |

## Access model ([ADR-012](../DECISIONS.md))

- **Two `TYPE = SERVICE` users, one per tool:** a **loader** (writes `RAW`) and a
  **transformer** (reads `RAW`, writes `STAGING`/`INTERMEDIATE`/`MARTS`, *cannot* write `RAW`).
  A third read-only **reporter** role (scoped to `MARTS`) backs the Power BI connection.
- **Key-pair auth** for the service users (private keys live in `../.keys/`, gitignored;
  public keys are embedded in `setup.sql` — they are not secret).
- **Role-switched DDL:** each object is created by the role that should own it (`SYSADMIN`
  for infra, `SECURITYADMIN` for roles/users/grants) rather than everything as `ACCOUNTADMIN`.
- A **resource monitor** caps the warehouse at 30 credits/month.

## Run it

1. Generate the service-user key-pairs and register their public keys (see
   [`../.keys/README.md`](../.keys/README.md)).
2. Run `setup.sql` in Snowflake as `ACCOUNTADMIN`.
3. `python verify_connection.py` to confirm both users connect and least privilege holds.
