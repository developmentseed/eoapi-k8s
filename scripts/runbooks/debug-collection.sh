#!/usr/bin/env bash

# eoAPI Runbook - Collection Performance Debugging
#
# Diagnoses why a specific STAC collection is slow or returning errors.
# Designed for large collections (millions of items) where /items may
# timeout or return 500s.  All output goes to both the terminal and a
# timestamped log file under $LOG_DIR.
#
# Prerequisites: kubectl (configured), curl, python3
# Usage:
#   bash debug-collection.sh                                    # defaults to sentinel-1-nrb
#   bash debug-collection.sh sentinel-2-l2a                     # any collection
#   NS=data-access STAC_URL=https://... bash debug-collection.sh
#
# WARNING: Do NOT source this script (. ./debug.sh) — run it as a subprocess
#          (bash debug-collection.sh). Sourcing will apply set -e to your
#          login shell and a failing command will kill your SSH session.

# Guard: refuse to run if sourced into an interactive shell
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script must not be sourced. Run it as:" >&2
    echo "  bash ${BASH_SOURCE[0]} [collection-name]" >&2
    return 1 2>/dev/null || exit 1
fi

set -euo pipefail

###############################################################################
# CONFIG — override via environment or first positional argument
###############################################################################
NS="${NS:-data-access}"
STAC_URL="${STAC_URL:-https://stac-k8s.terrabyte.lrz.de/stac}"
COLLECTION="${1:-sentinel-1-nrb}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"

###############################################################################
# LOGGING — tee everything to a timestamped file
###############################################################################
LOG_DIR="${LOG_DIR:-$HOME/eoapi-loadtest-logs}"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/debug-${COLLECTION}-$(date -u +'%Y%m%d-%H%M%S').log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Logging to: $LOGFILE"

echo "=========================================="
echo "  COLLECTION DEBUG: $COLLECTION"
echo "  $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

###############################################################################
# Helper: discover database connection (may be cross-namespace)
###############################################################################
DB_NS="${DB_NS:-}"
DB_POD="${DB_POD:-}"
DB_USER="${DB_USER:-}"
DB_NAME="${DB_NAME:-}"

discover_db_connection() {
    echo "  Discovering database connection..."

    # 1. Read connection info from the STAC pod's environment
    local stac_env
    stac_env=$(kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- env 2>/dev/null \
        | grep -E '^(PGHOST|PGUSER|PGDATABASE|PGPORT|DATABASE_URL)=' || true)

    if [[ -n "$stac_env" ]]; then
        echo "  STAC pod env:"
        echo "$stac_env" | sed 's/^/    /'

        # Note: PGUSER from STAC env is the app user (e.g. eoapi), but for
        # kubectl exec + psql we need the superuser (postgres) which has peer
        # auth on the Unix socket. We keep DB_NAME from the app env though.
        DB_NAME=$(echo "$stac_env" | grep '^PGDATABASE=' | cut -d= -f2)
        local pg_host
        pg_host=$(echo "$stac_env" | grep '^PGHOST=' | cut -d= -f2)

        # Extract namespace from service FQDN (e.g. default-primary.infra.svc)
        if [[ "$pg_host" == *.*.svc* ]]; then
            DB_NS=$(echo "$pg_host" | cut -d. -f2)
            local svc_name
            svc_name=$(echo "$pg_host" | cut -d. -f1)
            echo "  DB is in namespace: $DB_NS (service: $svc_name)"
        else
            DB_NS="$NS"
        fi
    fi

    : "${DB_USER:=postgres}"
    : "${DB_NAME:=postgis}"
    : "${DB_NS:=$NS}"

    # 2. Find a running postgres pod in the target namespace
    local pod
    pod=$(
        kubectl get pods -n "$DB_NS" -l app.kubernetes.io/name=postgresql \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
    ) && [[ -n "$pod" ]] && DB_POD="$pod" && return 0

    pod=$(
        kubectl get pods -n "$DB_NS" -l cnpg.io/cluster \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
    ) && [[ -n "$pod" ]] && DB_POD="$pod" && return 0

    pod=$(
        kubectl get pods -n "$DB_NS" -l role=primary \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
    ) && [[ -n "$pod" ]] && DB_POD="$pod" && return 0

    pod=$(
        kubectl get pods -n "$DB_NS" 2>/dev/null \
            | grep -iE 'postgres|cnpg|primary' | grep Running | head -1 | awk '{print $1}'
    ) && [[ -n "$pod" ]] && DB_POD="$pod" && return 0

    DB_POD=""
    return 1
}

# Allow manual override via environment, otherwise auto-discover
if [[ -z "$DB_POD" ]]; then
    if discover_db_connection; then
        echo "  DB pod: $DB_POD (namespace: $DB_NS, user: $DB_USER, db: $DB_NAME)"
    else
        echo "  WARNING: No DB pod found in namespace ${DB_NS:-$NS}"
        echo "  To run DB checks manually, set: DB_NS=<ns> DB_POD=<pod> DB_USER=<user> DB_NAME=<db>"
    fi
else
    : "${DB_NS:=$NS}"
    : "${DB_USER:=postgres}"
    # If DB_NAME wasn't set, try to read it from the STAC pod
    if [[ -z "$DB_NAME" ]]; then
        DB_NAME=$(
            kubectl exec -n "$NS" "deploy/${RELEASE_NAME}-stac" -- \
                printenv PGDATABASE 2>/dev/null || echo ""
        )
    fi
    : "${DB_NAME:=postgis}"
    echo "  Using provided DB_POD=$DB_POD (namespace: $DB_NS, user: $DB_USER, db: $DB_NAME)"
fi

run_sql() {
    local sql="$1"
    if [[ -z "$DB_POD" ]]; then
        echo "(no DB pod found — skipping)"
        return 1
    fi
    # Connection strategy (in order of preference):
    #   1. Unix socket as postgres (peer auth, no password) — works on Crunchy/CNPG
    #   2. TCP 127.0.0.1 with PGPASSWORD — works when only md5/scram is available
    #   3. TCP 127.0.0.1 without password — works if pg_hba allows trust/ident
    kubectl exec -n "$DB_NS" "$DB_POD" -- \
        psql -U "$DB_USER" -d "$DB_NAME" -t -c "$sql" 2>&1
}

run_sql_verbose() {
    local sql="$1"
    if [[ -z "$DB_POD" ]]; then
        echo "(no DB pod found — skipping)"
        return 1
    fi
    kubectl exec -n "$DB_NS" "$DB_POD" -- \
        psql -U "$DB_USER" -d "$DB_NAME" -c "\\timing on" -c "$sql" 2>&1
}

###############################################################################
# 1. Does the collection exist?
###############################################################################
echo ""
echo "--- 1. Collection existence ---"
HTTP_CODE=$(curl -s -o /tmp/debug_collection.json -w '%{http_code}' \
    --max-time 30 "$STAC_URL/collections/$COLLECTION")
echo "GET $STAC_URL/collections/$COLLECTION → HTTP $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
    python3 << 'PYEOF' 2>&1 || cat /tmp/debug_collection.json | head -20
import json
d = json.load(open("/tmp/debug_collection.json"))
print("  id:    %s" % d.get("id"))
print("  title: %s" % d.get("title", "(none)"))
extent = d.get("extent", {}).get("temporal", {}).get("interval", [])
if extent:
    print("  temporal extent: %s" % extent[0])
PYEOF
elif [[ "$HTTP_CODE" == "404" ]]; then
    echo "COLLECTION NOT FOUND — was it ingested?"
else
    echo "Unexpected response — body:"
    cat /tmp/debug_collection.json 2>/dev/null | head -30
fi

###############################################################################
# 2. Items listing (the known failure point)
###############################################################################
echo ""
echo "--- 2. Items listing ---"
echo "Requesting items?limit=1 with 120s timeout..."
HTTP_CODE=$(curl -s -o /tmp/debug_items.json -w '%{http_code}' \
    --max-time 120 "$STAC_URL/collections/$COLLECTION/items?limit=1")
echo "GET .../collections/$COLLECTION/items?limit=1 → HTTP $HTTP_CODE"

if [[ "$HTTP_CODE" == "200" ]]; then
    python3 << 'PYEOF' 2>&1 || echo "(python3 not available)"
import json, sys
try:
    d = json.load(open("/tmp/debug_items.json"))
except Exception as e:
    print("  (JSON parse error: %s)" % e)
    sys.exit(0)
print("  type:           %s" % d.get("type", "?"))
print("  top-level keys: %s" % list(d.keys()))
ctx = d.get("context", {})
matched = d.get("numberMatched", ctx.get("matched", "not present"))
returned = d.get("numberReturned", ctx.get("returned", len(d.get("features", []))))
print("  numberMatched:  %s" % matched)
print("  numberReturned: %s" % returned)
features = d.get("features", [])
print("  features count: %d" % len(features))
if features:
    f = features[0]
    props = f.get("properties", {})
    print("  first item id:       %s" % f.get("id", "?"))
    print("  first item datetime: %s" % props.get("datetime", "?"))
PYEOF
elif [[ "$HTTP_CODE" == "500" ]]; then
    echo "INTERNAL SERVER ERROR — response body:"
    cat /tmp/debug_items.json 2>/dev/null | python3 -m json.tool 2>/dev/null \
        || cat /tmp/debug_items.json 2>/dev/null | head -30
    echo ""
    echo "This typically means pgstac query timeout or OOM on a large collection."
elif [[ "$HTTP_CODE" == "000" ]]; then
    echo "REQUEST TIMED OUT after 120s — the query is too slow."
else
    echo "HTTP $HTTP_CODE — body:"
    cat /tmp/debug_items.json 2>/dev/null | head -20
fi

###############################################################################
# 3. Queryables for this collection
###############################################################################
echo ""
echo "--- 3. Collection queryables ---"
HTTP_CODE=$(curl -s -o /tmp/debug_queryables.json -w '%{http_code}' \
    --max-time 30 "$STAC_URL/collections/$COLLECTION/queryables")
echo "GET .../collections/$COLLECTION/queryables → HTTP $HTTP_CODE"
if [[ "$HTTP_CODE" == "200" ]]; then
    cat /tmp/debug_queryables.json | python3 -m json.tool 2>/dev/null | head -40
fi

###############################################################################
# 4. Search performance (3 timed attempts)
###############################################################################
echo ""
echo "--- 4. Search performance (POST /search, limit=1) ---"

for i in 1 2 3; do
    echo -n "  attempt $i: "
    START_NS=$(date +%s%N)
    HTTP_CODE=$(curl -s -o /tmp/debug_search.json -w '%{http_code}' \
        --max-time 120 \
        -X POST -H "Content-Type: application/json" \
        -d "{\"collections\":[\"$COLLECTION\"],\"limit\":1}" \
        "$STAC_URL/search")
    END_NS=$(date +%s%N)
    ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
    echo "HTTP $HTTP_CODE in ${ELAPSED_MS}ms"
done

echo ""
echo "Last search result:"
python3 << 'PYEOF' 2>&1 || echo "(python3 not available)"
import json, sys
try:
    d = json.load(open("/tmp/debug_search.json"))
except Exception as e:
    print("  (JSON parse error: %s)" % e)
    sys.exit(0)
print("  top-level keys: %s" % list(d.keys()))
ctx = d.get("context", {})
matched = d.get("numberMatched", ctx.get("matched", "not present"))
returned = d.get("numberReturned", ctx.get("returned", len(d.get("features", []))))
print("  numberMatched:  %s" % matched)
print("  numberReturned: %s" % returned)
features = d.get("features", [])
if features:
    f = features[0]
    props = f.get("properties", {})
    print("  first item id:       %s" % f.get("id", "?"))
    print("  first item datetime: %s" % props.get("datetime", "?"))
PYEOF

###############################################################################
# 5. Database: collection + item count
###############################################################################
echo ""
echo "--- 5. Database: collection metadata ---"
echo "DB pod: ${DB_POD:-(not found)}"

echo ""
echo "  Collection row:"
run_sql "SELECT id, content->>'title' AS title
         FROM pgstac.collections
         WHERE id = '$COLLECTION';" || true

echo ""
echo "  Item count (may be slow on large collections):"
run_sql_verbose "SELECT count(*) FROM pgstac.items WHERE collection = '$COLLECTION';" || true

###############################################################################
# 6. Database: partitions + indexes
###############################################################################
echo ""
echo "--- 6. Database: partitions and sizes ---"

# pgstac uses underscores in partition names
COLLECTION_UNDERSCORE=$(echo "$COLLECTION" | tr '-' '_')

run_sql "
SELECT c.relname                                   AS partition,
       pg_size_pretty(pg_relation_size(c.oid))     AS data_size,
       pg_size_pretty(pg_indexes_size(c.oid))      AS index_size,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'pgstac'
  AND (c.relname LIKE '%${COLLECTION_UNDERSCORE}%'
       OR c.relname LIKE '%${COLLECTION}%')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 20;
" || true

echo ""
echo "  Index list on partitions:"
run_sql "
SELECT indexrelid::regclass AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index
WHERE indrelid IN (
    SELECT c.oid FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'pgstac'
      AND (c.relname LIKE '%${COLLECTION_UNDERSCORE}%'
           OR c.relname LIKE '%${COLLECTION}%')
)
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;
" || true

###############################################################################
# 7. Database: EXPLAIN on items query
###############################################################################
echo ""
echo "--- 7. Database: EXPLAIN ANALYZE on items query ---"
echo "  (This runs the actual query — may take time on large collections)"

run_sql_verbose "
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT content
FROM pgstac.items
WHERE collection = '$COLLECTION'
ORDER BY datetime DESC, id DESC
LIMIT 1;
" || true

###############################################################################
# 8. Database: pgstac search context settings
###############################################################################
echo ""
echo "--- 8. Database: pgstac context settings ---"

run_sql "SELECT * FROM pgstac.pgstac_settings();" \
    || run_sql "SELECT name, value FROM pgstac.migrations ORDER BY id DESC LIMIT 5;" \
    || echo "  (could not read pgstac settings)"

###############################################################################
# 9. Database: active / long-running queries
###############################################################################
echo ""
echo "--- 9. Database: active queries ---"

run_sql "
SELECT pid,
       now() - query_start AS duration,
       state,
       left(query, 100) AS query
FROM pg_stat_activity
WHERE state != 'idle'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration DESC
LIMIT 10;
" || true

###############################################################################
# 10. Database: connection pool usage
###############################################################################
echo ""
echo "--- 10. Database: connection counts ---"

run_sql "
SELECT state, count(*)
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state
ORDER BY count DESC;
" || true

run_sql "SELECT current_setting('max_connections') AS max_connections;" || true

###############################################################################
# 11. STAC pod logs for this collection
###############################################################################
echo ""
echo "--- 11. STAC pod logs (errors related to $COLLECTION) ---"
kubectl logs -n "$NS" "deploy/${RELEASE_NAME}-stac" --since=30m --tail=300 2>&1 \
    | grep -iE "$COLLECTION|error|exception|timeout|500|internal" \
    | tail -30 \
    || echo "(no matching log lines)"

###############################################################################
# 12. Auth-proxy logs for this collection
###############################################################################
echo ""
echo "--- 12. Auth-proxy logs (errors related to $COLLECTION) ---"
kubectl logs -n "$NS" "deploy/${RELEASE_NAME}-stac-auth-proxy" --since=30m --tail=300 2>&1 \
    | grep -iE "$COLLECTION|error|exception|timeout|500|internal|5[0-9][0-9]" \
    | tail -30 \
    || echo "(no matching log lines)"

###############################################################################
# 13. STAC manager check
###############################################################################
echo ""
echo "--- 13. STAC Manager status ---"
kubectl get deploy -n "$NS" | grep -i manager || echo "(no manager deployment)"
kubectl logs -n "$NS" "deploy/${RELEASE_NAME}-stac-manager" --since=30m --tail=50 2>&1 \
    | grep -iE "$COLLECTION|error|exception|timeout|500" \
    | tail -15 \
    || echo "(no matching log lines)"

###############################################################################
# Done
###############################################################################
echo ""
echo "=========================================="
echo "  DEBUG COMPLETE — $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "  Full log at: $LOGFILE"
echo "=========================================="
echo ""
echo "Common findings for large-collection 500s / timeouts:"
echo "  - Missing partitions: step 6 shows no partitions → items not partitioned"
echo "  - Huge partition:     step 6 shows one very large partition → needs sub-partitioning"
echo "  - Missing indexes:    step 6 shows no indexes on partition → pgstac migrate needed"
echo "  - Slow seq scan:      step 7 shows Seq Scan → missing index on datetime/id"
echo "  - Context overhead:   pgstac numberMatched count on millions of rows is expensive"
echo "                        check step 8 for 'context' setting (should be 'off' for large collections)"
echo "  - Connection pool:    step 10 shows near max_connections → pool exhaustion under load"
