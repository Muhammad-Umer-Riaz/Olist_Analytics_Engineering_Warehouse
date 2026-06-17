with source as (

    select * from {{ source('olist_raw', 'order_items') }}

),

renamed as (

    select
        -- composite key: one row per (order_id, order_item_id)
        order_id,
        order_item_id::int                  as order_item_id,

        -- foreign keys
        product_id,
        seller_id,

        -- timestamp (shipping deadline) — VARCHAR in RAW
        shipping_limit_date::timestamp_ntz  as shipping_limit_date,

        -- measures
        price::number(10,2)                 as price,
        freight_value::number(10,2)         as freight_value

    from source

)

select * from renamed
