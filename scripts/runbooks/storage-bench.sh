#!/usr/bin/env bash

# eoAPI Runbook - Storage & I/O Diagnostics
#
# Checks Kubernetes storage configuration and benchmarks disk performance
# on the database PV. Also captures PostgreSQL I/O statistics to identify
# whether storage is a bottleneck.
#
# Prerequisites: kubectl (configured)
# Usage:
#   DB_NS=infra DB_POD=default-default-cn4l-0 bash storage-bench.sh

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
LOGFILE="$LOG_DIR/storage-bench-$(date -u +'%Y%m%d-%H%M%S').log"
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

run_in_pod() {
    kubectl exec -n "$DB_NS" "$DB_POD" -- sh -c "$1" 2>&1
}

echo ""
echo "=========================================="
echo "  STORAGE & I/O DIAGNOSTICS — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

###############################################################################
echo ""
echo "================================================================"
echo "  KUBERNETES STORAGE CONFIGURATION"
echo "================================================================"

###############################################################################
# 1. PVCs attached to the DB pod
###############################################################################
echo ""
echo "--- 1. PVCs for DB pod ---"
kubectl get pod -n "$DB_NS" "$DB_POD" -o jsonpath='{range .spec.volumes[*]}{.name}{"\t"}{.persistentVolumeClaim.claimName}{"\n"}{end}' 2>/dev/null \
    | grep -v "^$" || echo "  (no PVCs found)"

echo ""
echo "  PVC details:"
for pvc in $(kubectl get pod -n "$DB_NS" "$DB_POD" -o jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}' 2>/dev/null | grep -v "^$"); do
    echo ""
    echo "  --- $pvc ---"
    kubectl get pvc -n "$DB_NS" "$pvc" -o wide 2>/dev/null || echo "  (could not get PVC)"
done

###############################################################################
# 2. Storage class
###############################################################################
echo ""
echo "--- 2. Storage class ---"
for pvc in $(kubectl get pod -n "$DB_NS" "$DB_POD" -o jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}' 2>/dev/null | grep -v "^$"); do
    SC=$(kubectl get pvc -n "$DB_NS" "$pvc" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
    if [[ -n "$SC" ]]; then
        echo "  PVC $pvc uses StorageClass: $SC"
        kubectl get storageclass "$SC" -o wide 2>/dev/null || true
        echo ""
        echo "  Provisioner details:"
        kubectl get storageclass "$SC" -o jsonpath='{.provisioner}{"\n"}' 2>/dev/null || true
        kubectl get storageclass "$SC" -o jsonpath='{.parameters}' 2>/dev/null | python3 -m json.tool 2>/dev/null || true
    fi
done

###############################################################################
# 3. Volume mount points inside the pod
###############################################################################
echo ""
echo "--- 3. Mount points inside DB pod ---"
run_in_pod "df -hT /pgdata 2>/dev/null || df -hT /var/lib/postgresql 2>/dev/null || df -hT / 2>/dev/null" || true

echo ""
echo "  All mounts:"
run_in_pod "mount | grep -E 'pgdata|postgresql|pvc'" || echo "  (no pgdata mounts found)"

###############################################################################
echo ""
echo "================================================================"
echo "  DISK I/O BENCHMARKS"
echo "================================================================"

###############################################################################
# 4. dd sequential write test
###############################################################################
echo ""
echo "--- 4. Sequential write (dd) ---"
echo "  Writing 256MB to /tmp in DB pod..."
run_in_pod "dd if=/dev/zero of=/tmp/bench_seq_write bs=1M count=256 conv=fdatasync 2>&1; rm -f /tmp/bench_seq_write" || true

###############################################################################
# 5. dd sequential write on PG data directory
###############################################################################
echo ""
echo "--- 5. Sequential write on PG data volume ---"

PGDATA=$(run_in_pod "echo \$PGDATA" 2>/dev/null | tr -d '[:space:]')
if [[ -z "$PGDATA" ]]; then
    PGDATA=$(run_in_pod "ls -d /pgdata/pg* 2>/dev/null | head -1" | tr -d '[:space:]')
fi
: "${PGDATA:=/pgdata}"
echo "  PGDATA: $PGDATA"
echo "  Writing 256MB to $PGDATA/bench_test..."
run_in_pod "dd if=/dev/zero of=$PGDATA/bench_test bs=1M count=256 conv=fdatasync 2>&1; rm -f $PGDATA/bench_test" || true

###############################################################################
# 6. Random I/O (small block, simulates index reads)
###############################################################################
echo ""
echo "--- 6. Random read/write (small block, simulates DB I/O) ---"
echo "  Writing 10,000 x 8KB blocks (PG page size)..."
run_in_pod "dd if=/dev/urandom of=$PGDATA/bench_random bs=8192 count=10000 conv=fdatasync 2>&1; rm -f $PGDATA/bench_random" || true

###############################################################################
# 7. fsync latency test
###############################################################################
echo ""
echo "--- 7. fsync latency ---"
echo "  pg_test_fsync (if available):"
run_in_pod "pg_test_fsync 2>&1 | head -40" || echo "  (pg_test_fsync not available — install postgresql-contrib)"

###############################################################################
echo ""
echo "================================================================"
echo "  POSTGRESQL I/O STATISTICS"
echo "================================================================"

###############################################################################
# 8. bgwriter + checkpoint stats
###############################################################################
echo ""
echo "--- 8. Background writer & checkpoint stats ---"
run_sql "
SELECT checkpoints_timed, checkpoints_req,
       pg_size_pretty(buffers_checkpoint * 8192) AS checkpoint_written,
       pg_size_pretty(buffers_clean * 8192) AS bgwriter_written,
       pg_size_pretty(buffers_backend * 8192) AS backend_written,
       maxwritten_clean AS bgwriter_stops,
       round(checkpoint_write_time/1000) AS chkpt_write_s,
       round(checkpoint_sync_time/1000) AS chkpt_sync_s
FROM pg_stat_bgwriter;
" || true

###############################################################################
# 9. Buffer cache vs disk reads
###############################################################################
echo ""
echo "--- 9. Buffer cache hit ratio ---"
run_sql "
SELECT
    round(100.0 * sum(blks_hit) / nullif(sum(blks_hit + blks_read), 0), 2) AS cache_hit_pct,
    pg_size_pretty(sum(blks_hit) * 8192) AS cache_hits,
    pg_size_pretty(sum(blks_read) * 8192) AS disk_reads
FROM pg_stat_database
WHERE datname = '$DB_NAME';
" || true

###############################################################################
# 10. Largest tables — cache vs disk
###############################################################################
echo ""
echo "--- 10. Top tables by disk reads ---"
run_sql "
SELECT schemaname, relname,
       heap_blks_read AS disk_reads,
       heap_blks_hit AS cache_hits,
       CASE WHEN heap_blks_hit + heap_blks_read > 0
           THEN round(100.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 1)
           ELSE 0
       END AS hit_pct,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_statio_user_tables
WHERE schemaname = 'pgstac'
ORDER BY heap_blks_read DESC
LIMIT 15;
" || true

###############################################################################
# 11. WAL generation rate
###############################################################################
echo ""
echo "--- 11. WAL statistics ---"
run_sql "
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')) AS total_wal_generated;
" || true

run_sql "SHOW wal_level;" || true
run_sql "SHOW max_wal_size;" || true
run_sql "SHOW min_wal_size;" || true

echo ""
echo "  WAL directory size:"
run_in_pod "du -sh $PGDATA/pg_wal 2>/dev/null || du -sh /pgdata/*/pg_wal 2>/dev/null" || true

###############################################################################
# 12. Temp file usage (spilling to disk)
###############################################################################
echo ""
echo "--- 12. Temp file usage (queries spilling to disk) ---"
run_sql "
SELECT datname,
       temp_files AS temp_file_count,
       pg_size_pretty(temp_bytes) AS temp_bytes_written
FROM pg_stat_database
WHERE datname = '$DB_NAME';
" || true

###############################################################################
# 13. shared_buffers vs dataset size
###############################################################################
echo ""
echo "--- 13. Memory vs data ratio ---"
run_sql "
SELECT current_setting('shared_buffers') AS shared_buffers,
       pg_size_pretty(pg_database_size(current_database())) AS db_size,
       current_setting('effective_cache_size') AS effective_cache_size,
       current_setting('work_mem') AS work_mem;
" || true

###############################################################################
# Done
###############################################################################
echo ""
echo "=========================================="
echo "  STORAGE BENCH COMPLETE — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "  Full log at: $LOGFILE"
echo "=========================================="
echo ""
echo "Key things to look for:"
echo "  - Step 2:  Is the StorageClass using local SSD, network block (Cinder/EBS), or NFS?"
echo "  - Step 5:  Sequential write < 100 MB/s on the PG volume → storage is slow"
echo "  - Step 7:  fsync latency > 1ms → impacts WAL commit performance"
echo "  - Step 8:  High buffers_backend → backends doing their own writes (shared_buffers too small)"
echo "  - Step 9:  Cache hit < 99% → working set doesn't fit in shared_buffers"
echo "  - Step 10: Tables with low hit_pct → candidates for more memory or partitioning changes"
echo "  - Step 12: High temp_bytes → queries spilling to disk (raise work_mem)"
echo "  - Step 13: shared_buffers << db_size → likely evicting hot pages"
