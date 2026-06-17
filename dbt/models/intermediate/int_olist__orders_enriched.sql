{#
    Order-grain hub feeding fct_orders. One row per order. Combines:
      - delivery metrics (delivery_days / is_late macros),
      - the collapsed payment rollup (int_olist__payments_pivoted),
      - the deduped review (int_olist__reviews_deduped),
      - order-item totals (basis for payment reconciliation),
      - FX conversion of the paid amount on the order's PURCHASE date.

    Reconciliation is 3-state (ADR-009): TRUE within +/-0.01 BRL, FALSE when it
    genuinely differs, NULL when not assessable (order missing items OR payments).
    Discrepancies are flagged here and kept (most are legitimate financing fees);
    only structurally broken rows go to int_olist__rejects.
#}

with orders as (
    select * from {{ ref('stg_olist__orders') }}
),

payments as (
    select * from {{ ref('int_olist__payments_pivoted') }}
),

reviews as (
    select order_id, review_id, review_score
    from {{ ref('int_olist__reviews_deduped') }}
),

item_totals as (
    select
        order_id,
        sum({{ order_item_revenue('price', 'freight_value') }}) as order_item_total,
        count(*)                                                as item_count
    from {{ ref('stg_olist__order_items') }}
    group by order_id
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
    o.order_id,
    o.customer_id,
    o.order_status,

    -- timestamps
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- delivery metrics (macros). NULL where not delivered = meaningful signal.
    {{ delivery_days('o.order_purchase_timestamp', 'o.order_delivered_customer_date') }} as delivery_days,
    {{ delivery_days('o.order_purchase_timestamp', 'o.order_estimated_delivery_date') }} as estimated_delivery_days,
    {{ delivery_days('o.order_estimated_delivery_date', 'o.order_delivered_customer_date') }} as delivery_vs_estimate_days,
    {{ is_late('o.order_delivered_customer_date', 'o.order_estimated_delivery_date') }}     as is_late,

    -- payment rollup
    p.total_payment_value,
    p.payment_count,
    p.max_installments,
    p.distinct_payment_types,
    p.is_multi_method,
    p.primary_payment_type,

    -- FX conversion of paid amount, on the purchase date (BRL -> USD/EUR)
    {{ brl_to('p.total_payment_value', 'usd.usd_rate') }} as total_payment_value_usd,
    {{ brl_to('p.total_payment_value', 'eur.eur_rate') }} as total_payment_value_eur,

    -- review
    r.review_id,
    r.review_score,

    -- order-item totals (reconciliation basis)
    it.order_item_total,
    it.item_count,

    -- 3-state payment reconciliation (tolerance +/-0.01 BRL)
    case
        when it.order_item_total is null or p.total_payment_value is null then null
        else round(p.total_payment_value - it.order_item_total, 2)
    end as payment_reconciliation_diff,
    case
        when it.order_item_total is null or p.total_payment_value is null then null
        else abs(p.total_payment_value - it.order_item_total) <= 0.01
    end as is_payment_reconciled

from orders as o
left join payments    as p   on p.order_id        = o.order_id
left join reviews     as r   on r.order_id        = o.order_id
left join item_totals as it  on it.order_id       = o.order_id
left join fx_usd      as usd on usd.calendar_date = o.order_purchase_timestamp::date
left join fx_eur      as eur on eur.calendar_date = o.order_purchase_timestamp::date
