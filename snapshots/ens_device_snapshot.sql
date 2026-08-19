{#
    Devices move teams and get decommissioned. An incident raised last quarter
    should resolve against inventory as it was, not as it is. Two-minute build
    that answers a question network teams live with.
#}

{% snapshot ens_device_snapshot %}

{{ config(
    target_schema = 'snapshots',
    unique_key = 'device_id',
    strategy = 'check',
    check_cols = ['lifecycle_state', 'owning_team', 'site_code']
) }}

select
    device_id,
    hostname,
    device_class,
    vendor,
    site_code,
    environment,
    owning_team,
    lifecycle_state,
    last_modified_ts
from {{ source('ens', 'ens_device') }}

{% endsnapshot %}
