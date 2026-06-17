with source as (

    select * from {{ source('olist_raw', 'fx_rates') }}

),

renamed as (

    select
        -- grain: one row per (rate_date, quote_currency)
        rate_date::date     as rate_date,
        base_currency,                      -- always BRL
        quote_currency,                     -- USD or EUR
        rate::number(18, 8) as rate         -- BRL -> quote_currency

    from source

)

select * from renamed
