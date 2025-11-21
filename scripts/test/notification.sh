#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

NAMESPACE="${NAMESPACE:-eoapi}"
RELEASE_NAME="${RELEASE_NAME:-}"
DEBUG_MODE="${DEBUG_MODE:-false}"

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
    python3 -m pip install --quiet pytest httpx requests >/dev/null 2>&1

    # Set up service endpoints for API access
    # Use existing endpoints if set, otherwise determine based on cluster access
    if [[ -z "${STAC_ENDPOINT:-}" ]]; then
        # Check if we have an ingress
        local ingress_host
        ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")

        if [[ -n "$ingress_host" ]]; then
            # Use ingress host
            export STAC_ENDPOINT="http://${ingress_host}/stac"
            export RASTER_ENDPOINT="http://${ingress_host}/raster"
            export VECTOR_ENDPOINT="http://${ingress_host}/vector"
        else
            # Fall back to localhost (assumes port-forward or local ingress)
            export STAC_ENDPOINT="http://localhost/stac"
            export RASTER_ENDPOINT="http://localhost/raster"
            export VECTOR_ENDPOINT="http://localhost/vector"
        fi
    fi
    export NAMESPACE
    export RELEASE_NAME

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
