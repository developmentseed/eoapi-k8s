#!/bin/bash

# eoAPI Data Ingest Script
#
# Loads STAC collections and items into a PgSTAC database directly via psql,
# using the same "insert, ignore duplicates" semantics as `pypgstac load
# --method insert_ignore` -- but talking to pgstac's own SQL primitives
# instead of depending on pypgstac. Accepts either NDJSON (one JSON object
# per line) or a single JSON document (e.g. a top-level array), same as
# pypgstac itself.
#
# This script only needs `psql` and `jq` on PATH and a reachable Postgres
# DSN -- it has no Kubernetes dependency at all. For a Kubernetes-aware
# convenience wrapper (auto-discovering/port-forwarding the current
# cluster's own database), see scripts/data-management.sh / `eoapi-cli ingest`.
#
# Everything runs through a single psql session (using \if to bail out
# cleanly if the target schema isn't compatible) rather than one psql
# invocation per statement. This isn't just an efficiency nicety: some
# port-forward setups only tolerate a small number of connections per
# invocation before the tunnel drops, so many separate psql connections
# through a port-forwarded DSN can fail outright.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../lib/common.sh"

DEFAULT_COLLECTIONS_FILE="./collections.json"
DEFAULT_ITEMS_FILE="./items.json"
DSN=""
COLLECTIONS_FILE=""
ITEMS_FILE=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --dsn DSN [COLLECTIONS_FILE] [ITEMS_FILE]

Load STAC collections and items into a PgSTAC database. Requires 'psql' and
'jq' on PATH -- no Kubernetes involved.

OPTIONS:
    --dsn DSN     Postgres DSN of the PgSTAC database to load into. Required.
    -h, --help    Show this help message

COLLECTIONS_FILE defaults to '$DEFAULT_COLLECTIONS_FILE', ITEMS_FILE to
'$DEFAULT_ITEMS_FILE'. Both may be NDJSON or a single JSON document.
EOF
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dsn)
            DSN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

[ ${#POSITIONAL[@]} -ge 1 ] && COLLECTIONS_FILE="${POSITIONAL[0]}"
[ ${#POSITIONAL[@]} -ge 2 ] && ITEMS_FILE="${POSITIONAL[1]}"
COLLECTIONS_FILE="${COLLECTIONS_FILE:-$DEFAULT_COLLECTIONS_FILE}"
ITEMS_FILE="${ITEMS_FILE:-$DEFAULT_ITEMS_FILE}"

if [ -z "$DSN" ]; then
    log_error "--dsn is required"
    usage
    exit 1
fi

if ! validate_tools psql jq; then
    log_error "Install a PostgreSQL client and jq to continue, e.g.:"
    log_error "  Debian/Ubuntu: apt-get install postgresql-client jq"
    log_error "  macOS:         brew install libpq jq && brew link --force libpq"
    exit 1
fi

validate_stac_file "$COLLECTIONS_FILE" || exit 1
validate_stac_file "$ITEMS_FILE" || exit 1

# Quoted SQL literals avoid `psql \copy` (its backslash-escaping would
# corrupt JSON); a temp file rather than `< <(jq ...)` surfaces jq parse
# failures instead of silently truncating the record set.
emit_records() {
    local file="$1"
    local sql_prefix="$2"
    local sql_suffix="$3"
    local tmp
    tmp="$(mktemp)"

    if ! jq -c 'if type == "array" then .[] else . end' "$file" > "$tmp"; then
        log_error "jq failed to parse $file"
        rm -f "$tmp"
        return 1
    fi

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local escaped="${line//\'/\'\'}"
        echo "${sql_prefix}'${escaped}'${sql_suffix}"
    done < "$tmp"
    rm -f "$tmp"
}

log_info "Loading collections from $COLLECTIONS_FILE and items from $ITEMS_FILE..."
if ! {
    cat <<'SQL'
\pset tuples_only on
\pset format unaligned
select (
    exists(select 1 from pg_proc where pronamespace = 'pgstac'::regnamespace and proname = 'upsert_collection')
    and exists(select 1 from pg_class where relnamespace = 'pgstac'::regnamespace and relname = 'items_staging_ignore')
) as ok \gset
\if :ok
BEGIN;
SQL
    # Runs in a subshell (left of the pipe to psql below); exit here
    # propagates failure via pipefail.
    emit_records "$COLLECTIONS_FILE" "select pgstac.upsert_collection(" "::jsonb);" || exit 1
    emit_records "$ITEMS_FILE" "insert into pgstac.items_staging_ignore (content) values (" "::jsonb);" || exit 1
    cat <<'SQL'
COMMIT;
select 'Collections: ' || count(*) from pgstac.collections;
select 'Items: ' || count(*) from pgstac.items;
\else
do $$ begin raise exception 'pgstac.upsert_collection()/items_staging_ignore not found on the target database'; end $$;
\endif
SQL
} | psql -q -v ON_ERROR_STOP=1 "$DSN" -f -
then
    log_error "Ingest failed. If this is because pgstac.upsert_collection()/items_staging_ignore is missing, see 'Load data' in docs/manage-data.md for a manual fallback."
    exit 1
fi

log_success "✅ Ingest completed"
