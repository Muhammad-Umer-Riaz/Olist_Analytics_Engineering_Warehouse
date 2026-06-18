{#
    Map RFM quintile scores (each 1-5, where 5 = best: most recent / most frequent /
    highest spend) to a named customer segment.

    The grid is intentionally R x F driven (the classic RFM segmentation), with M
    used to separate high-value customers. Order of the CASE matters: the most
    specific / most valuable segments are tested first.

    Scoring note: F is value-based, NOT a quintile (see customer_summary) -- Olist is
    dominated by ONE-TIME buyers, so most customers score F=1. That correctly pushes
    most rows into the recency- and monetary-driven buckets (New Customers, Big
    Spenders, Lost) rather than the loyalty buckets -- an honest reflection of the
    data, not an NTILE artefact. The f>=4 "Loyal/Champions" buckets now require a
    genuine 4+ orders.
#}
{% macro rfm_bucket(r, f, m) -%}
case
    when {{ r }} >= 4 and {{ f }} >= 4 and {{ m }} >= 4   then 'Champions'
    when {{ f }} >= 4                                     then 'Loyal Customers'
    when {{ m }} >= 4 and {{ r }} >= 3                    then 'Big Spenders'
    when {{ r }} >= 4 and {{ f }} >= 2                    then 'Potential Loyalist'
    when {{ r }} >= 4 and {{ f }} = 1                     then 'New Customers'
    when {{ r }} = 3                                      then 'Promising'
    when {{ r }} <= 2 and ({{ f }} >= 3 or {{ m }} >= 4)  then 'At Risk'
    when {{ r }} <= 2 and {{ f }} = 2                     then 'Hibernating'
    when {{ r }} <= 2 and {{ f }} = 1                     then 'Lost'
    else 'Needs Attention'
end
{%- endmacro %}
