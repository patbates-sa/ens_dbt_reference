{{ config(
    materialized = 'incremental',
    unique_key = ['interface_id', 'metric_hour'],
    incremental_strategy = 'merge',
    cluster_by = ['metric_hour']
) }}

with hourly as (

    select * from {{ ref('int_ens__interface_metric_hourly') }}

    {% if is_incremental() %}
      where metric_hour >= dateadd('hour', -3, (select max(metric_hour) from {{ this }}))
    {% endif %}

),

interfaces as (

    select
        interface_id,
        device_id,
        interface_name,
        interface_description,
        speed_mbps,
        circuit_id
    from {{ ref('stg_ens__interface') }}

),

devices as (

    select
        device_id,
        hostname,
        device_class,
        vendor,
        environment,
        owning_team,
        site_code,
        site_region
    from {{ ref('dim_device') }}

)

select
    h.interface_id,
    h.metric_hour,
    h.metric_date,

    i.device_id,
    i.interface_name,
    i.speed_mbps,
    i.circuit_id,

    d.hostname,
    d.device_class,
    d.vendor,
    d.environment,
    d.owning_team,
    d.site_code,
    d.site_region,

    h.poll_count,
    h.failed_poll_count,
    h.avg_utilization_pct_in,
    h.avg_utilization_pct_out,
    h.peak_utilization_pct_out,
    h.total_errors,
    h.total_discards,
    h.avg_latency_ms_p50,
    h.peak_latency_ms_p95,
    h.peak_packet_loss_pct

from hourly     h
join interfaces i using (interface_id)
join devices    d using (device_id)
