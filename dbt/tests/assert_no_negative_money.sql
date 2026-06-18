-- Money can never be negative. Olist line items are price + freight, both >= 0,
-- and the FX-converted revenue is a positive multiple of a non-negative BRL amount.
-- Any negative here means bad source data or a broken FX/revenue calculation.
-- Returns the offending item grain + the values, so a failure is self-explaining.
select
    order_id,
    order_item_id,
    price_brl,
    freight_brl,
    revenue_brl,
    revenue_usd,
    revenue_eur
from {{ ref('fct_order_items') }}
where price_brl   < 0
   or freight_brl < 0
   or revenue_brl < 0
   or revenue_usd < 0
   or revenue_eur < 0
