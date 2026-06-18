{{ config(severity = 'warn') }}

-- Conditional-null rule (Q6 policy, ADR-009/015): an order whose status is
-- 'delivered' MUST carry a delivered-to-customer date. A NULL delivery date on a
-- delivered order is a contradiction between the status field and the timeline.
--
-- Direction is deliberate: we assert delivered => date present. We do NOT assert
-- the reverse (non-delivered => date absent), because a canceled order can
-- legitimately have been delivered first and then canceled, so it may carry a
-- delivery timestamp. Asserting the reverse would flag valid rows.
--
-- Severity = warn (not error): this surfaces 8 known Olist source anomalies -- orders
-- marked 'delivered' whose customer-delivery timestamp was never captured (7 of the 8
-- still reached the carrier, so delivery almost certainly happened; it's a data-capture
-- gap, not a fake delivery). These are legitimate orders we keep in the fact, so we
-- make the gap visible every run rather than quarantining valid data. See README caveats.
select
    order_id,
    order_status,
    order_delivered_customer_date_key
from {{ ref('fct_orders') }}
where order_status = 'delivered'
  and order_delivered_customer_date_key is null
