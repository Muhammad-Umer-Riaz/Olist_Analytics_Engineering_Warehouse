#!/usr/bin/env python
"""Verify a Snowflake service-user key-pair login and its RBAC scope.

No secrets are hard-coded. The account identifier comes from the SNOWFLAKE_ACCOUNT
environment variable (or --account); the private key is referenced by file path.

Usage (PowerShell, from the repo root with the venv active):

    $env:SNOWFLAKE_ACCOUNT = "ORGNAME-ACCOUNTNAME"

    # Loader (dlt) — should connect and be able to WRITE to RAW:
    python snowflake/verify_connection.py `
        --user OLIST_LOADER_SVC --key .keys/olist_loader.p8 `
        --role OLIST_LOADER --warehouse OLIST_WH --database OLIST `
        --write-schema RAW

    # Transformer (dbt) — writes STAGING, but is DENIED writing RAW:
    python snowflake/verify_connection.py `
        --user OLIST_TRANSFORMER_SVC --key .keys/olist_transformer.p8 `
        --role OLIST_TRANSFORMER --warehouse OLIST_WH --database OLIST `
        --write-schema STAGING --deny-schema RAW

Exit code 0 = all checks passed; non-zero = a check failed.
"""
import argparse
import os
import sys

import snowflake.connector
from snowflake.connector.errors import ProgrammingError


def main() -> int:
    p = argparse.ArgumentParser(description="Verify a Snowflake key-pair login + RBAC scope.")
    p.add_argument("--account", default=os.environ.get("SNOWFLAKE_ACCOUNT"),
                   help="Account identifier (default: $SNOWFLAKE_ACCOUNT).")
    p.add_argument("--user", required=True)
    p.add_argument("--key", required=True,
                   help="Path to the unencrypted PKCS#8 private key (.p8).")
    p.add_argument("--role")
    p.add_argument("--warehouse")
    p.add_argument("--database")
    p.add_argument("--write-schema",
                   help="Schema where creating a temp table should SUCCEED.")
    p.add_argument("--deny-schema",
                   help="Schema where creating a table should be DENIED (least-privilege check).")
    args = p.parse_args()

    if not args.account:
        print("ERROR: set SNOWFLAKE_ACCOUNT or pass --account", file=sys.stderr)
        return 2
    if not os.path.exists(args.key):
        print(f"ERROR: key file not found: {args.key}", file=sys.stderr)
        return 2

    conn_args = {"account": args.account, "user": args.user, "private_key_file": args.key}
    for field in ("role", "warehouse", "database"):
        value = getattr(args, field)
        if value:
            conn_args[field] = value

    print(f"Connecting as {args.user} to {args.account} ...")
    ctx = snowflake.connector.connect(**conn_args)
    rc = 0
    try:
        cur = ctx.cursor()
        cur.execute(
            "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(), "
            "CURRENT_DATABASE(), CURRENT_VERSION()"
        )
        user, role, wh, db, ver = cur.fetchone()
        print(f"  user={user}  role={role}  warehouse={wh}  database={db}")
        print(f"  Snowflake version {ver}")
        print("  [PASS] key-pair authentication")

        if args.write_schema:
            tbl = f"{args.database}.{args.write_schema}._VERIFY_TMP"
            try:
                cur.execute(f"CREATE OR REPLACE TABLE {tbl} (x INT)")
                cur.execute(f"DROP TABLE {tbl}")
                print(f"  [PASS] write to {args.write_schema} (create + drop temp table)")
            except ProgrammingError as e:
                print(f"  [FAIL] expected write to {args.write_schema}, but: {e.msg}")
                rc = 1

        if args.deny_schema:
            tbl = f"{args.database}.{args.deny_schema}._VERIFY_TMP"
            try:
                cur.execute(f"CREATE OR REPLACE TABLE {tbl} (x INT)")
                cur.execute(f"DROP TABLE {tbl}")
                print(f"  [FAIL] write to {args.deny_schema} SUCCEEDED but should be denied")
                rc = 1
            except ProgrammingError:
                print(f"  [PASS] write to {args.deny_schema} correctly DENIED (least privilege)")
    finally:
        ctx.close()

    print("RESULT:", "OK" if rc == 0 else "FAILURES")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
