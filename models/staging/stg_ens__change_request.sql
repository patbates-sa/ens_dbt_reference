with source as (

    select * from {{ source('ens', 'ens_change_request') }}

),

renamed as (

    select
        change_number,

        planned_start_ts,
        planned_end_ts,
        actual_start_ts,
        actual_end_ts,

        -- Changes overrun. The effective window is what an incident should be
        -- tested against, so it is defined once rather than per consumer.
        coalesce(actual_start_ts, planned_start_ts)          as effective_start_ts,
        coalesce(actual_end_ts,   planned_end_ts)            as effective_end_ts,

        risk                                                 as change_risk,
        change_type,
        implementer_group,
        outcome                                              as change_outcome,

        cmdb_ci                                              as cmdb_ci_raw,
        lower(trim(cmdb_ci))                                 as cmdb_ci_clean

    from source

)

select * from renamed
