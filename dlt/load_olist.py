"""Phase 2 — dlt load pipeline: 9 Olist CSVs + FX rates -> Snowflake OLIST.RAW.

Run with the venv active, FROM THE dlt/ DIRECTORY (so dlt finds ./.dlt/secrets.toml):

    cd dlt
    python load_olist.py 1     # pass 1: full-refresh tables + order history through 2017 + FX
    python load_olist.py 2     # pass 2: the 2018 batch (incremental)

Design (see plans/2.dlt-load.md):
  * RAW is a faithful 1:1 landing zone — no derived columns are injected.
  * orders + order_reviews carry real timestamps -> dlt.sources.incremental cursors.
  * order_items + order_payments have no usable created-at -> merge on primary key,
    with the two seed passes split by parent-order membership.
  * Honest caveat: the source is a static dump; the two-pass run demonstrates the
    incremental *mechanism*, not response to genuinely arriving data.
"""
from __future__ import annotations

import sys
from pathlib import Path

import dlt
import pandas as pd
import requests

# Repo-root/data/raw, resolved from this file's location (independent of cwd).
DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"

# Pass 1 loads order history strictly before this date; pass 2 is everything from it on.
PASS1_CUTOFF = "2018-01-01"

# FX window = the verified order-purchase span; one external source (Frankfurter).
FX_START, FX_END = "2016-09-04", "2018-10-17"
FX_BASE, FX_QUOTES = "BRL", ["USD", "EUR"]


def _records(df: pd.DataFrame) -> list[dict]:
    """DataFrame -> list of dicts, converting pandas NaN to None (Snowflake NULL)."""
    return df.astype(object).where(df.notnull(), None).to_dict("records")


# ---------------------------------------------------------------------------
# Full-refresh reference / dimension tables  (write_disposition="replace").
# Yielded as DataFrames so dlt's arrow path handles types + nulls efficiently.
# zip-code prefixes are forced to str to preserve leading zeros (e.g. 01001).
# ---------------------------------------------------------------------------
@dlt.resource(name="customers", write_disposition="replace")
def customers():
    yield pd.read_csv(DATA_DIR / "olist_customers_dataset.csv",
                      dtype={"customer_zip_code_prefix": str})


@dlt.resource(name="geolocation", write_disposition="replace")
def geolocation():
    yield pd.read_csv(DATA_DIR / "olist_geolocation_dataset.csv",
                      dtype={"geolocation_zip_code_prefix": str})


@dlt.resource(name="sellers", write_disposition="replace")
def sellers():
    yield pd.read_csv(DATA_DIR / "olist_sellers_dataset.csv",
                      dtype={"seller_zip_code_prefix": str})


@dlt.resource(name="products", write_disposition="replace")
def products():
    yield pd.read_csv(DATA_DIR / "olist_products_dataset.csv")


@dlt.resource(name="product_category_name_translation", write_disposition="replace")
def category_translation():
    # utf-8-sig strips the BOM on this file's header.
    yield pd.read_csv(DATA_DIR / "product_category_name_translation.csv",
                      encoding="utf-8-sig")


# ---------------------------------------------------------------------------
# Transactional tables  (write_disposition="merge" -> idempotent upsert).
#   orders, order_reviews -> real timestamp cursor (dlt.sources.incremental):
#       pass 1 feeds the pre-2018 slice; pass 2 feeds the whole file and dlt's
#       cursor loads only rows newer than last run.
#   order_items, order_payments -> no usable date; merge on composite PK, with the
#       two passes split by parent-order-id membership (set built in olist_source).
# ---------------------------------------------------------------------------
@dlt.resource(name="orders", write_disposition="merge", primary_key="order_id")
def orders(pass_num: int,
           cursor=dlt.sources.incremental("order_purchase_timestamp")):
    df = pd.read_csv(DATA_DIR / "olist_orders_dataset.csv",
                     dtype={"customer_id": str})
    if pass_num == 1:
        df = df[df["order_purchase_timestamp"] < PASS1_CUTOFF]
    yield _records(df)


@dlt.resource(name="order_reviews", write_disposition="merge",
              primary_key=["review_id", "order_id"])
def order_reviews(pass_num: int,
                  cursor=dlt.sources.incremental("review_creation_date")):
    df = pd.read_csv(DATA_DIR / "olist_order_reviews_dataset.csv")
    if pass_num == 1:
        df = df[df["review_creation_date"] < PASS1_CUTOFF]
    yield _records(df)


@dlt.resource(name="order_items", write_disposition="merge",
              primary_key=["order_id", "order_item_id"])
def order_items(order_ids: set):
    df = pd.read_csv(DATA_DIR / "olist_order_items_dataset.csv")
    yield _records(df[df["order_id"].isin(order_ids)])


@dlt.resource(name="order_payments", write_disposition="merge",
              primary_key=["order_id", "payment_sequential"])
def order_payments(order_ids: set):
    df = pd.read_csv(DATA_DIR / "olist_order_payments_dataset.csv")
    yield _records(df[df["order_id"].isin(order_ids)])


# ---------------------------------------------------------------------------
# FX rates — one external source (Frankfurter), landed long-format & faithful.
# Business-day series only; weekend/holiday gap-filling is a downstream dbt job.
# ---------------------------------------------------------------------------
@dlt.resource(name="fx_rates", write_disposition="replace")
def fx_rates():
    resp = requests.get(
        f"https://api.frankfurter.app/{FX_START}..{FX_END}",
        params={"base": FX_BASE, "symbols": ",".join(FX_QUOTES)},
        timeout=60,
    )
    resp.raise_for_status()
    for rate_date, quotes in sorted(resp.json()["rates"].items()):
        for quote_currency, rate in quotes.items():
            yield {
                "rate_date": rate_date,
                "base_currency": FX_BASE,
                "quote_currency": quote_currency,
                "rate": rate,
            }


# ---------------------------------------------------------------------------
# Source: assembles the resources for a given pass.
# ---------------------------------------------------------------------------
@dlt.source(name="olist")
def olist_source(pass_num: int):
    # Build the per-pass order-id set from orders (cheap: 2 columns only).
    od = pd.read_csv(DATA_DIR / "olist_orders_dataset.csv",
                     usecols=["order_id", "order_purchase_timestamp"])
    before = set(od.loc[od["order_purchase_timestamp"] < PASS1_CUTOFF, "order_id"])
    from_2018 = set(od.loc[od["order_purchase_timestamp"] >= PASS1_CUTOFF, "order_id"])
    pass_ids = before if pass_num == 1 else from_2018

    # Full-refresh tables + FX only need loading once (pass 1).
    if pass_num == 1:
        yield customers()
        yield geolocation()
        yield sellers()
        yield products()
        yield category_translation()
        yield fx_rates()

    # Transactional tables load on both passes.
    yield orders(pass_num)
    yield order_reviews(pass_num)
    yield order_items(pass_ids)
    yield order_payments(pass_ids)


def main() -> int:
    pass_num = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    if pass_num not in (1, 2):
        print("Usage: python load_olist.py [1|2]")
        return 2

    pipeline = dlt.pipeline(
        pipeline_name="olist_raw",
        destination="snowflake",
        dataset_name="raw",          # -> schema OLIST.RAW
    )
    print(f"Running pass {pass_num} ...")
    info = pipeline.run(olist_source(pass_num))
    print(info)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
