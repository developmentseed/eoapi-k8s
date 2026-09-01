#!/bin/bash

# eoAPI Data Management Kubernetes Wrapper
#
# Thin Kubernetes-aware wrapper around scripts/raw/export.sh and
# scripts/raw/ingest.sh (the actual export/ingest logic, which only needs
# `psql`/`jq` and a DSN -- no kubectl at all). This is what `eoapi-cli
# export` and `eoapi-cli ingest` invoke.
#
# - With --source-dsn/--target-dsn: passes straight through to the raw
#   script -- no kubectl calls happen at all. This is the normal migration
#   case, since the other instance is usually an external, directly-
#   reachable database.
# - Without it: auto-discovers and port-forwards the *current* cluster's
#   own database (useful for testing/round-tripping against a dev
#   deployment), then calls the raw script with the resulting localhost
#   DSN. Only works when postgresql.type is "postgrescluster" (the chart's
#   default), since that's what creates the {release}-pguser-postgres admin
#   secret this depends on.

WRAPPER_DIR="$(dirname "$(readlink -f "$0")")"
source "$WRAPPER_DIR/lib/common.sh"
source "$WRAPPER_DIR/lib/k8s.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <ingest|export> [OPTIONS] [ARGS]

export OPTIONS:
    --source-dsn DSN    Postgres DSN to export from. Defaults to the target
                         cluster's own database, auto-discovered and
                         port-forwarded.
    --collection ID      Restrict export to one collection (repeatable).
    [OUTPUT_DIR]          Defaults to './stac-export'.

ingest OPTIONS:
    --target-dsn DSN    Postgres DSN to load into. Defaults to the target
                         cluster's own database, auto-discovered and
                         port-forwarded.
    [COLLECTIONS_FILE] [ITEMS_FILE]   Default to './collections.json' /
                                       './items.json'.
EOF
}

MODE="${1:-}"
case "$MODE" in
    ingest|export)
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        log_error "Expected 'ingest' or 'export' as the first argument, got: '${MODE}'"
        usage
        exit 1
        ;;
esac

# Discovers and port-forwards the current cluster's own PgSTAC database,
# setting DISCOVERED_DSN to a localhost DSN on success. Sets up a trap to
# kill the port-forward when this script exits. Deliberately sets a global
# rather than "returning" the DSN via stdout/command substitution -- the
# latter would run in a subshell, and the trap/background port-forward PID
# it starts would not survive past that subshell exiting.
DISCOVERED_DSN=""
discover_and_forward_dsn() {
    validate_tools kubectl jq || return 1
    validate_cluster || return 1

    local namespace release secret_name
    namespace=$(detect_namespace)
    log_info "Using namespace: $namespace"
    release=$(detect_release_name "$namespace")
    secret_name="${release}-pguser-postgres"

    log_info "Looking up database credentials from secret $secret_name..."
    local db_user db_pass db_port db_name
    db_user=$(get_secret_value "$namespace" "$secret_name" "user" 2>/dev/null || echo "")
    db_pass=$(get_secret_value "$namespace" "$secret_name" "password" 2>/dev/null || echo "")
    db_port=$(get_secret_value "$namespace" "$secret_name" "port" 2>/dev/null || echo "")
    db_name=$(get_secret_value "$namespace" "$secret_name" "dbname" 2>/dev/null || echo "")
    if [ -z "$db_user" ] || [ -z "$db_pass" ] || [ -z "$db_port" ] || [ -z "$db_name" ]; then
        log_error "Could not read user/password/port/dbname from secret $secret_name in namespace $namespace."
        log_error "This auto-discovery only works when postgresql.type=postgrescluster."
        log_error "For any other setup, pass --source-dsn/--target-dsn 'postgresql://user:pass@host:port/db' directly."
        return 1
    fi

    # The CrunchyData PGO "-primary" service (what PGHOST/the uri secret
    # point at) is headless and has no selector -- PGO manages its endpoints
    # directly for failover, and `kubectl port-forward` can only target a
    # selector-based Service or a pod. Its postgres-operator.crunchydata.com/
    # role=master label identifies the current primary pod directly and
    # survives failovers, so forward to that pod instead.
    local primary_pod
    primary_pod=$(get_pod_name "$namespace" "postgres-operator.crunchydata.com/cluster=${release},postgres-operator.crunchydata.com/role=master")
    if [ -z "$primary_pod" ]; then
        primary_pod=$(get_pod_name "$namespace" "postgres-operator.crunchydata.com/role=master")
    fi
    if [ -z "$primary_pod" ]; then
        log_error "Could not find the PgSTAC primary pod (label postgres-operator.crunchydata.com/role=master) in namespace $namespace."
        log_error "Pass --source-dsn/--target-dsn directly instead."
        return 1
    fi

    PF_LOG="$(mktemp)"
    PF_PID=""
    cleanup() {
        [ -n "$PF_PID" ] && kill "$PF_PID" >/dev/null 2>&1 || true
        rm -f "$PF_LOG"
    }
    trap cleanup EXIT

    log_info "Port-forwarding pod/$primary_pod ($db_port) in namespace $namespace..."
    kubectl port-forward -n "$namespace" "pod/$primary_pod" ":$db_port" >"$PF_LOG" 2>&1 &
    PF_PID=$!

    local local_port=""
    for _ in $(seq 1 30); do
        local_port=$(grep -oE '127\.0\.0\.1:[0-9]+' "$PF_LOG" | head -1 | grep -oE '[0-9]+$' || echo "")
        [ -n "$local_port" ] && break
        kill -0 "$PF_PID" 2>/dev/null || break
        sleep 0.2
    done

    if [ -z "$local_port" ]; then
        log_error "kubectl port-forward to pod/$primary_pod did not come up in time:"
        cat "$PF_LOG" >&2
        return 1
    fi

    # kubectl prints "Forwarding from ..." as soon as its local listener is
    # up, slightly before the tunnel to the pod is actually ready to accept
    # connections -- confirm Postgres is really reachable through it before
    # handing the DSN off, rather than racing straight into the real load.
    if ! command_exists pg_isready; then
        sleep 1
    else
        local forward_ready=""
        for _ in $(seq 1 30); do
            if pg_isready -h 127.0.0.1 -p "$local_port" >/dev/null 2>&1; then
                forward_ready=1
                break
            fi
            kill -0 "$PF_PID" 2>/dev/null || break
            sleep 0.2
        done
        if [ -z "$forward_ready" ]; then
            log_error "Port-forward to pod/$primary_pod came up but Postgres never became reachable through it:"
            cat "$PF_LOG" >&2
            return 1
        fi
    fi
    log_info "Forwarded localhost:$local_port -> pod/$primary_pod:$db_port"

    local db_user_enc db_pass_enc
    db_user_enc=$(jq -rn --arg v "$db_user" '$v|@uri')
    db_pass_enc=$(jq -rn --arg v "$db_pass" '$v|@uri')
    DISCOVERED_DSN="postgresql://${db_user_enc}:${db_pass_enc}@localhost:${local_port}/${db_name}"
}

case "$MODE" in
    export)
        SOURCE_DSN=""
        OUTPUT_DIR=""
        COLLECTIONS=()
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

        PASSTHROUGH_ARGS=()
        for id in "${COLLECTIONS[@]}"; do
            PASSTHROUGH_ARGS+=(--collection "$id")
        done
        [ -n "$OUTPUT_DIR" ] && PASSTHROUGH_ARGS+=("$OUTPUT_DIR")

        if [ -n "$SOURCE_DSN" ]; then
            exec "$WRAPPER_DIR/raw/export.sh" --dsn "$SOURCE_DSN" "${PASSTHROUGH_ARGS[@]}"
        fi

        discover_and_forward_dsn || exit 1
        "$WRAPPER_DIR/raw/export.sh" --dsn "$DISCOVERED_DSN" "${PASSTHROUGH_ARGS[@]}"
        ;;
    ingest)
        TARGET_DSN=""
        POSITIONAL=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --target-dsn)
                    TARGET_DSN="$2"
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

        if [ -n "$TARGET_DSN" ]; then
            exec "$WRAPPER_DIR/raw/ingest.sh" --dsn "$TARGET_DSN" "${POSITIONAL[@]}"
        fi

        discover_and_forward_dsn || exit 1
        "$WRAPPER_DIR/raw/ingest.sh" --dsn "$DISCOVERED_DSN" "${POSITIONAL[@]}"
        ;;
esac
