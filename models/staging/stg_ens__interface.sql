with source as (

    select * from {{ source('ens', 'ens_interface') }}

),

renamed as (

    select
        interface_id,
        device_id,
        if_name         as interface_name,

        -- Empty ~42% of the time in the source. Nullified so downstream
        -- coalesce logic is explicit rather than accidental.
        nullif(trim(if_description), '')  as interface_description,

        speed_mbps,
        is_monitored,
        circuit_id

    from source

)

select * from renamed
