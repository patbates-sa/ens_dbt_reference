with source as (

    select * from {{ source('ens', 'ens_device_health_5m') }}

),

renamed as (

    select
        device_id,
        metric_ts,
        cast(metric_ts as date)     as metric_date,

        cpu_pct,
        memory_pct,
        temperature_c,
        fan_state,
        uptime_seconds,
        bgp_peers_established

    from source

)

select * from renamed
