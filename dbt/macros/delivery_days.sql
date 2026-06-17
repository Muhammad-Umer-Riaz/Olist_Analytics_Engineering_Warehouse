{#
    Whole calendar days between two timestamps (end - start), as an integer.
    Used for delivery lead time: delivery_days(purchase_ts, delivered_customer_ts).
    Returns NULL if either side is NULL (e.g. an order never delivered) — that
    NULL is meaningful signal, not an error (ADR-009 / Q6).
#}
{% macro delivery_days(start_ts, end_ts) -%}
    datediff('day', {{ start_ts }}, {{ end_ts }})
{%- endmacro %}
