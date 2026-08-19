with source as (

    select * from {{ source('ens', 'ens_site') }}

),

renamed as (

    select
        site_code,
        city,
        region,
        country,
        tier          as site_tier,
        timezone      as site_timezone

    from source

)

select * from renamed
