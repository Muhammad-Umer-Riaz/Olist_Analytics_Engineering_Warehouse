# .keys/

Local-only store for the Snowflake **service-user key-pairs**. The contents of this
folder (everything except this README) are **gitignored and never committed** — they
are credentials.

## What lives here (on a configured machine)

| File | What it is |
|------|-----------|
| `olist_loader.p8` | Unencrypted PKCS#8 **private** key for `OLIST_LOADER_SVC` (dlt) |
| `olist_loader.pub` | Base64 SPKI **public** key (registered in Snowflake via `setup.sql`) |
| `olist_transformer.p8` | Unencrypted PKCS#8 **private** key for `OLIST_TRANSFORMER_SVC` (dbt) |
| `olist_transformer.pub` | Base64 SPKI **public** key (registered in Snowflake via `setup.sql`) |

The private `.p8` files are the actual credentials — anyone holding one can connect as
that Snowflake service user. They are kept unencrypted for local convenience; do not
copy them outside this machine or into any synced/cloud folder.

## Regenerating / rotating keys

The key-pairs are standard 2048-bit RSA in PKCS#8. To rotate, generate a new pair,
update the matching `RSA_PUBLIC_KEY` in `snowflake/setup.sql`, and re-run that statement
in Snowflake (`ALTER USER <svc> SET RSA_PUBLIC_KEY='...'`). Public keys are not secret
and are intentionally embedded in `setup.sql`.
