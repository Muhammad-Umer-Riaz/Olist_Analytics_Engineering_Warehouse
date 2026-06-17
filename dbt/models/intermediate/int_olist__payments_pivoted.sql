{#
    Collapse payments to ONE row per order (staging is 1 row per installment/split).
    - total_payment_value : what the customer actually paid (sum across all rows).
    - primary_payment_type: the method contributing the most BRL, deterministic
      tie-break (value desc, then payment_type alphabetically).
    - is_multi_method     : did the order mix methods (e.g. voucher + credit_card)?
#}

with payments as (
    select * from {{ ref('stg_olist__order_payments') }}
),

-- value per (order, type): the basis for picking the dominant method by money
type_value as (
    select
        order_id,
        payment_type,
        sum(payment_value) as type_value
    from payments
    group by order_id, payment_type
),

primary_type as (
    select
        order_id,
        payment_type as primary_payment_type
    from type_value
    qualify row_number() over (
        partition by order_id
        order by type_value desc, payment_type
    ) = 1
),

order_rollup as (
    select
        order_id,
        sum(payment_value)               as total_payment_value,
        count(*)                         as payment_count,
        max(payment_installments)        as max_installments,
        count(distinct payment_type)     as distinct_payment_types,
        count(distinct payment_type) > 1 as is_multi_method
    from payments
    group by order_id
)

select
    r.order_id,
    r.total_payment_value,
    r.payment_count,
    r.max_installments,
    r.distinct_payment_types,
    r.is_multi_method,
    p.primary_payment_type
from order_rollup as r
inner join primary_type as p using (order_id)
