{#
    DBT-21: Device-attributed incidents at every severity, with change-window
    context.

    fct_incident_telemetry_correlation answers a narrower version of the same
    question: it is scoped to the severities in var('incident_severities'),
    because that is the population the correlation argument is about. The weekly
    site report has to show total incidents and the S1/S2 subset side by side,
    so the attribution join and the change-window join are repeated here across
    the full severity mix rather than reading the narrower mart.

    Incidents that no resolver tier could attribute to a device are dropped.
    They have no device, therefore no site, therefore no row in a per-site
    report. This is stated in the mart documentation too, because the first
    thing a consumer will do is reconcile against the raw incident count.
#}

with attributed as (

    select
        r.incident_number,
        r.device_id,
        i.opened_ts,
        i.resolved_ts,
        i.minutes_to_resolve,
        i.is_open,
        i.incident_severity

    from {{ ref('int_ens__ci_resolved') }} r
    join {{ ref('stg_ens__incident') }}    i using (incident_number)
    where r.device_id is not null

),

-- Same rule as the change_overlap CTE in fct_incident_telemetry_correlation:
-- exact or canonicalised hostname, tested against the effective window so an
-- overrunning change still counts.
change_overlap as (

    select distinct
        a.incident_number,
        true    as opened_during_change_window

    from attributed a
    join {{ ref('stg_ens__device') }} d
      on d.device_id = a.device_id
    join {{ ref('stg_ens__change_request') }} c
      on  c.cmdb_ci_clean in (d.hostname, d.fqdn)
      and a.opened_ts between c.effective_start_ts and c.effective_end_ts

)

select
    a.incident_number,
    a.device_id,
    a.opened_ts,
    a.resolved_ts,
    {{ week_start_monday('a.opened_ts') }}          as opened_week_start_date,
    a.minutes_to_resolve,
    a.is_open,
    a.incident_severity,

    -- The S1/S2 definition stays in dbt_project.yml, shared with the
    -- correlation model, rather than being retyped here.
    a.incident_severity in (
        {%- for severity in var('incident_severities') -%}
        '{{ severity }}'{{ ", " if not loop.last }}
        {%- endfor -%}
    )                                               as is_high_severity,

    coalesce(ch.opened_during_change_window, false)  as opened_during_change_window

from attributed a
left join change_overlap ch using (incident_number)
