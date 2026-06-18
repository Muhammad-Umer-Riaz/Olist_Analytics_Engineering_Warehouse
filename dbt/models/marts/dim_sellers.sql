{#
    Seller dimension. One row per seller_id. seller_zip_code_prefix is an FK to the
    conformed dim_geography; native seller_city/state kept here (full coverage, D8).
#}

select
    seller_id,                 -- PK
    seller_zip_code_prefix,    -- FK -> dim_geography
    seller_city,
    seller_state
from {{ ref('stg_olist__sellers') }}
