# Pre-session verification

Run in order. Each step has an expected result — if it does not match, stop there.

## 1. Connection

```bash
dbt deps
dbt debug
```

Expect `All checks passed!`. If SSO opens a browser tab, that is `authenticator: externalbrowser` working.

## 2. Staging

```bash
dbt build --select staging
```

Expect 9 models and roughly 25 tests, all pass. Failures here are almost always
a column-name mismatch between the generated CSVs and `_ens__sources.yml` — check
the actual columns with `describe table ENS_SANDBOX.RAW.ENS_INCIDENT;` and fix the
staging model rather than the source YAML.

## 3. The resolver — the number that matters

```bash
dbt build --select int_ens__ci_resolved
```

Expect `ci_resolution_rate_at_least_80_pct` to PASS. To see the value:

```sql
select
    count(*)                                     as incidents,
    count(device_id)                             as resolved,
    round(count(device_id) * 100.0 / count(*), 2) as pct,
    count(*) - count(device_id)                  as unresolved
from ENS_SANDBOX.DEV_intermediate.int_ens__ci_resolved;
```

Expect ~86%. The validation report confirms 86.00% resolvable in the data, so a
materially lower number means the resolver is dropping a tier it should catch.

Tier breakdown, which is worth having on hand because it is a likely question:

```sql
select match_method, count(*) as n,
       round(count(*) * 100.0 / sum(count(*)) over (), 2) as pct
from ENS_SANDBOX.DEV_intermediate.int_ens__ci_resolved
group by 1 order by 2 desc;
```

Expect roughly: exact 47%, fqdn 13%, case/ws folded into exact or embedded ~10%,
asset_tag 8%, description 8%, unresolved 14%.

## 4. The centrepiece

```bash
dbt build --select +fct_incident_telemetry_correlation
```

Then confirm the telemetry coverage matches what the notebook produced:

```sql
select
    count(*)                                        as rows_total,
    count_if(peak_util_out_prior_window is not null) as with_telemetry,
    round(count_if(peak_util_out_prior_window is not null) * 100.0 / count(*), 1) as pct_with_telemetry
from ENS_SANDBOX.DEV_marts.fct_incident_telemetry_correlation;
```

Expect ~77% with telemetry, consistent with the notebook run. The residual is
incidents before the telemetry window plus devices with no monitored interfaces.

Sanity-check the precursor signal is actually visible, since this is what the
segment points at:

```sql
select
    had_elevated_utilization,
    count(*)                            as incidents,
    round(avg(avg_util_out_prior_window), 1) as avg_util,
    round(avg(errors_prior_window), 0)       as avg_errors
from ENS_SANDBOX.DEV_marts.fct_incident_telemetry_correlation
where peak_util_out_prior_window is not null
group by 1;
```

## 5. The incremental gap — the cost argument

```bash
dbt run --select int_ens__interface_metric_hourly --full-refresh   # time this
dbt run --select int_ens__interface_metric_hourly                  # time this
```

Write both numbers down. The ratio is the only quantified claim in the segment,
and it should be your number rather than a slide's.

## 6. The broken branch

```bash
git checkout -b demo/broken-resolver
# delete the tier_asset_tag CTE and its "union all select * from tier_asset_tag" line
dbt build --select int_ens__ci_resolved
# expect: FAIL at ~78%
git commit -am "break resolver for demo"
git checkout main
dbt build --select int_ens__ci_resolved   # confirm main still passes
```

Verify the failure tonight. A test that does not fail on cue is worse than not
showing one.

## 7. Docs and lineage

```bash
dbt docs generate
```

Needed for column-level lineage in the catalog. Without a `docs generate` the
lineage view is incomplete, which would undercut the segment that depends on it.

## 8. Semantic layer

```bash
dbt parse
```

Confirms the semantic models and metrics compile. Querying metrics requires the
Semantic Layer configured in dbt platform — if that is not set up for this
project, plan to show the YAML and the DAG rather than a live metric query, and
say that plainly rather than improvising.
