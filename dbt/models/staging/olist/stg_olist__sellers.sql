with source as (

    select * from {{ source('olist_raw', 'sellers') }}

),

renamed as (

    select
        -- keys
        seller_id,

        -- attributes
        seller_zip_code_prefix,  -- kept as VARCHAR to preserve leading zeros
        seller_city,
        seller_state

    from source

)

select * from renamed
