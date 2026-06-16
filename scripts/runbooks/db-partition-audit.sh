#!/usr/bin/env bash

# eoAPI Runbook - Database Partition Audit
#
# Gathers partition statistics across all collections for pgstac tuning.
# Designed to answer: how many collections, how many total partitions,
# what's the partition strategy, and are we over-partitioned?
#
# Prerequisites: kubectl (configured)
# Usage:
#   DB_NS=infra DB_POD=default-default-cn4l-0 bash db-partition-audit.sh

# Guard: refuse to run if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: Run as: bash ${BASH_SOURCE[0]}" >&2
    return 1 2>/dev/null || exit 1
fi

set -euo pipefail

###############################################################################
# CONFIG
###############################################################################
NS="${NS:-data-access}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"
DB_NS="${DB_NS:-}"
DB_POD="${DB_POD:-}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-}"

###############################################################################
# LOGGING
###############################################################################
LOG_DIR="${LOG_DIR:-$HOME/eoapi-loadtest-logs}"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/partition-audit-$(date -u +'%Y%m%d-%H%M%S').log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Logging to: $LOGFILE"

###############################################################################
# DB connection: auto-discover if not provided
###############################################################################
if [[ -z "$DB_POD" ]]; then
    echo "ERROR: DB_POD is required. Example:" >&2
    echo "  DB_NS=infra DB_POD=default-default-cn4l-0 bash $0" >&2
    exit 1
fi

if [[ -z "$DB_NAME" ]]; then
    DB_NAME=$(
        kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- \
            printenv PGDATABASE 2>/dev/null || echo "eoapi"
    )
fi
: "${DB_NS:=$NS}"

echo "DB: $DB_POD (namespace: $DB_NS, user: $DB_USER, db: $DB_NAME)"

run_sql() {
    kubectl exec -n "$DB_NS" "$DB_POD" -- \
        psql -U "$DB_USER" -d "$DB_NAME" -c "$1" 2>&1 \
        | grep -v "^WARNING:.*collation" | grep -v "^DETAIL:" | grep -v "^HINT:"
}

echo ""
echo "=========================================="
echo "  PARTITION AUDIT — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

###############################################################################
# 1. pgstac version
###############################################################################
echo ""
echo "--- 1. pgstac version ---"
run_sql "SELECT version FROM pgstac.migrations ORDER BY datetime DESC LIMIT 1;" || true

###############################################################################
# 2. Collection count and list
###############################################################################
echo ""
echo "--- 2. Collections ---"
run_sql "SELECT count(*) AS total_collections FROM pgstac.collections;" || true

echo ""
run_sql "
SELECT id,
       content->>'title' AS title
FROM pgstac.collections
ORDER BY id;
" || true

###############################################################################
# 3. Items per collection
###############################################################################
echo ""
echo "--- 3. Items per collection ---"
echo "  (Using pgstac partition stats if available, falling back to pg_class estimates)"
run_sql "
SELECT collection, count(*) AS item_count
FROM pgstac.items
GROUP BY collection
ORDER BY count(*) DESC;
" || true

###############################################################################
# 4. Total partition count
###############################################################################
echo ""
echo "--- 4. Total partitions ---"
run_sql "
SELECT count(*) AS total_partitions
FROM pg_inherits pi
JOIN pg_class parent ON pi.inhparent = parent.oid
JOIN pg_namespace pn ON parent.relnamespace = pn.oid
WHERE pn.nspname = 'pgstac'
  AND parent.relname = 'items';
" || true

###############################################################################
# 5. Partitions per collection (estimated from partition naming)
###############################################################################
echo ""
echo "--- 5. Partition breakdown ---"
echo "  Top-level partitions (by collection key):"
run_sql "
SELECT child.relname AS partition,
       pg_size_pretty(pg_total_relation_size(child.oid)) AS total_size,
       child.reltuples::bigint AS estimated_rows
FROM pg_inherits pi
JOIN pg_class parent ON pi.inhparent = parent.oid
JOIN pg_class child ON pi.inhrelid = child.oid
JOIN pg_namespace pn ON parent.relnamespace = pn.oid
WHERE pn.nspname = 'pgstac'
  AND parent.relname = 'items'
ORDER BY child.relname;
" || true

###############################################################################
# 6. Sub-partitions (monthly) per top-level partition
###############################################################################
echo ""
echo "--- 6. Sub-partition counts per collection partition ---"
run_sql "
SELECT p1.relname AS collection_partition,
       count(p2.inhrelid) AS monthly_partitions,
       pg_size_pretty(sum(pg_total_relation_size(sub.oid))) AS total_size,
       sum(sub.reltuples::bigint) AS estimated_rows
FROM pg_inherits p1i
JOIN pg_class parent ON p1i.inhparent = parent.oid
JOIN pg_class p1 ON p1i.inhrelid = p1.oid
JOIN pg_namespace pn ON parent.relnamespace = pn.oid
LEFT JOIN pg_inherits p2 ON p2.inhparent = p1.oid
LEFT JOIN pg_class sub ON p2.inhrelid = sub.oid
WHERE pn.nspname = 'pgstac'
  AND parent.relname = 'items'
GROUP BY p1.relname
ORDER BY count(p2.inhrelid) DESC;
" || true

###############################################################################
# 7. Rows per monthly partition for sentinel-1-nrb
###############################################################################
echo ""
echo "--- 7. sentinel-1-nrb partition detail ---"
echo "  (Monthly partitions with row estimates and sizes)"
run_sql "
WITH nrb_parent AS (
    SELECT child.oid, child.relname
    FROM pg_inherits pi
    JOIN pg_class parent ON pi.inhparent = parent.oid
    JOIN pg_class child ON pi.inhrelid = child.oid
    JOIN pg_namespace pn ON parent.relnamespace = pn.oid
    WHERE pn.nspname = 'pgstac'
      AND parent.relname = 'items'
      AND child.relname LIKE '%_17%'
    LIMIT 1
)
SELECT sub.relname AS partition,
       sub.reltuples::bigint AS estimated_rows,
       pg_size_pretty(pg_relation_size(sub.oid)) AS data_size,
       pg_size_pretty(pg_indexes_size(sub.oid)) AS index_size,
       pg_size_pretty(pg_total_relation_size(sub.oid)) AS total_size
FROM nrb_parent np
JOIN pg_inherits pi ON pi.inhparent = np.oid
JOIN pg_class sub ON pi.inhrelid = sub.oid
ORDER BY sub.relname;
" || true

###############################################################################
# 8. Partition strategy (check constraint expressions)
###############################################################################
echo ""
echo "--- 8. Partition strategy ---"
echo "  (Partition bound expressions for top-level items partitions)"
run_sql "
SELECT c.relname AS partition,
       pg_get_expr(c.relpartbound, c.oid) AS partition_bound
FROM pg_inherits pi
JOIN pg_class parent ON pi.inhparent = parent.oid
JOIN pg_class c ON pi.inhrelid = c.oid
JOIN pg_namespace pn ON parent.relnamespace = pn.oid
WHERE pn.nspname = 'pgstac'
  AND parent.relname = 'items'
ORDER BY c.relname;
" || true

###############################################################################
# 9. pgstac context + timeout settings
###############################################################################
echo ""
echo "--- 9. pgstac settings ---"
run_sql "SELECT * FROM pgstac.pgstac_settings;" || true

echo ""
echo "  Database statement_timeout:"
run_sql "SHOW statement_timeout;" || true

###############################################################################
# 10. Database size overview
###############################################################################
echo ""
echo "--- 10. Database size ---"
run_sql "
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
" || true

run_sql "
SELECT nspname AS schema,
       pg_size_pretty(sum(pg_total_relation_size(c.oid))) AS total_size,
       count(*) AS relations
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE nspname IN ('pgstac', 'public')
GROUP BY nspname
ORDER BY sum(pg_total_relation_size(c.oid)) DESC;
" || true

###############################################################################
# Done
###############################################################################
echo ""
echo "=========================================="
echo "  AUDIT COMPLETE — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "  Full log at: $LOGFILE"
echo "=========================================="
