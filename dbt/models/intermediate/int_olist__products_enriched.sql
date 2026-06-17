{#
    Products with the English category attached (PT->EN join deferred from staging,
    ADR-014). LEFT JOIN so an untranslated category keeps the product with a NULL
    English label (a missing-reference gap = signal, not a reject). Grain: product_id.
#}

with products as (
    select * from {{ ref('stg_olist__products') }}
),

translation as (
    select * from {{ ref('stg_olist__category_translation') }}
)

select
    p.product_id,
    p.product_category_name,            -- Portuguese (kept for traceability)
    t.product_category_name_english,    -- NULL when no translation exists (signal)
    p.product_name_length,
    p.product_description_length,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
from products as p
left join translation as t
    on p.product_category_name = t.product_category_name
