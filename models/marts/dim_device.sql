with devices as (

    select * from {{ ref('stg_ens__device') }}

),

sites as (

    select * from {{ ref('stg_ens__site') }}

),

interface_counts as (

    select
        device_id,
        count(*)                            as interface_count,
        count_if(is_monitored)              as monitored_interface_count
    from {{ ref('stg_ens__interface') }}
    group by 1

)

select
    d.device_id,
    d.hostname,
    d.fqdn,
    d.device_class,
    d.vendor,
    d.model,
    d.environment,
    d.owning_team,
    d.lifecycle_state,
    d.install_date,

    d.site_code,
    s.city                                  as site_city,
    s.region                                as site_region,
    s.country                               as site_country,
    s.site_tier,
    s.site_timezone,

    coalesce(i.interface_count, 0)           as interface_count,
    coalesce(i.monitored_interface_count, 0) as monitored_interface_count,
    coalesce(i.monitored_interface_count, 0) > 0 as is_monitored_device

from devices d
left join sites            s using (site_code)
left join interface_counts i using (device_id)
