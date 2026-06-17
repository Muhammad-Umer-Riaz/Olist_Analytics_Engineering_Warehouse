{#
    RAW geolocation has MANY rows per zip prefix: scattered GPS points and
    inconsistent city spellings. We collapse to ONE row per zip:
      - coordinates  = MEDIAN(lat), MEDIAN(lng)   (robust to outlier pins; NULL-tolerant)
      - city / state = the most frequent (city, state) pair, with a DETERMINISTIC
                       tie-break (count desc, then alphabetical) so re-runs are reproducible
                       -- note: bare MODE() would break ties non-deterministically.
    Zips whose coordinates are all NULL are kept (they still have a city/state).
#}

with source as (

    select * from {{ source('olist_raw', 'geolocation') }}

),

-- Median coordinates per zip (MEDIAN ignores NULLs).
coords as (

    select
        geolocation_zip_code_prefix,
        median(geolocation_lat) as geolocation_lat,
        median(geolocation_lng) as geolocation_lng
    from source
    group by geolocation_zip_code_prefix

),

-- Frequency of each (city, state) spelling within a zip.
place_counts as (

    select
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state,
        count(*) as n_rows,
        row_number() over (
            partition by geolocation_zip_code_prefix
            order by count(*) desc, geolocation_city asc, geolocation_state asc
        ) as place_rank
    from source
    group by
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state

),

-- Keep only the winning (most frequent, deterministic) place per zip.
modal_place as (

    select
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state
    from place_counts
    where place_rank = 1

)

select
    coords.geolocation_zip_code_prefix,
    coords.geolocation_lat,
    coords.geolocation_lng,
    modal_place.geolocation_city,
    modal_place.geolocation_state
from coords
left join modal_place
    on coords.geolocation_zip_code_prefix = modal_place.geolocation_zip_code_prefix
