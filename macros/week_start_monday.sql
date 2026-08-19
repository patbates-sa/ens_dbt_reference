-- DBT-21: Monday week boundary, defined once so the report, the telemetry
-- rollup and the week spine cannot drift apart.
--
-- Deliberately not date_trunc('week', ...): that follows the Snowflake
-- WEEK_START session parameter, so the same SQL can return a Sunday or a
-- Monday depending on who is connected. dayofweekiso is 1 on Monday
-- regardless of session settings.
{% macro week_start_monday(ts_column) -%}
    dateadd('day', 1 - dayofweekiso({{ ts_column }}), cast({{ ts_column }} as date))
{%- endmacro %}
