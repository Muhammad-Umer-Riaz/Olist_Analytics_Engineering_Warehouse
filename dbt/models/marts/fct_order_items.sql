{#
    Order-item-grain fact: one row per (order_id, order_item_id) — the finest sales
    grain (ADR-007). This is where the deferred item-grain FX lands (D6): revenue is
    converted to USD/EUR on the ORDER's purchase date (same anchor as fct_orders, so
    the two facts reconcile), reusing the brl_to + order_item_revenue macros and the
    gap-filled rate series.

    Joined to orders (inner) for the purchase date and customer FK. The inner join
    enforces "no orphan fact keys": an item without a parent order is impossible to
    place in time/customer and is documented separately in int_olist__rejects
    (orphan guard, currently 0 rows).

    Measures: price/freight/revenue in BRL; revenue in USD + EUR.
#}

with items as (
    select * from {{ ref('stg_olist__order_items') }}
),

orders as (
    select order_id, customer_id, order_purchase_timestamp
    from {{ ref('stg_olist__orders') }}
),

fx_usd as (
    select calendar_date, rate as usd_rate
    from {{ ref('int_olist__fx_rates_filled') }}
    where quote_currency = 'USD'
),

fx_eur as (
    select calendar_date, rate as eur_rate
    from {{ ref('int_olist__fx_rates_filled') }}
    where quote_currency = 'EUR'
)

select
    -- grain
    i.order_id,
    i.order_item_id,

    -- foreign keys
    i.product_id,                                                          -- -> dim_products
    i.seller_id,                                                           -- -> dim_sellers
    o.customer_id,                                                         -- -> dim_customers
    to_number(to_char(o.order_purchase_timestamp::date, 'YYYYMMDD'))       as order_purchase_date_key,  -- -> dim_dates

    -- degenerate dimension
    i.shipping_limit_date,

    -- measures (BRL)
    i.price                                                  as price_brl,
    i.freight_value                                          as freight_brl,
    {{ order_item_revenue('i.price', 'i.freight_value') }}   as revenue_brl,

    -- measures (FX-converted revenue, on the order's purchase date)
    {{ brl_to(order_item_revenue('i.price', 'i.freight_value'), 'usd.usd_rate') }} as revenue_usd,
    {{ brl_to(order_item_revenue('i.price', 'i.freight_value'), 'eur.eur_rate') }} as revenue_eur

from items as i
inner join orders  as o   on o.order_id        = i.order_id
left join  fx_usd  as usd on usd.calendar_date = o.order_purchase_timestamp::date
left join  fx_eur  as eur on eur.calendar_date = o.order_purchase_timestamp::date
