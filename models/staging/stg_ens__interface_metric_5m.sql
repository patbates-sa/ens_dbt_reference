with source as (

    select * from {{ source('ens', 'ens_interface_metric_5m') }}

),

renamed as (

    select
        interface_id,
        metric_ts,
        cast(metric_ts as date)     as metric_date,

        in_octets,
        out_octets,
        in_errors,
        out_errors,
        in_discards,
        out_discards,

        utilization_pct_in,
        utilization_pct_out,
        latency_ms_p50,
        latency_ms_p95,
        packet_loss_pct,

        poll_status,
        poll_status = 'ok'          as is_successful_poll

    from source

)

select * from renamed
