{#
    Override dbt's default schema naming.

    By default dbt builds the target schema as "<profile_schema>_<custom_schema>"
    (e.g. STAGING_STAGING) so multiple developers can work in isolated schemas off
    one warehouse. We have fixed, pre-created schemas (RAW / STAGING / INTERMEDIATE /
    MARTS), so we want a model's +schema config used VERBATIM instead.

    - custom_schema_name is None  -> fall back to the profile's target schema.
    - custom_schema_name is set   -> use it exactly (trimmed).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
