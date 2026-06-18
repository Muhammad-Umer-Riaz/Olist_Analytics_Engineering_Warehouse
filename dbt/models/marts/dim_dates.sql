{#
    Calendar (date) dimension — one row per day, 2016-01-01 .. 2018-12-31. Covers
    every order, delivery, and estimated-delivery date across the warehouse, padded
    to clean calendar-year boundaries for tidy YoY / full-quarter comparisons.

    PK = date_key (YYYYMMDD integer surrogate, D1). Facts carry this integer as a
    role-playing FK (purchase / delivered / estimated dates all point here, D5).

    Determinism note: Snowflake's DAYOFWEEK / WEEKOFYEAR depend on the session
    WEEK_START / WEEK_OF_YEAR_POLICY params. We use the ISO variants (DAYOFWEEKISO =
    1=Mon..7=Sun, WEEKISO) so the dimension is identical regardless of session.

    Holidays come from the br_holidays seed (BR national holidays, incl. movable
    Carnival / Good Friday / Corpus Christi). LEFT JOIN => is_holiday flag.
    NOTE: dbt_utils.date_spine is end-EXCLUSIVE, so end_date is 2019-01-01 to keep
    2018-12-31 in the spine.
#}

with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2016-01-01' as date)",
        end_date="cast('2019-01-01' as date)"
    ) }}

),

dates as (
    select cast(date_day as date) as date_day
    from spine
),

holidays as (
    select holiday_date, holiday_name
    from {{ ref('br_holidays') }}
)

select
    to_number(to_char(d.date_day, 'YYYYMMDD'))      as date_key,
    d.date_day,
    year(d.date_day)                                 as year,
    quarter(d.date_day)                              as quarter,
    month(d.date_day)                                as month,
    monthname(d.date_day)                            as month_name,
    date_trunc('month', d.date_day)                  as month_start,
    weekiso(d.date_day)                              as week_of_year,   -- ISO week
    day(d.date_day)                                  as day_of_month,
    dayofweekiso(d.date_day)                         as day_of_week,    -- 1=Mon..7=Sun
    dayname(d.date_day)                              as day_name,
    (dayofweekiso(d.date_day) in (6, 7))             as is_weekend,     -- Sat / Sun
    (h.holiday_date is not null)                     as is_holiday,
    h.holiday_name
from dates as d
left join holidays as h
    on h.holiday_date = d.date_day
