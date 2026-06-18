{#
    Average Order Value = total monetary / number of orders, rounded to cents.
    nullif guards division by zero: a customer with 0 orders yields NULL (honest)
    rather than a divide-by-zero error. In customer_summary every person has >=1
    order, but the guard keeps the macro safe to reuse anywhere.
#}
{% macro aov(monetary, frequency) -%}
    round({{ monetary }} / nullif({{ frequency }}, 0), 2)
{%- endmacro %}
