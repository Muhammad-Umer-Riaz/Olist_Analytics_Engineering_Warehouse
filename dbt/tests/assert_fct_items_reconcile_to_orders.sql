-- Cross-fact reconciliation: the two facts must agree. Summing the item-grain
-- revenue (price + freight) for an order in fct_order_items must equal that order's
-- order_item_total carried on fct_orders, to the cent. This is the same 0-mismatch
-- check run in Snowsight during Phase 5, now executable on every run.
--
-- It proves there is no fan-out (an item joining to multiple order rows, or vice
-- versa) and that the shared revenue definition stays consistent across the star.
-- Tolerance 0.01 BRL absorbs only cent-level decimal rounding, nothing larger.
with items_rolled_up as (
    select
        order_id,
        sum(revenue_brl) as items_revenue_brl
    from {{ ref('fct_order_items') }}
    group by order_id
)

select
    o.order_id,
    o.order_item_total,
    i.items_revenue_brl,
    o.order_item_total - i.items_revenue_brl as diff_brl
from {{ ref('fct_orders') }} as o
inner join items_rolled_up as i on i.order_id = o.order_id
where abs(o.order_item_total - i.items_revenue_brl) > 0.01
