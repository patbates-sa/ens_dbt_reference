with resolution_rate as (

    select
        coalesce(
            count(device_id) * 1.0 / nullif(count(*), 0),
            0
        ) as actual_resolution_rate
    from {{ ref('int_ens__ci_resolved') }}

)

select
    actual_resolution_rate,
    {{ var('min_ci_resolution_rate') }} as minimum_resolution_rate
from resolution_rate
where actual_resolution_rate < {{ var('min_ci_resolution_rate') }}
