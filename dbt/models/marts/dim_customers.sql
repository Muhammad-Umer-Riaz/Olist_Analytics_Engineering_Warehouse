{#
    Customer dimension at the ORDER-scoped grain: one row per customer_id (ADR-006,
    the two-layer customer grain). customer_unique_id is carried as the linking
    attribute to the real person (person-grain analytics live in customer_summary).

    Native customer_city/state are kept here (full coverage, the source's own
    location statement, D8). customer_zip_code_prefix is an FK to dim_geography,
    which supplies coordinates. Zips absent from geolocation = left-join nulls there
    (signal), but city/state here have no coverage gap.
#}

select
    customer_id,               -- PK (per-order customer key; fact join key)
    customer_unique_id,        -- the real person (links a person's many orders)
    customer_zip_code_prefix,  -- FK -> dim_geography
    customer_city,
    customer_state
from {{ ref('stg_olist__customers') }}
