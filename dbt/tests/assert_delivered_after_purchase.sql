-- Causality: a delivery cannot happen before the order was placed.
-- We compare the raw timestamps (exact time-of-day, not the truncated date keys).
-- 3-state aware: undelivered orders have a NULL delivered timestamp -- that is a
-- meaningful signal (ADR-009), not a violation, so the IS NOT NULL guard excludes
-- them. Only a delivered-BEFORE-purchase row is a genuine integrity failure.
select
    order_id,
    order_purchase_timestamp,
    order_delivered_customer_date
from {{ ref('fct_orders') }}
where order_delivered_customer_date is not null
  and order_delivered_customer_date < order_purchase_timestamp
