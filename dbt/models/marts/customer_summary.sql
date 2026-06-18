{#
    Person-grain customer summary: one row per customer_unique_id (ADR-006). This is
    the second layer of the two-layer customer grain — fct_orders joins on the
    per-order customer_id; here we resolve UP to the real person (via dim_customers)
    and aggregate their lifetime behaviour.

    Metrics:
      - frequency    : number of distinct orders the person placed.
      - monetary     : total order revenue (sum of price+freight; merchant-received
                       money, D7). clv_historical = monetary (HISTORICAL, not predictive).
      - aov          : monetary / frequency (aov macro, div0-safe).
      - recency_days : days from the person's last order to the dataset's max order
                       date ("today" is the latest order, since the data is static).
      - first/last_order_date, tenure_days.
      - R/F/M quintile scores (NTILE 5, 5 = best) + rfm_segment (rfm_bucket macro).

    Scoring: Recency and Monetary use NTILE(5) quintiles (continuous, well-spread;
    deterministic customer_unique_id tie-break). Frequency is scored BY VALUE
    (least(frequency,5)): 1 order -> 1 .. 5+ orders -> 5. NTILE is deliberately NOT
    used for frequency -- Olist is ~97% one-time buyers, so a quintile forces ~2/5 of
    single-purchase customers into f>=4 and mislabels them "Loyal". Value scoring
    keeps one-time buyers at f=1, so segmentation is correctly driven by Recency and
    Monetary (the dataset's real signal).
#}

with person_orders as (
    select
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp::date as order_date,
        o.order_item_total
    from {{ ref('fct_orders') }} as o
    inner join {{ ref('dim_customers') }} as c
        on c.customer_id = o.customer_id
),

as_of as (
    select max(order_date) as as_of_date from person_orders
),

aggregated as (
    select
        customer_unique_id,
        count(distinct order_id)            as frequency,
        coalesce(sum(order_item_total), 0)  as monetary,   -- 0 when only item-less orders
        min(order_date)                     as first_order_date,
        max(order_date)                     as last_order_date
    from person_orders
    group by customer_unique_id
),

metrics as (
    select
        a.customer_unique_id,
        a.frequency,
        a.monetary,
        {{ aov('a.monetary', 'a.frequency') }}                                as aov,
        datediff('day', a.last_order_date, (select as_of_date from as_of))    as recency_days,
        a.first_order_date,
        a.last_order_date,
        datediff('day', a.first_order_date, a.last_order_date)                as tenure_days,
        a.monetary                                                           as clv_historical
    from aggregated as a
),

scored as (
    select
        m.*,
        ntile(5) over (order by recency_days desc, customer_unique_id) as r_score,  -- 5 = most recent
        least(frequency, 5)                                            as f_score,  -- value-based: 1 order=1 .. 5+ orders=5
        ntile(5) over (order by monetary     asc,  customer_unique_id) as m_score   -- 5 = highest spend
    from metrics as m
)

select
    customer_unique_id,
    frequency,
    monetary,
    aov,
    recency_days,
    first_order_date,
    last_order_date,
    tenure_days,
    r_score,
    f_score,
    m_score,
    {{ rfm_bucket('r_score', 'f_score', 'm_score') }} as rfm_segment,
    clv_historical
from scored
