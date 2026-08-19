-- DBT-21: the acceptance criterion that a missing row cannot be read as an
-- improvement. Every site must appear in every week in the reporting range.
-- Fails with the site-weeks that are absent.

with sites as (

    select site_code from {{ ref('stg_ens__site') }}

),

weeks as (

    select distinct week_start_date from {{ ref('fct_site_reliability_weekly') }}

),

expected as (

    select s.site_code, w.week_start_date
    from sites s
    cross join weeks w

)

select
    e.site_code,
    e.week_start_date
from expected e
left join {{ ref('fct_site_reliability_weekly') }} f
  on  f.site_code       = e.site_code
  and f.week_start_date = e.week_start_date
where f.site_code is null
