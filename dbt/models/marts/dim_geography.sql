{#
    Conformed geography dimension (ADR-016 / D2). One row per zip code prefix —
    the natural key. Shared by dim_customers and dim_sellers, which carry their
    zip_prefix as an FK. Source is already collapsed to 1 row/zip in staging
    (median coords + deterministic modal city/state). Supplies the coordinates and
    the cleaned modal city/state for map labels; the per-entity textual location
    lives on dim_customers / dim_sellers (D8).
#}

select
    geolocation_zip_code_prefix as zip_code_prefix,
    geolocation_city            as city,
    geolocation_state           as state,
    geolocation_lat             as latitude,
    geolocation_lng             as longitude
from {{ ref('stg_olist__geolocation') }}
