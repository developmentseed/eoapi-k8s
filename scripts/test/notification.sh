#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

NAMESPACE="${NAMESPACE:-eoapi}"
RELEASE_NAME="${RELEASE_NAME:-}"
DEBUG_MODE="${DEBUG_MODE:-false}"
PORT_FORWARD_PID=""

cleanup() {
    if [[ -n "$PORT_FORWARD_PID" ]] && kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        log_debug "Stopping port forwarding (PID: $PORT_FORWARD_PID)"
        kill "$PORT_FORWARD_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

run_notification_tests() {
    local pytest_args="${1:-}"

    log_info "Running notification tests..."

    check_requirements python3 kubectl || return 1

    if [[ -z "$RELEASE_NAME" ]]; then
        RELEASE_NAME=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="eoapi")].metadata.labels.app\.kubernetes\.io/instance}' | head -1)
        [[ -z "$RELEASE_NAME" ]] && { log_error "Cannot detect release name"; return 1; }
    fi

    log_debug "Connected to cluster: $(kubectl config current-context)"

    log_info "Installing Python test dependencies..."
    python3 -m pip install --quiet pytest httpx psycopg2-binary requests >/dev/null 2>&1

    if kubectl get secret "${RELEASE_NAME}-pguser-eoapi" -n "$NAMESPACE" &>/dev/null; then
        local pg_host pg_port
        pg_host=$(kubectl get secret "${RELEASE_NAME}-pguser-eoapi" -n "$NAMESPACE" -o jsonpath='{.data.host}' | base64 -d)
        pg_port=$(kubectl get secret "${RELEASE_NAME}-pguser-eoapi" -n "$NAMESPACE" -o jsonpath='{.data.port}' | base64 -d)

        # Set up port forwarding for database access
        local local_port=15432
        log_info "Setting up database port forwarding (localhost:$local_port -> $pg_host:$pg_port)"

        kubectl port-forward -n "$NAMESPACE" "svc/${RELEASE_NAME}-primary" "$local_port:$pg_port" >/dev/null 2>&1 &
        PORT_FORWARD_PID=$!

        # Wait for port forward to be ready
        for i in {1..10}; do
            if nc -z localhost "$local_port" 2>/dev/null; then
                log_success "Port forwarding established"
                break
            fi
            [[ $i -eq 10 ]] && { log_error "Port forwarding failed"; return 1; }
            sleep 1
        done

        export PGHOST="localhost"
        export PGPORT="$local_port"
        PGDATABASE=$(kubectl get secret "${RELEASE_NAME}-pguser-eoapi" -n "$NAMESPACE" -o jsonpath='{.data.dbname}' | base64 -d)
        export PGDATABASE
        PGUSER=$(kubectl get secret "${RELEASE_NAME}-pguser-eoapi" -n "$NAMESPACE" -o jsonpath='{.data.user}' | base64 -d)
        export PGUSER
        PGPASSWORD=$(kubectl get secret "${RELEASE_NAME}-pguser-eoapi" -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
        export PGPASSWORD

        log_info "Database configuration set (host: localhost:$local_port)"
    else
        log_error "Database secret not found"
        return 1
    fi

    # local ingress_host
    # ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "localhost")

    export STAC_ENDPOINT="http://localhost/stac"
    export RASTER_ENDPOINT="http://localhost/raster"
    export VECTOR_ENDPOINT="http://localhost/vector"

    log_info "Running notification tests..."

    local cmd="python3 -m pytest tests/notification"
    [[ "$DEBUG_MODE" == "true" ]] && cmd="$cmd -v --tb=short"
    [[ -n "$pytest_args" ]] && cmd="$cmd $pytest_args"

    log_debug "Running: $cmd"

    if eval "$cmd"; then
        log_success "Notification tests passed"
        return 0
    else
        log_error "Notification tests failed"
        return 1
    fi
}

run_notification_tests "$@"
