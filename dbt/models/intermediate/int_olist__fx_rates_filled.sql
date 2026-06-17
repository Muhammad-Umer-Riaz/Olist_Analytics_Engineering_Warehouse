{#
    Gap-filled daily FX rates, BRL -> {USD, EUR}, one row per (calendar_date, quote_currency).

    Source rates (stg_olist__fx_rates) only exist on business days. Orders happen every
    day (23% on weekends; the first order is a Sunday), so we build a complete daily
    calendar and fill the gaps:
      - LOCF forward-fill  : carry the last quoted rate across closed market days.
      - Leading back-fill  : for dates BEFORE the first quote, use the earliest rate.
    `is_filled` flags any day that had no real quote (audit trail). The rate not_null
    test is the fail-loud guard against short FX coverage.
#}

{%- set fx     = ref('stg_olist__fx_rates') -%}
{%- set orders = ref('stg_olist__orders')   -%}

{#- Bounds cover both the FX series and the order dates so every order's purchase
    date resolves to a rate. NOTE: dbt_utils.date_spine EXCLUDES end_date, so we add
    one day to the true max to keep the final order date (2018-10-17) in the spine. -#}
{% set start_date = "(select least(
        (select min(rate_date) from " ~ fx ~ "),
        (select min(order_purchase_timestamp::date) from " ~ orders ~ ")))" %}
{% set end_date = "(select dateadd('day', 1, greatest(
        (select max(rate_date) from " ~ fx ~ "),
        (select max(order_purchase_timestamp::date) from " ~ orders ~ "))))" %}

with spine as (

    {{ dbt_utils.date_spine(datepart="day", start_date=start_date, end_date=end_date) }}

),

currencies as (
    select 'USD' as quote_currency
    union all
    select 'EUR' as quote_currency
),

calendar as (
    select
        cast(s.date_day as date) as calendar_date,
        c.quote_currency
    from spine as s
    cross join currencies as c
),

joined as (
    select
        cal.calendar_date,
        cal.quote_currency,
        fx.rate as quoted_rate
    from calendar as cal
    left join {{ ref('stg_olist__fx_rates') }} as fx
        on  fx.rate_date      = cal.calendar_date
        and fx.quote_currency = cal.quote_currency
),

filled as (
    select
        calendar_date,
        'BRL'::varchar as base_currency,
        quote_currency,
        quoted_rate,
        coalesce(
            quoted_rate,
            -- forward-fill: last known rate on/before this date (LOCF)
            last_value(quoted_rate ignore nulls) over (
                partition by quote_currency order by calendar_date
                rows between unbounded preceding and current row
            ),
            -- leading back-fill: earliest known rate, for pre-first-quote dates
            first_value(quoted_rate ignore nulls) over (
                partition by quote_currency order by calendar_date
                rows between current row and unbounded following
            )
        ) as rate,
        (quoted_rate is null) as is_filled
    from joined
)

select
    calendar_date,
    base_currency,
    quote_currency,
    rate,
    is_filled
from filled
