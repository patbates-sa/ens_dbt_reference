{#
    What the notebook was trying to be.

    For each in-scope incident: what did the network look like in the hour
    before it opened. This is the join the customer hand-writes today, and
    the model to build live.

    Three things worth saying while it builds:
      1. The interval join between a point-in-time incident and a five-minute
         time series is the part he does by hand.
      2. opened_during_change_window is a one-line answer to a question his
         organisation asks constantly.
      3. The incremental predicate means tomorrow's run touches new incidents
         only.
#}

{{ config(
    materialized = 'incremental',
    unique_key = 'incident_number',
    incremental_strategy = 'merge',
    cluster_by = ['opened_date']
) }}

with incidents as (

    select
        r.incident_number,
        r.device_id,
        r.match_method,
        i.opened_ts,
        i.resolved_ts,
        i.opened_date,
        i.minutes_to_resolve,
        i.is_open,
        i.incident_severity,
        i.assignment_group,
        i.short_description

    from {{ ref('int_ens__ci_resolved') }} r
    join {{ ref('stg_ens__incident') }}    i using (incident_number)

    -- Unresolved incidents are excluded here, not silently dropped by a join.
    -- The resolution rate is measured and tested upstream.
    where r.device_id is not null
      and i.incident_severity in (
          {%- for severity in var('incident_severities') -%}
          '{{ severity }}'{{ ", " if not loop.last }}
          {%- endfor -%}
      )

    {% if is_incremental() %}
      and i.opened_ts > (select max(opened_ts) from {{ this }})
    {% endif %}

),

-- The lookback window. Was a Python literal with a comment; now a var.
-- Changing it is a one-line edit that re-runs in seconds.
precursor_telemetry as (

    select
        inc.incident_number,
        avg(m.utilization_pct_out)              as avg_util_out_prior_window,
        max(m.utilization_pct_out)              as peak_util_out_prior_window,
        sum(m.in_errors + m.out_errors)         as errors_prior_window,
        max(m.latency_ms_p95)                   as peak_latency_p95_prior_window,
        max(m.packet_loss_pct)                  as peak_loss_prior_window,
        count_if(not m.is_successful_poll)      as failed_polls_prior_window,
        count(distinct ifc.interface_id)        as monitored_interfaces_observed

    from incidents inc
    join {{ ref('stg_ens__interface') }} ifc
      on  ifc.device_id = inc.device_id
      and ifc.is_monitored
    join {{ ref('stg_ens__interface_metric_5m') }} m
      on  m.interface_id = ifc.interface_id
      and m.metric_ts >= dateadd('hour', -{{ var('precursor_lookback_hours') }}, inc.opened_ts)
      and m.metric_ts <  inc.opened_ts
    group by 1

),

precursor_syslog as (

    select
        inc.incident_number,
        count(*)                            as syslog_events_prior_window,
        count_if(s.is_critical_event)        as critical_events_prior_window,
        min(s.syslog_severity)               as worst_severity_prior_window

    from incidents inc
    join {{ ref('stg_ens__syslog_event') }} s
      on  s.device_id = inc.device_id
      and s.event_ts >= dateadd('hour', -{{ var('precursor_lookback_hours') }}, inc.opened_ts)
      and s.event_ts <  inc.opened_ts
    group by 1

),

-- Change-side CI resolution is deliberately simpler than the incident side:
-- exact and canonicalised hostname only. Unifying both sides behind one
-- crosswalk is a good thing to offer to do live if he asks.
change_overlap as (

    select
        inc.incident_number,
        max(c.change_number)    as overlapping_change_number,
        max(c.change_type)      as overlapping_change_type,
        max(c.change_risk)      as overlapping_change_risk
    from incidents inc
    join {{ ref('stg_ens__device') }} d
      on d.device_id = inc.device_id
    join {{ ref('stg_ens__change_request') }} c
      on  c.cmdb_ci_clean in (d.hostname, d.fqdn)
      and inc.opened_ts between c.effective_start_ts and c.effective_end_ts
    group by 1

)

select
    inc.incident_number,
    inc.device_id,
    inc.match_method,
    inc.opened_ts,
    inc.resolved_ts,
    inc.opened_date,
    inc.minutes_to_resolve,
    inc.is_open,
    inc.incident_severity,
    inc.assignment_group,
    inc.short_description,

    t.avg_util_out_prior_window,
    t.peak_util_out_prior_window,
    t.errors_prior_window,
    t.peak_latency_p95_prior_window,
    t.peak_loss_prior_window,
    t.failed_polls_prior_window,
    t.monitored_interfaces_observed,

    s.syslog_events_prior_window,
    s.critical_events_prior_window,
    s.worst_severity_prior_window,

    ch.overlapping_change_number,
    ch.overlapping_change_type,
    ch.overlapping_change_risk,
    ch.overlapping_change_number is not null    as opened_during_change_window,

    -- The generator injects a real precursor signal: utilization runs ~1.86x
    -- baseline in the hour before a resolvable incident. This flag makes that
    -- visible without claiming it is predictive.
    t.peak_util_out_prior_window >= 80          as had_elevated_utilization

from incidents inc
left join precursor_telemetry t  using (incident_number)
left join precursor_syslog    s  using (incident_number)
left join change_overlap      ch using (incident_number)
