#!/usr/bin/env bash

# eoAPI Runbook - Database & Application Deep Dive
#
# Investigates remaining unknowns after the initial partition audit:
# where is the statement timeout set, is there a connection pooler,
# what are the actual slow queries, and what are the resource constraints?
#
# Prerequisites: kubectl (configured)
# Usage:
#   DB_NS=infra DB_POD=default-default-cn4l-0 bash db-deep-dive.sh

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
LOGFILE="$LOG_DIR/deep-dive-$(date -u +'%Y%m%d-%H%M%S').log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Logging to: $LOGFILE"

###############################################################################
# DB connection
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
echo "  DEEP DIVE — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

###############################################################################
# 1. Where is the timeout set?
###############################################################################
echo ""
echo "================================================================"
echo "  DATABASE LAYER"
echo "================================================================"

echo ""
echo "--- 1. Statement timeout hunt ---"

echo ""
echo "  Database-level:"
run_sql "SHOW statement_timeout;" || true

echo ""
echo "  Role-level settings (rolconfig):"
run_sql "SELECT rolname, rolconfig FROM pg_roles WHERE rolconfig IS NOT NULL;" || true

echo ""
echo "  Per-database/role overrides:"
run_sql "\drds" || true

echo ""
echo "  App user (eoapi) effective timeout when connecting:"
run_sql "
SELECT d.datname, r.rolname, unnest(s.setconfig) AS setting
FROM pg_db_role_setting s
JOIN pg_database d ON d.oid = s.setdatabase
LEFT JOIN pg_roles r ON r.oid = s.setrole
WHERE d.datname = '$DB_NAME'
   OR s.setdatabase = 0
ORDER BY d.datname, r.rolname;
" || true

###############################################################################
# 2. Connection pooler?
###############################################################################
echo ""
echo "--- 2. Connection pooler check ---"

echo ""
echo "  Services with pooler/bouncer in name (infra namespace):"
kubectl get svc -n "$DB_NS" 2>&1 | grep -iE 'pooler|bouncer|rw|ro' || echo "  (none found)"

echo ""
echo "  Pods with pooler/bouncer in name (infra namespace):"
kubectl get pods -n "$DB_NS" 2>&1 | grep -iE 'pooler|bouncer' || echo "  (none found)"

echo ""
echo "  STAC app DATABASE_URL (what is it actually connecting to?):"
kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- printenv DATABASE_URL 2>/dev/null \
    | sed 's|://[^:]*:[^@]*@|://****:****@|' \
    || echo "  (not set)"

echo ""
echo "  STAC app PGHOST:"
kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- printenv PGHOST 2>/dev/null \
    || echo "  (not set)"

###############################################################################
# 3. PG server tuning
###############################################################################
echo ""
echo "--- 3. PostgreSQL server settings ---"
run_sql "
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'shared_buffers', 'effective_cache_size', 'work_mem',
    'maintenance_work_mem', 'max_connections',
    'max_parallel_workers', 'max_parallel_workers_per_gather',
    'random_page_cost', 'effective_io_concurrency',
    'plan_cache_mode', 'max_locks_per_transaction',
    'jit', 'statement_timeout', 'lock_timeout',
    'idle_in_transaction_session_timeout',
    'wal_level', 'max_wal_size', 'checkpoint_completion_target'
)
ORDER BY name;
" || true

###############################################################################
# 4. pg_stat_statements — actual slow queries
###############################################################################
echo ""
echo "--- 4. Top 15 slowest queries (pg_stat_statements) ---"
run_sql "
SELECT s.calls,
       round(s.mean_exec_time)::int AS mean_ms,
       round(s.max_exec_time)::int AS max_ms,
       round(s.total_exec_time/1000)::int AS total_s,
       s.rows,
       left(s.query, 150) AS query
FROM pg_stat_statements s
JOIN pg_database d ON d.oid = s.dbid
WHERE d.datname = '$DB_NAME'
ORDER BY s.mean_exec_time DESC
LIMIT 15;
" || true

echo ""
echo "  Top 15 by total time:"
run_sql "
SELECT s.calls,
       round(s.mean_exec_time)::int AS mean_ms,
       round(s.total_exec_time/1000)::int AS total_s,
       s.rows,
       left(s.query, 150) AS query
FROM pg_stat_statements s
JOIN pg_database d ON d.oid = s.dbid
WHERE d.datname = '$DB_NAME'
ORDER BY s.total_exec_time DESC
LIMIT 15;
" || true

###############################################################################
# 5. pgstac search function signature
###############################################################################
echo ""
echo "--- 5. pgstac search function ---"
run_sql "\df pgstac.search" || true

echo ""
echo "  pgstac search_query function (if exists):"
run_sql "\df pgstac.search_query" || true

###############################################################################
# 6. Buffer cache hit ratio
###############################################################################
echo ""
echo "--- 6. Buffer cache performance ---"
run_sql "
SELECT
    round(100.0 * sum(blks_hit) / nullif(sum(blks_hit + blks_read), 0), 2) AS cache_hit_pct,
    pg_size_pretty(sum(blks_hit) * 8192) AS cache_hits,
    pg_size_pretty(sum(blks_read) * 8192) AS disk_reads
FROM pg_stat_database
WHERE datname = '$DB_NAME';
" || true

echo ""
echo "  Table I/O for pgstac.items:"
run_sql "
SELECT relname,
       heap_blks_read, heap_blks_hit,
       round(100.0 * heap_blks_hit / nullif(heap_blks_hit + heap_blks_read, 0), 1) AS hit_pct
FROM pg_statio_user_tables
WHERE schemaname = 'pgstac' AND relname = 'items';
" || true

echo ""
echo "  Index I/O for items partitions (top 10 by reads):"
run_sql "
SELECT relname, indexrelname,
       idx_blks_read, idx_blks_hit,
       round(100.0 * idx_blks_hit / nullif(idx_blks_hit + idx_blks_read, 0), 1) AS hit_pct
FROM pg_statio_user_indexes
WHERE schemaname = 'pgstac' AND relname LIKE '_items_%'
ORDER BY idx_blks_read DESC
LIMIT 10;
" || true

###############################################################################
# 7. Active connections breakdown
###############################################################################
echo ""
echo "--- 7. Connection breakdown ---"
run_sql "
SELECT usename, state, count(*),
       string_agg(DISTINCT client_addr::text, ', ') AS client_addrs
FROM pg_stat_activity
WHERE datname = '$DB_NAME'
GROUP BY usename, state
ORDER BY count DESC;
" || true

run_sql "SELECT current_setting('max_connections') AS max_connections;" || true

###############################################################################
echo ""
echo "================================================================"
echo "  APPLICATION LAYER"
echo "================================================================"

###############################################################################
# 8. STAC app settings
###############################################################################
echo ""
echo "--- 8. STAC app configuration ---"
echo ""
echo "  Timeout / concurrency / worker env vars:"
kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- env 2>/dev/null \
    | grep -iE 'timeout|concurrency|worker|gunicorn|uvicorn|db_.*conn|db_.*size|web_conc' \
    | sort \
    || echo "  (could not read env)"

echo ""
echo "  Gunicorn/uvicorn config file:"
kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- \
    cat /app/gunicorn.conf.py 2>/dev/null \
    || kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- \
    cat /app/gunicorn_conf.py 2>/dev/null \
    || echo "  (no gunicorn config file found)"

echo ""
echo "  Process list inside STAC pod:"
kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- \
    ps aux 2>/dev/null | head -20 \
    || echo "  (ps not available)"

###############################################################################
# 9. Auth-proxy settings
###############################################################################
echo ""
echo "--- 9. Auth-proxy configuration ---"
echo ""
echo "  Timeout / upstream env vars:"
kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac-auth-proxy" -- env 2>/dev/null \
    | grep -iE 'timeout|upstream|backend|log_level|workers|forwarded' \
    | sort \
    || echo "  (could not read env)"

###############################################################################
# 10. CNPG cluster resources
###############################################################################
echo ""
echo "================================================================"
echo "  INFRASTRUCTURE LAYER"
echo "================================================================"

echo ""
echo "--- 10. DB pod resources ---"
echo ""
echo "  Resource requests/limits:"
kubectl get pod -n "$DB_NS" "$DB_POD" -o jsonpath='{range .spec.containers[*]}{.name}{"\t"}{.resources}{"\n"}{end}' 2>/dev/null \
    || echo "  (could not read pod spec)"

echo ""
echo ""
echo "  Current usage:"
kubectl top pod -n "$DB_NS" "$DB_POD" 2>/dev/null || echo "  (metrics not available)"

echo ""
echo "  STAC pod resources:"
kubectl top pods -n "$NS" 2>/dev/null \
    | grep -iE 'NAME|stac|auth-proxy' \
    || echo "  (metrics not available)"

echo ""
echo "  DB pod uptime / restarts:"
kubectl get pod -n "$DB_NS" "$DB_POD" -o wide 2>/dev/null | head -2 || true

###############################################################################
# 11. CNPG cluster status
###############################################################################
echo ""
echo "--- 11. CNPG cluster status ---"
echo ""
echo "  Cluster custom resource:"
kubectl get clusters.postgresql.cnpg.io -n "$DB_NS" 2>/dev/null \
    || kubectl get postgresclusters -n "$DB_NS" 2>/dev/null \
    || echo "  (no CNPG cluster resource found)"

echo ""
echo "  Replication status:"
run_sql "
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
" || true

###############################################################################
# Done
###############################################################################
echo ""
echo "=========================================="
echo "  DEEP DIVE COMPLETE — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "  Full log at: $LOGFILE"
echo "=========================================="
