-- DBT-21: the rules the report's readers rely on, enforced rather than
-- described. Each failing row names the rule it broke.

with report as (

    select * from {{ ref('fct_site_reliability_weekly') }}

),

violations as (

    -- Weeks start Monday. dayofweekiso is 1 on Monday under any session
    -- WEEK_START setting.
    select site_code, week_start_date, 'week does not start on a Monday' as rule_broken
    from report
    where dayofweekiso(week_start_date) != 1

    union all

    -- A zero-incident week must report an empty change-window share, not 0%.
    select site_code, week_start_date, 'no incidents but change-window share is not null'
    from report
    where incidents_opened = 0
      and pct_incidents_during_change_window is not null

    union all

    -- ...and a week with incidents must report one.
    select site_code, week_start_date, 'incidents present but change-window share is null'
    from report
    where incidents_opened > 0
      and pct_incidents_during_change_window is null

    union all

    -- The S1/S2 count is a subset of the total, never larger.
    select site_code, week_start_date, 'high severity count exceeds total incidents'
    from report
    where high_severity_incidents_opened > incidents_opened

    union all

    select site_code, week_start_date, 'change-window count exceeds total incidents'
    from report
    where incidents_during_change_window > incidents_opened

    union all

    select site_code, week_start_date, 'resolved count exceeds total incidents'
    from report
    where resolved_incidents > incidents_opened

    union all

    -- has_telemetry is the column consumers read instead of interpreting nulls,
    -- so it must agree with the utilization columns in both directions.
    select site_code, week_start_date, 'has_telemetry is false but utilization is populated'
    from report
    where not has_telemetry
      and (peak_utilization_pct_out is not null or avg_utilization_pct_out is not null)

    union all

    select site_code, week_start_date, 'has_telemetry is true but peak utilization is null'
    from report
    where has_telemetry
      and peak_utilization_pct_out is null

)

select * from violations
