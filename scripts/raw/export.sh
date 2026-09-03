#!/bin/bash

# eoAPI Data Export Script
#
# Exports STAC collections and items from a PgSTAC database to NDJSON files,
# using pgstac's own content_hydrate() function so items come out fully
# hydrated (not the dehydrated form PgSTAC stores on disk). The output is
# loadable straight into another PgSTAC instance with scripts/raw/ingest.sh --
# this is the export half of a PgSTAC -> PgSTAC migration.
#
# This script only needs `psql` on PATH and a reachable Postgres DSN -- it
# has no Kubernetes dependency at all, so it works standalone against any
# PgSTAC database (local, external, port-forwarded, whatever). For a
# Kubernetes-aware convenience wrapper (auto-discovering/port-forwarding the
# current cluster's own database), see scripts/data-management.sh / `eoapi-cli export`.
#
# Everything runs through a single psql session (using \o to redirect each
# query's output to its own file, and \if to bail out cleanly if the source
# schema isn't compatible) rather than one psql invocation per query. This
# isn't just an efficiency nicety: some port-forward setups only tolerate a
# single connection per invocation before the tunnel drops, so multiple
# separate psql connections through a port-forwarded DSN can fail outright.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../lib/common.sh"

DEFAULT_OUTPUT_DIR="./stac-export"
DSN=""
OUTPUT_DIR=""
COLLECTIONS=()

usage() {
    cat <<EOF
Usage: $(basename "$0") --dsn DSN [OPTIONS] [OUTPUT_DIR]

Export STAC collections and items from a PgSTAC database to NDJSON files.
Requires only 'psql' on PATH -- no Kubernetes involved.

OPTIONS:
    --dsn DSN            Postgres DSN of the PgSTAC database to export from.
                         Required.
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
        --dsn)
            DSN="$2"
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

if [ -z "$DSN" ]; then
    log_error "--dsn is required"
    usage
    exit 1
fi

if ! validate_tools psql; then
    log_error "Install a PostgreSQL client to continue, e.g.:"
    log_error "  Debian/Ubuntu: apt-get install postgresql-client"
    log_error "  macOS:         brew install libpq && brew link --force libpq"
    exit 1
fi

OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# Escapes a path for use as a quoted psql meta-command argument (\o '...'),
# which uses backslash-escaping, not SQL-string quote-doubling.
psql_quote_path() {
    local p="${1//\\/\\\\}"
    echo "${p//\'/\\\'}"
}
COLLECTIONS_FILE="$OUTPUT_DIR/collections.ndjson"
ITEMS_FILE="$OUTPUT_DIR/items.ndjson"
COLLECTIONS_FILE_ESC="$(psql_quote_path "$COLLECTIONS_FILE")"
ITEMS_FILE_ESC="$(psql_quote_path "$ITEMS_FILE")"

COLLECTIONS_QUERY="select content from pgstac.collections"
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
    COLLECTIONS_QUERY="$COLLECTIONS_QUERY where id in ($IN_LIST)"
    ITEMS_QUERY="$ITEMS_QUERY where collection in ($IN_LIST)"
    log_info "Exporting collections and items for collections: ${COLLECTIONS[*]}..."
else
    log_info "Exporting all collections and items..."
fi

if ! psql -q -v ON_ERROR_STOP=1 "$DSN" -f - <<SQL
\pset tuples_only on
\pset format unaligned
select (count(*) > 0) as hydrate_ok from pg_proc where pronamespace = 'pgstac'::regnamespace and proname = 'content_hydrate' \gset
\if :hydrate_ok
\o '${COLLECTIONS_FILE_ESC}'
${COLLECTIONS_QUERY};
\o '${ITEMS_FILE_ESC}'
${ITEMS_QUERY};
\o
\else
do \$\$ begin raise exception 'pgstac.content_hydrate() was not found on the source database'; end \$\$;
\endif
SQL
then
    log_error "Export failed. If this is because pgstac.content_hydrate() is missing, see 'Export data' in docs/manage-data.md for a manual fallback."
    exit 1
fi

log_info "Collections exported: $(wc -l < "$COLLECTIONS_FILE") records"
log_info "Items exported: $(wc -l < "$ITEMS_FILE") records"
log_success "✅ Export completed: $COLLECTIONS_FILE, $ITEMS_FILE"
