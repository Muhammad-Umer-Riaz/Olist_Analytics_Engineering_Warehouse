{#
    One review per order. ~547 orders carry two reviews; keep the LATEST as the
    customer's final assessment. Deterministic order: creation date, then answer
    timestamp (non-null wins), then review_id. order_id is unique after this;
    review_id is NOT (a review can legitimately span multiple orders).
#}

with reviews as (
    select * from {{ ref('stg_olist__order_reviews') }}
)

select
    order_id,
    review_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
from reviews
qualify row_number() over (
    partition by order_id
    order by review_creation_date desc,
             review_answer_timestamp desc nulls last,
             review_id desc
) = 1
