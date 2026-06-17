{#
    Customer-paid value of an order-item line = price + freight.
    Freight is included because the customer pays it, and because order-level
    payment reconciliation (sum(payment_value) vs sum(price+freight)) must use the
    same definition. Kept as a macro so revenue is defined in exactly one place.
#}
{% macro order_item_revenue(price, freight_value) -%}
    ({{ price }} + {{ freight_value }})
{%- endmacro %}
