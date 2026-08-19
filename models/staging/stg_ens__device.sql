with source as (

    select * from {{ source('ens', 'ens_device') }}

),

renamed as (

    select
        device_id,

        -- Canonicalised once, here, so no downstream model re-implements it.
        -- The notebook did lower(trim(...)) inline in the join.
        lower(trim(hostname))   as hostname,
        lower(trim(fqdn))       as fqdn,

        device_class,
        vendor,
        model,
        site_code,
        environment,
        owning_team,
        lifecycle_state,

        install_date,
        last_modified_ts

    from source

)

select * from renamed
