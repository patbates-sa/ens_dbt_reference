{{
    config(
        materialized = 'table'
    )
}}

with hours as (

    {{
        dbt.date_spine(
            'hour',
            "dateadd(year, -5, date_trunc('hour', current_timestamp()))",
            "dateadd(day, 30, date_trunc('hour', current_timestamp()))"
        )
    }}

),

final as (

    select cast(date_hour as timestamp_ntz) as date_hour
    from hours

)

select * from final
