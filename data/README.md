# data/

The raw Olist CSVs are **not committed** to this repo (they're gitignored — large,
and subject to Kaggle's terms). Download them yourself before running the pipeline.

## Source

**Brazilian E-Commerce Public Dataset by Olist** — Kaggle dataset
`olistbr/brazilian-ecommerce`
<https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce>

You must accept the Kaggle dataset terms before downloading.

## Setup

1. Download and unzip the dataset.
2. Place all **9 CSV files** directly in `data/raw/`.

## Expected files (the 9-table core)

```
data/raw/
├── olist_customers_dataset.csv
├── olist_geolocation_dataset.csv
├── olist_order_items_dataset.csv
├── olist_order_payments_dataset.csv
├── olist_order_reviews_dataset.csv
├── olist_orders_dataset.csv
├── olist_products_dataset.csv
├── olist_sellers_dataset.csv
└── product_category_name_translation.csv
```

> The separate **marketing funnel** dataset is **not** in scope (see `DECISIONS.md`,
> ADR-002). Only the 9 files above are used.
