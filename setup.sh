#!/usr/bin/env bash
# One-time setup for the ENS reference project.
#   source setup.sh     (source it, so the exports persist in your shell)

set -u

export SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT:-}"      # e.g. abcdefg-xy12345
export SNOWFLAKE_USER="${SNOWFLAKE_USER:-pat.bates@dbtlabs.com}"
export SNOWFLAKE_ROLE="${SNOWFLAKE_ROLE:-SYSADMIN}"
export SNOWFLAKE_WAREHOUSE="${SNOWFLAKE_WAREHOUSE:-}"

if [ -z "$SNOWFLAKE_ACCOUNT" ] || [ -z "$SNOWFLAKE_WAREHOUSE" ]; then
  echo "Set SNOWFLAKE_ACCOUNT and SNOWFLAKE_WAREHOUSE first:"
  echo "  export SNOWFLAKE_ACCOUNT=<orgname>-<account>"
  echo "  export SNOWFLAKE_WAREHOUSE=<warehouse>"
  return 1 2>/dev/null || exit 1
fi

echo "account:   $SNOWFLAKE_ACCOUNT"
echo "user:      $SNOWFLAKE_USER"
echo "role:      $SNOWFLAKE_ROLE"
echo "warehouse: $SNOWFLAKE_WAREHOUSE"
echo
echo "next:"
echo "  dbt deps"
echo "  dbt debug"
echo "  dbt build --select staging"
