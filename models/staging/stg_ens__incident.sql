with source as (

    select * from {{ source('ens', 'ens_incident') }}

),

renamed as (

    select
        incident_number,

        opened_ts,
        resolved_ts,
        closed_ts,
        cast(opened_ts as date)                             as opened_date,
        datediff('minute', opened_ts, resolved_ts)           as minutes_to_resolve,
        resolved_ts is null                                  as is_open,

        severity                                             as incident_severity,
        assignment_group,
        short_description,

        -- The raw dirty key is preserved, and the canonicalised form is derived
        -- once here. Resolution logic lives in int_ens__ci_resolved, not in staging.
        cmdb_ci                                              as cmdb_ci_raw,
        lower(trim(cmdb_ci))                                 as cmdb_ci_clean,

        close_code,
        root_cause_category,
        linked_change_number

    from source

)

select * from renamed
