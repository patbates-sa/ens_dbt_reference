with source as (

    select * from {{ source('ens', 'ens_jira_issue') }}

),

renamed as (

    select
        issue_key,
        issue_type,
        summary,
        status,

        created_ts,
        resolved_ts,

        assignee,
        epic_key,
        component,
        linked_incident_number

    from source

)

select * from renamed
