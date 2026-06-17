with source as (

    select * from {{ source('olist_raw', 'products') }}

),

renamed as (

    select
        -- keys
        product_id,

        -- attributes
        product_category_name,                  -- Portuguese; English join deferred to marts

        -- measures (cast to int; light-touch typo fix: "lenght" -> "length")
        product_name_lenght::int         as product_name_length,
        product_description_lenght::int  as product_description_length,
        product_photos_qty::int          as product_photos_qty,
        product_weight_g::int            as product_weight_g,
        product_length_cm::int           as product_length_cm,
        product_height_cm::int           as product_height_cm,
        product_width_cm::int            as product_width_cm

    from source

)

select * from renamed
