with source as (

    select * from {{ source('olist_raw', 'order_reviews') }}

),

renamed as (

    select
        -- composite key: review_id is NOT unique alone (proven in Phase 2),
        -- so the grain is (review_id, order_id)
        review_id,
        order_id,

        -- score
        review_score::int                      as review_score,

        -- free text
        review_comment_title,
        review_comment_message,

        -- timestamps — VARCHAR in RAW
        review_creation_date::timestamp_ntz    as review_creation_date,
        review_answer_timestamp::timestamp_ntz as review_answer_timestamp

    from source

)

select * from renamed
