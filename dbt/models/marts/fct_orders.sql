{#
    Order-grain fact: one row per order_id (ADR-007). Built directly on
    int_olist__orders_enriched, which already produced the order-grain hub in Phase 4
    (no fan-out) with delivery metrics, payment rollup, review, FX on the purchase
    date, and the 3-state payment-reconciliation flag.

    This model adds the role-playing date FKs (D5): purchase / delivered-to-customer
    / estimated-delivery, each an integer date_key into dim_dates. A NULL timestamp
    (e.g. undelivered order) yields a NULL date_key = meaningful signal.

    customer_id is the FK to dim_customers; order_status / primary_payment_type /
    review_score etc. are degenerate dimensions carried on the fact.
#}

with orders as (
    select * from {{ ref('int_olist__orders_enriched') }}
)

select
    -- grain
    order_id,

    -- foreign keys
    customer_id,                                                            -- -> dim_customers
    to_number(to_char(order_purchase_timestamp::date,        'YYYYMMDD'))   as order_purchase_date_key,            -- -> dim_dates
    to_number(to_char(order_delivered_customer_date::date,   'YYYYMMDD'))   as order_delivered_customer_date_key,  -- -> dim_dates (NULL if undelivered)
    to_number(to_char(order_estimated_delivery_date::date,   'YYYYMMDD'))   as order_estimated_delivery_date_key,  -- -> dim_dates

    -- degenerate dimensions
    order_status,
    primary_payment_type,
    is_multi_method,
    is_late,
    review_id,
    review_score,

    -- raw timestamps (exact time-of-day kept alongside the date keys)
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,

    -- delivery measures
    delivery_days,
    estimated_delivery_days,
    delivery_vs_estimate_days,

    -- payment measures (BRL + FX on purchase date)
    total_payment_value,
    total_payment_value_usd,
    total_payment_value_eur,
    payment_count,
    max_installments,
    distinct_payment_types,

    -- reconciliation (3-state; see ADR-009/015)
    order_item_total,
    item_count,
    payment_reconciliation_diff,
    is_payment_reconciled

from orders
