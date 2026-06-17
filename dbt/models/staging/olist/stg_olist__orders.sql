with source as (

    select * from {{ source('olist_raw', 'orders') }}

),

renamed as (

    select
        -- keys
        order_id,
        customer_id,

        -- status
        order_status,

        -- timestamps: RAW landed these as VARCHAR; cast to TIMESTAMP_NTZ
        -- (Olist times are local Brazil with no offset). Hard cast = fail-fast.
        order_purchase_timestamp::timestamp_ntz      as order_purchase_timestamp,
        order_approved_at::timestamp_ntz             as order_approved_at,
        order_delivered_carrier_date::timestamp_ntz  as order_delivered_carrier_date,
        order_delivered_customer_date::timestamp_ntz as order_delivered_customer_date,
        order_estimated_delivery_date::timestamp_ntz as order_estimated_delivery_date

    from source

)

select * from renamed
