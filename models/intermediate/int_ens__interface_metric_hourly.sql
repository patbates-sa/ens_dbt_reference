{#
    The cost argument, made concrete.

    Rolls ~9.7M five-minute rows to hourly, incrementally. Downstream models
    hit this rather than raw telemetry. Run it twice in the session: the second
    run touches only new partitions, which is where the hour-becomes-three-
    minutes claim gets cashed as a measurement rather than a slide.
#}

{{ config(
    materialized = 'incremental',
    unique_key = ['interface_id', 'metric_hour'],
    incremental_strategy = 'merge',
    cluster_by = ['metric_hour']
) }}

with metrics as (

    select * from {{ ref('stg_ens__interface_metric_5m') }}

    {% if is_incremental() %}
      -- Only the window that could still change. One line replaces the
      -- notebook's full rebuild.
      where metric_ts >= dateadd('hour', -3, (select max(metric_hour) from {{ this }}))
    {% endif %}

),

hourly as (

    select
        interface_id,
        date_trunc('hour', metric_ts)                as metric_hour,
        cast(metric_ts as date)                      as metric_date,

        count(*)                                     as poll_count,
        count_if(not is_successful_poll)             as failed_poll_count,

        avg(utilization_pct_in)                      as avg_utilization_pct_in,
        avg(utilization_pct_out)                     as avg_utilization_pct_out,
        max(utilization_pct_out)                     as peak_utilization_pct_out,

        sum(in_errors + out_errors)                  as total_errors,
        sum(in_discards + out_discards)              as total_discards,

        avg(latency_ms_p50)                          as avg_latency_ms_p50,
        max(latency_ms_p95)                          as peak_latency_ms_p95,
        max(packet_loss_pct)                         as peak_packet_loss_pct

    from metrics
    group by 1, 2, 3

)

select * from hourly
