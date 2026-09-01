#!/bin/bash

# eoAPI Data Export Script
#
# Exports STAC collections and items from a PgSTAC database to NDJSON files,
# using pgstac's own content_hydrate() function so items come out fully
# hydrated (not the dehydrated form PgSTAC stores on disk). The output is
# loadable straight into another PgSTAC instance with scripts/ingest.sh --
# this is the export half of a PgSTAC -> PgSTAC migration.
#
# Unlike ingest.sh, this streams query output directly from `kubectl exec`
# to a local file (no in-pod temp file / kubectl cp round-trip needed, since
# kubectl exec already relays the remote command's stdout to the caller).

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"

DEFAULT_OUTPUT_DIR="./stac-export"
SOURCE_DSN=""
OUTPUT_DIR=""
COLLECTIONS=()

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [OUTPUT_DIR]

Export STAC collections and items from a PgSTAC database to NDJSON files.

OPTIONS:
    --source-dsn DSN    Postgres DSN of the PgSTAC database to export from.
                         Defaults to the target cluster's own database
                         (\$PGADMIN_URI inside the raster pod). Pass this to
                         export from a different (e.g. older) PgSTAC instance
                         that is network-reachable from the cluster.
    --collection ID      Restrict export to one collection (repeatable).
                         Defaults to all collections.
    -h, --help           Show this help message

OUTPUT_DIR defaults to '$DEFAULT_OUTPUT_DIR'. Writes collections.ndjson and
items.ndjson, loadable via:
    eoapi-cli ingest OUTPUT_DIR/collections.ndjson OUTPUT_DIR/items.ndjson
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-dsn)
            SOURCE_DSN="$2"
            shift 2
            ;;
        --collection)
            COLLECTIONS+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            OUTPUT_DIR="$1"
            shift
            ;;
    esac
done

OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"

if ! validate_tools kubectl; then
    exit 1
fi

if ! validate_cluster; then
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

FOUND_NAMESPACE=$(detect_namespace)
log_info "Using namespace: $FOUND_NAMESPACE"

EOAPI_POD_RASTER=$(find_raster_pod "$FOUND_NAMESPACE") || exit 1

log_info "Validating pod readiness..."
if ! kubectl wait --for=condition=Ready pod "$EOAPI_POD_RASTER" -n "$FOUND_NAMESPACE" --timeout=30s; then
    log_error "Pod $EOAPI_POD_RASTER is not ready"
    kubectl describe pod "$EOAPI_POD_RASTER" -n "$FOUND_NAMESPACE"
    exit 1
fi

# Runs `psql -tAc "$1"` (unaligned, tuples-only -- one text value per output
# line) against the source database inside the raster pod. When --source-dsn
# wasn't given, $PGADMIN_URI is expanded *inside* the pod's own shell so we
# never need to know its value locally.
run_psql_in_pod() {
    local query="$1"
    if [ -n "$SOURCE_DSN" ]; then
        # shellcheck disable=SC2016 # $1/$2 are expanded by the pod's bash, not this one -- see positional args below
        kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- \
            bash -c 'psql -v ON_ERROR_STOP=1 "$1" -tAc "$2"' _ "$SOURCE_DSN" "$query"
    else
        # shellcheck disable=SC2016 # $PGADMIN_URI/$1 are expanded by the pod's bash, not this one
        kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- \
            bash -c 'psql -v ON_ERROR_STOP=1 "$PGADMIN_URI" -tAc "$1"' _ "$query"
    fi
}

log_info "Checking for psql in pod..."
if kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- bash -c 'command -v psql' >/dev/null 2>&1; then
    log_info "psql already available"
else
    log_info "Installing postgresql-client in pod $EOAPI_POD_RASTER..."
    if ! kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- bash -c 'apt-get update -y && apt-get install -y postgresql-client'; then
        log_error "Failed to install psql (postgresql-client) in pod $EOAPI_POD_RASTER"
        exit 1
    fi
fi

log_info "Verifying pgstac.content_hydrate() is available on the source database..."
if ! run_psql_in_pod "select 1 from pg_proc where pronamespace = 'pgstac'::regnamespace and proname = 'content_hydrate' limit 1" | grep -q 1; then
    log_error "pgstac.content_hydrate() was not found on the source database."
    log_error "This usually means the source PgSTAC schema is incompatible with this script's assumptions -- see 'Export data' in docs/manage-data.md for a manual fallback."
    exit 1
fi

log_info "Exporting collections..."
if ! run_psql_in_pod "select content from pgstac.collections" > "$OUTPUT_DIR/collections.ndjson"; then
    log_error "Failed to export collections"
    exit 1
fi
log_info "Collections exported: $(wc -l < "$OUTPUT_DIR/collections.ndjson") records"

ITEMS_QUERY="select pgstac.content_hydrate(items) from pgstac.items"
if [ ${#COLLECTIONS[@]} -gt 0 ]; then
    IN_LIST=""
    for id in "${COLLECTIONS[@]}"; do
        escaped_id="${id//\'/\'\'}"
        if [ -z "$IN_LIST" ]; then
            IN_LIST="'$escaped_id'"
        else
            IN_LIST="$IN_LIST,'$escaped_id'"
        fi
    done
    ITEMS_QUERY="$ITEMS_QUERY where collection in ($IN_LIST)"
    log_info "Exporting items for collections: ${COLLECTIONS[*]}..."
else
    log_info "Exporting items for all collections..."
fi

if ! run_psql_in_pod "$ITEMS_QUERY" > "$OUTPUT_DIR/items.ndjson"; then
    log_error "Failed to export items"
    exit 1
fi
log_info "Items exported: $(wc -l < "$OUTPUT_DIR/items.ndjson") records"

log_success "✅ Export completed: $OUTPUT_DIR/collections.ndjson, $OUTPUT_DIR/items.ndjson"
