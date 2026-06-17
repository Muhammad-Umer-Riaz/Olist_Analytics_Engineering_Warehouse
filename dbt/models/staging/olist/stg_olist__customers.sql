with source as (

    select * from {{ source('olist_raw', 'customers') }}

),

renamed as (

    select
        -- keys
        customer_id,             -- per-order customer key (join key for facts)
        customer_unique_id,      -- the real person (links a person's many orders)

        -- attributes
        customer_zip_code_prefix,  -- kept as VARCHAR to preserve leading zeros
        customer_city,
        customer_state

    from source

)

select * from renamed
