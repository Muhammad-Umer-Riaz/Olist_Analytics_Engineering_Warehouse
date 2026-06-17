with source as (

    select * from {{ source('olist_raw', 'product_category_name_translation') }}

),

renamed as (

    select
        product_category_name,           -- Portuguese (join key back to products)
        product_category_name_english    -- English label

    from source

)

select * from renamed
