{#
    Convert a BRL amount to a quote currency (USD/EUR), rounded to cents.
    `rate` is BRL -> quote (units of quote per 1 BRL, e.g. ~0.27 for USD), supplied
    by a join to int_olist__fx_rates_filled on the order's purchase date. So the
    converted amount = amount_brl * rate.
#}
{% macro brl_to(amount, rate) -%}
    round({{ amount }} * {{ rate }}, 2)
{%- endmacro %}
