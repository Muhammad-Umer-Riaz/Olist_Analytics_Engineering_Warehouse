{#
    Consolidated quarantine of genuinely-broken rows (ADR-009 / Q6). This table holds
    rows we could NOT trust and set aside -- never silently dropped. Grain: one row
    per (entity, reason).

    NOT here: payment-reconciliation mismatches (those are legitimate financing fees
    in the main; they are flagged in int_olist__orders_enriched and kept). Also NOT
    here: the 775 canceled/unavailable orders with no items (meaningful signal, kept).

    The three orphan guards currently match 0 rows (Olist is FK-clean) but stay as
    standing integrity gates -- incremental loads (ADR-005/013) can land a child row
    before/without its parent order.
#}

with orders as (
    select order_id from {{ ref('stg_olist__orders') }}
),

orphan_items as (
    select
        'stg_olist__order_items'                                   as source_model,
        oi.order_id || '|' || oi.order_item_id::varchar           as business_key,
        'orphan_order_item'                                        as reject_reason,
        'order_item references an order_id not present in orders'  as reject_detail
    from {{ ref('stg_olist__order_items') }} as oi
    left join orders as o on o.order_id = oi.order_id
    where o.order_id is null
),

orphan_payments as (
    select
        'stg_olist__order_payments'                               as source_model,
        op.order_id || '|' || op.payment_sequential::varchar      as business_key,
        'orphan_order_payment'                                    as reject_reason,
        'payment references an order_id not present in orders'     as reject_detail
    from {{ ref('stg_olist__order_payments') }} as op
    left join orders as o on o.order_id = op.order_id
    where o.order_id is null
),

orphan_reviews as (
    select
        'stg_olist__order_reviews'                                as source_model,
        orv.review_id || '|' || orv.order_id                      as business_key,
        'orphan_order_review'                                     as reject_reason,
        'review references an order_id not present in orders'      as reject_detail
    from {{ ref('stg_olist__order_reviews') }} as orv
    left join orders as o on o.order_id = orv.order_id
    where o.order_id is null
),

orders_without_payment as (
    select
        'stg_olist__orders'                                          as source_model,
        o.order_id                                                  as business_key,
        'order_no_payment'                                          as reject_reason,
        'order has no payment record (cannot reconcile what was paid)' as reject_detail
    from {{ ref('stg_olist__orders') }} as o
    left join {{ ref('stg_olist__order_payments') }} as op on op.order_id = o.order_id
    where op.order_id is null
),

all_rejects as (
    select source_model, business_key, reject_reason, reject_detail from orphan_items
    union all
    select source_model, business_key, reject_reason, reject_detail from orphan_payments
    union all
    select source_model, business_key, reject_reason, reject_detail from orphan_reviews
    union all
    select source_model, business_key, reject_reason, reject_detail from orders_without_payment
)

select
    source_model,
    business_key,
    reject_reason,
    reject_detail,
    cast('{{ run_started_at.strftime("%Y-%m-%d %H:%M:%S") }}' as timestamp_ntz) as rejected_at
from all_rejects
