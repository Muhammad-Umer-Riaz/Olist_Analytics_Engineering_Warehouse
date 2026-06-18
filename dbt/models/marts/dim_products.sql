{#
    Product dimension. One row per product_id. Built on int_olist__products_enriched,
    which already attached the English category (PT->EN, LEFT JOIN). An untranslated
    category keeps the product with a NULL English label = signal, not a reject.
#}

select
    product_id,                       -- PK
    product_category_name,            -- Portuguese (kept for traceability)
    product_category_name_english,    -- NULL when untranslated (signal)
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
from {{ ref('int_olist__products_enriched') }}
