#!/usr/bin/env bash

# eoAPI Integration Tests Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

NAMESPACE="${NAMESPACE:-eoapi}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"

run_integration_tests() {
    local pytest_args="${1:-}"

    log_info "Running integration tests..."

    check_requirements kubectl || return 1
    validate_cluster || return 1
    validate_python_with_requirements "tests/requirements.txt" "$PROJECT_ROOT" || return 1

    if ! kubectl get deployment -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" &>/dev/null; then
        log_error "eoAPI deployment not found (release: $RELEASE_NAME, namespace: $NAMESPACE)"
        log_info "Deploy first with: eoapi deployment run"
        return 1
    fi

    cd "$PROJECT_ROOT"

    export RELEASE_NAME="$RELEASE_NAME"
    export NAMESPACE="$NAMESPACE"

    log_info "Setting up test environment..."

    local ingress_host
    local actual_host

    ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")

    if [[ -z "$ingress_host" ]]; then
        log_info "No ingress host configured in Kubernetes, will use localhost"
        actual_host="localhost"
    else
        log_info "Ingress configured with host: $ingress_host"
        log_info "Testing connectivity to http://$ingress_host/stac..."
        # Check if the ingress host is reachable
        if curl -s -f -m 2 "http://$ingress_host/stac" >/dev/null 2>&1; then
            log_success "Successfully connected to $ingress_host"
            actual_host="$ingress_host"
        else
            log_warn "Cannot reach $ingress_host (this is expected in CI with k3s)"
            log_info "Falling back to localhost for service access"
            actual_host="localhost"
        fi
    fi

    log_info "Final endpoint host selection: $actual_host"

    log_info "Verifying services are ready..."
    local service_ready=false
    local retries=10
    while [ $retries -gt 0 ]; do
        if curl -s -f "http://$actual_host/stac" >/dev/null 2>&1 && \
           curl -s -f "http://$actual_host/raster/healthz" >/dev/null 2>&1 && \
           curl -s -f "http://$actual_host/vector/healthz" >/dev/null 2>&1; then
            service_ready=true
            log_info "All services are responding correctly"
            break
        fi
        retries=$((retries - 1))
        if [ $retries -gt 0 ]; then
            log_debug "Waiting for services to be ready... (retries left: $retries)"
            sleep 3
        fi
    done

    if [ "$service_ready" = false ]; then
        log_warn "Some services may not be fully ready"
    fi

    log_info "Ensuring all pods are ready..."
    for service in stac raster vector; do
        local deployment="${RELEASE_NAME}-${service}"
        kubectl wait --for=condition=available deployment/"${deployment}" -n "$NAMESPACE" --timeout=60s 2>/dev/null || \
            log_warn "Deployment ${deployment} may not be fully ready"
    done

    log_info "Allowing services to stabilize..."
    sleep 5

    export STAC_ENDPOINT="${STAC_ENDPOINT:-http://$actual_host/stac}"
    export RASTER_ENDPOINT="${RASTER_ENDPOINT:-http://$actual_host/raster}"
    export VECTOR_ENDPOINT="${VECTOR_ENDPOINT:-http://$actual_host/vector}"
    export MOCK_OIDC_ENDPOINT="${MOCK_OIDC_ENDPOINT:-http://$actual_host/mock-oidc}"

    log_info "Test endpoints configured:"
    log_info "  STAC: $STAC_ENDPOINT"
    log_info "  Raster: $RASTER_ENDPOINT"
    log_info "  Vector: $VECTOR_ENDPOINT"
    log_info "  Mock OIDC: $MOCK_OIDC_ENDPOINT"

    log_info "Running service warmup..."
    for endpoint in "$STAC_ENDPOINT" "$RASTER_ENDPOINT/healthz" "$VECTOR_ENDPOINT/healthz"; do
        for _ in {1..3}; do
            curl -s -f "$endpoint" >/dev/null 2>&1 || true
            sleep 0.5
        done
    done

    local cmd="python3 -m pytest tests/integration"
    [[ "$DEBUG_MODE" == "true" ]] && cmd="$cmd -v --tb=short"
    [[ -n "$pytest_args" ]] && cmd="$cmd $pytest_args"

    log_debug "Running: $cmd"

    if eval "$cmd"; then
        log_success "Integration tests passed"
        return 0
    else
        log_error "Integration tests failed"
        return 1
    fi
}

run_integration_tests "$@"
