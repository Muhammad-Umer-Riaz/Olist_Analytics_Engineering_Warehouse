with source as (

    select * from {{ source('olist_raw', 'order_payments') }}

),

renamed as (

    select
        -- composite key: one row per (order_id, payment_sequential)
        order_id,
        payment_sequential::int     as payment_sequential,

        -- attributes
        payment_type,
        payment_installments::int   as payment_installments,

        -- measure
        payment_value::number(10,2) as payment_value

    from source

)

select * from renamed
