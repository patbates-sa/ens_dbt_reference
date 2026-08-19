with source as (

    select * from {{ source('ens', 'ens_syslog_event') }}

),

renamed as (

    select
        event_id,
        device_id,
        event_ts,

        facility,
        severity                        as syslog_severity,
        severity <= 3                   as is_critical_event,

        mnemonic,
        raw_message

    from source

)

select * from renamed
