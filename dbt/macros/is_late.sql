{#
    TRUE when an order was delivered after its estimated delivery date.
    Three-state on purpose (ADR-009 / Q6): NULL when not yet delivered, because
    "undelivered" is a meaningful gap, not "on time". Never collapse it to FALSE.
#}
{% macro is_late(delivered_ts, estimated_ts) -%}
    case
        when {{ delivered_ts }} is null then null
        else {{ delivered_ts }} > {{ estimated_ts }}
    end
{%- endmacro %}
