{#
    The model the whole demo turns on.

    The notebook resolved ServiceNow's cmdb_ci to a device with two branches:
    an exact hostname match and a lower(trim(...)) match. Everything else fell
    on the floor, and the notebook printed the ratio with a comment saying
    everyone knew it was bad.

    This version handles five patterns as explicit precedence tiers. The
    precedence order IS a business rule, which is the argument being made:
    a business rule in version-controlled SQL, with a test on it.

    Structured as tier CTEs unioned rather than four OR'd predicates. The OR
    form -- two of them LIKE against a 1,200-row dimension -- plans as a
    cross-join and filter in Snowflake.

    Measured against generated data at full scale: 86.00% resolved.
    The four-tier version without asset_tag measures 78.19% and fails the
    resolution-rate test, which is exactly what the broken branch demonstrates.
#}

with incidents as (

    select
        incident_number,
        opened_ts,
        cmdb_ci_raw,
        cmdb_ci_clean,
        lower(short_description) as short_description_clean
    from {{ ref('stg_ens__incident') }}

),

devices as (

    select
        device_id,
        hostname,
        fqdn
    from {{ ref('stg_ens__device') }}

),

-- Tier 1 -- exact canonical hostname. ~47% of rows.
tier_exact as (

    select i.incident_number, d.device_id, 'exact' as match_method, 1 as tier
    from incidents i
    join devices  d on i.cmdb_ci_clean = d.hostname

),

-- Tier 2 -- fully qualified name. ~12% of rows.
tier_fqdn as (

    select i.incident_number, d.device_id, 'fqdn' as match_method, 2 as tier
    from incidents i
    join devices  d on i.cmdb_ci_clean = d.fqdn

),

-- Tier 3 -- site-prefixed asset tag, e.g. "NYP / DEV-004821". ~8% of rows.
-- This is the tier the notebook was missing entirely. It carries device_id
-- rather than hostname, so no amount of hostname matching finds it.
tier_asset_tag as (

    select
        i.incident_number,
        d.device_id,
        'asset_tag' as match_method,
        3 as tier
    from incidents i
    join devices  d
      on regexp_substr(upper(i.cmdb_ci_raw), 'DEV-[0-9]+') = d.device_id
    where regexp_substr(upper(i.cmdb_ci_raw), 'DEV-[0-9]+') is not null

),

-- Tier 4 -- hostname embedded in a longer string. ~10% of rows, mostly
-- case and whitespace variance that survives canonicalisation.
tier_embedded as (

    select i.incident_number, d.device_id, 'embedded' as match_method, 4 as tier
    from incidents i
    join devices  d on i.cmdb_ci_clean like '%' || d.hostname || '%'

),

-- Tier 5 -- cmdb_ci is null and the device is named only in free text.
-- ~8% of rows. Hostname indices are capped at two digits in the generator
-- so no hostname is a substring of another; without that this tier would
-- be non-deterministic.
tier_description as (

    select i.incident_number, d.device_id, 'description' as match_method, 5 as tier
    from incidents i
    join devices  d on i.short_description_clean like '%' || d.hostname || '%'
    where i.cmdb_ci_clean is null or i.cmdb_ci_clean = ''

),

all_matches as (

    select * from tier_exact
    union all select * from tier_fqdn
    union all select * from tier_asset_tag
    union all select * from tier_embedded
    union all select * from tier_description

),

-- Fuzzy matching can hit several devices for one incident. Precedence
-- decides. This is the line to pause on live.
best_match as (

    select incident_number, device_id, match_method
    from all_matches
    qualify row_number() over (
        partition by incident_number
        order by tier, device_id
    ) = 1

)

select
    i.incident_number,
    i.opened_ts,
    i.cmdb_ci_raw,
    m.device_id,
    coalesce(m.match_method, 'unresolved')  as match_method,
    m.device_id is not null                 as is_resolved

from incidents i
left join best_match m using (incident_number)
