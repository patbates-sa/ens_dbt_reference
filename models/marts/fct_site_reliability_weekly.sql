{#
    DBT-21: The Monday regional review slide, as a governed table.

    One row per site per week, dense: every site appears in every week in the
    reporting range whether or not anything happened there. The failure mode
    being designed out is the missing row that gets read as an improvement, so
    the site list and the week list are cross-joined first and the measures are
    left-joined onto that frame.

    Three deliberate null/zero distinctions, because they carry different
    meanings and the current hand-built slide conflates them:

      1. Zero incidents is a zero. Quiet weeks are measured.
      2. The change-window share of zero incidents is NULL, not 0%. There was
         nothing to measure, and 0% reads as a finding.
      3. Utilization is NULL where telemetry retention does not reach back that
         far. has_telemetry says so as a column, so a consumer can tell
         "not measured" from "measured and low" without reading the docs.
#}

with sites as (

    select
        site_code,
        city            as site_city,
        region          as site_region,
        country         as site_country,
        site_tier
    from {{ ref('stg_ens__site') }}

),

incidents as (

    select * from {{ ref('int_ens__incident_device_attributed') }}

),

telemetry as (

    select * from {{ ref('fct_interface_performance_hourly') }}

),

-- The reporting range is the span of the underlying data, not the full five
-- years of the time spine. A spine wider than the data would emit hundreds of
-- all-zero weeks, which is the same lie as a missing row in the other
-- direction.
activity as (

    select min(opened_ts)   as first_ts, max(opened_ts)   as last_ts from incidents
    union all
    select min(metric_hour) as first_ts, max(metric_hour) as last_ts from telemetry

),

activity_bounds as (

    select
        min(first_ts)   as first_activity_ts,
        max(last_ts)    as last_activity_ts
    from activity

),

weeks as (

    select distinct {{ week_start_monday('t.date_hour') }} as week_start_date
    from {{ ref('time_spine_hourly') }} t
    cross join activity_bounds b
    where t.date_hour >= b.first_activity_ts
      and t.date_hour <= b.last_activity_ts

),

site_weeks as (

    select
        s.site_code,
        s.site_city,
        s.site_region,
        s.site_country,
        s.site_tier,
        w.week_start_date
    from sites s
    cross join weeks w

),

-- Current inventory, applied to every week. The device snapshot only starts
-- collecting history from its first run, so an as-of-week count would read as
-- zero devices for every week already in the report. Documented rather than
-- faked.
device_counts as (

    select
        site_code,
        count(*)                                    as device_count,
        count_if(lifecycle_state = 'in_service')    as in_service_device_count,
        count_if(is_monitored_device)               as monitored_device_count
    from {{ ref('dim_device') }}
    group by 1

),

incident_weekly as (

    select
        d.site_code,
        i.opened_week_start_date                        as week_start_date,

        count(*)                                        as incidents_opened,
        count_if(i.is_high_severity)                    as high_severity_incidents_opened,
        count_if(i.opened_during_change_window)         as incidents_during_change_window,
        count_if(not i.is_open)                         as resolved_incidents,

        -- Open incidents have a null minutes_to_resolve, so both aggregates
        -- describe resolved incidents only.
        sum(i.minutes_to_resolve)                       as total_minutes_to_resolve,
        avg(i.minutes_to_resolve)                       as avg_minutes_to_resolve

    from incidents i
    join {{ ref('dim_device') }} d
      on d.device_id = i.device_id
    group by 1, 2

),

telemetry_weekly as (

    select
        site_code,
        {{ week_start_monday('metric_hour') }}      as week_start_date,

        max(peak_utilization_pct_out)               as peak_utilization_pct_out,

        -- Mean across the site's monitored interface-hours in the week. Each
        -- interface-hour counts once, so a busy interface does not dominate.
        avg(avg_utilization_pct_out)                as avg_utilization_pct_out,

        count(distinct interface_id)                as monitored_interfaces_with_telemetry,
        count(*)                                    as interface_hours_observed

    from telemetry
    group by 1, 2

)

select
    sw.week_start_date,
    dateadd('day', 6, sw.week_start_date)                       as week_end_date,

    sw.site_code,
    sw.site_city,
    sw.site_region,
    sw.site_country,
    sw.site_tier,

    coalesce(dc.device_count, 0)                                as device_count,
    coalesce(dc.in_service_device_count, 0)                     as in_service_device_count,
    coalesce(dc.monitored_device_count, 0)                      as monitored_device_count,

    coalesce(iw.incidents_opened, 0)                            as incidents_opened,
    coalesce(iw.high_severity_incidents_opened, 0)              as high_severity_incidents_opened,
    coalesce(iw.incidents_during_change_window, 0)              as incidents_during_change_window,
    coalesce(iw.resolved_incidents, 0)                          as resolved_incidents,
    coalesce(iw.total_minutes_to_resolve, 0)                    as total_minutes_to_resolve,

    -- Null when the week resolved nothing. There is no average of no numbers.
    iw.avg_minutes_to_resolve,

    -- Null rather than 0% when the week had no incidents.
    case
        when coalesce(iw.incidents_opened, 0) > 0
        then iw.incidents_during_change_window * 100.0 / iw.incidents_opened
    end                                                         as pct_incidents_during_change_window,

    -- The normalisation the current slide is missing: a 200-device site and a
    -- 6-device site are not comparable on raw counts.
    case
        when coalesce(dc.in_service_device_count, 0) > 0
        then coalesce(iw.incidents_opened, 0) * 100.0 / dc.in_service_device_count
    end                                                         as incidents_per_100_in_service_devices,

    tw.peak_utilization_pct_out,
    tw.avg_utilization_pct_out,
    coalesce(tw.monitored_interfaces_with_telemetry, 0)         as monitored_interfaces_with_telemetry,
    coalesce(tw.interface_hours_observed, 0)                    as interface_hours_observed,

    -- Reads the utilization nulls for the consumer: false means no telemetry
    -- for this site-week, not quiet interfaces.
    coalesce(tw.interface_hours_observed, 0) > 0                as has_telemetry,

    -- The first and last weeks of the range are clipped by data availability.
    -- Flagged so a short week is not compared against a full one.
    (
        sw.week_start_date < cast(b.first_activity_ts as date)
        or dateadd('day', 6, sw.week_start_date) > cast(b.last_activity_ts as date)
    )                                                           as is_partial_week

from site_weeks         sw
cross join activity_bounds b
left join device_counts dc
  on  dc.site_code       = sw.site_code
left join incident_weekly  iw
  on  iw.site_code       = sw.site_code
  and iw.week_start_date = sw.week_start_date
left join telemetry_weekly tw
  on  tw.site_code       = sw.site_code
  and tw.week_start_date = sw.week_start_date
