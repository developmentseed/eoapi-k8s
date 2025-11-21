#!/usr/bin/env bash

# eoAPI Autoscaling Tests Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

NAMESPACE="${NAMESPACE:-eoapi}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"

run_autoscaling_tests() {
    local pytest_args="${1:-}"

    log_info "Running autoscaling tests..."

    check_requirements python3 kubectl || return 1
    validate_cluster || return 1

    log_info "Installing Python test dependencies..."
    python3 -m pip install --user -r "${PROJECT_ROOT}/tests/requirements.txt" >/dev/null 2>&1 || {
        log_warn "Could not install test dependencies automatically"
        log_info "Try manually: pip install -r tests/requirements.txt"
    }

    if ! kubectl get deployment -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" &>/dev/null; then
        log_error "eoAPI deployment not found (release: $RELEASE_NAME, namespace: $NAMESPACE)"
        log_info "Deploy first with: eoapi deployment run"
        return 1
    fi

    if ! kubectl get hpa -n "$NAMESPACE" &>/dev/null || [[ $(kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l) -eq 0 ]]; then
        log_error "No HPA resources found in namespace $NAMESPACE"
        log_info "Autoscaling tests require HPA resources. Deploy with autoscaling enabled."
        return 1
    fi

    if ! kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        log_warn "metrics-server not found in kube-system, checking other namespaces..."
        if ! kubectl get deployment -A | grep -q metrics-server; then
            log_error "metrics-server is not deployed - required for autoscaling tests"
            return 1
        fi
    fi

    cd "$PROJECT_ROOT"

    export RELEASE_NAME="$RELEASE_NAME"
    export NAMESPACE="$NAMESPACE"

    log_info "Setting up test environment for autoscaling tests..."

    local ingress_host
    ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "localhost")
    log_info "Using ingress host: $ingress_host"

    log_info "Verifying services are ready for load testing..."
    local service_ready=false
    local retries=15  # More retries for autoscaling tests
    while [ $retries -gt 0 ]; do
        if curl -s -f http://"$ingress_host"/stac >/dev/null 2>&1 && \
           curl -s -f http://"$ingress_host"/raster/healthz >/dev/null 2>&1 && \
           curl -s -f http://"$ingress_host"/vector/healthz >/dev/null 2>&1; then
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
        log_error "Services are not ready for autoscaling tests"
        return 1
    fi

    log_info "Ensuring all pods are ready for load testing..."
    for service in stac raster vector; do
        local deployment="${RELEASE_NAME}-${service}"
        if ! kubectl wait --for=condition=available deployment/"${deployment}" -n "$NAMESPACE" --timeout=90s 2>/dev/null; then
            log_error "Deployment ${deployment} is not ready for autoscaling tests"
            return 1
        fi
    done

    log_info "Allowing services to stabilize before load testing..."
    sleep 10

    export STAC_ENDPOINT="${STAC_ENDPOINT:-http://$ingress_host/stac}"
    export RASTER_ENDPOINT="${RASTER_ENDPOINT:-http://$ingress_host/raster}"
    export VECTOR_ENDPOINT="${VECTOR_ENDPOINT:-http://$ingress_host/vector}"

    log_info "Test endpoints configured:"
    log_info "  STAC: $STAC_ENDPOINT"
    log_info "  Raster: $RASTER_ENDPOINT"
    log_info "  Vector: $VECTOR_ENDPOINT"

    log_info "Checking HPA metrics availability..."
    local hpa_ready=false
    local hpa_retries=5
    while [ $hpa_retries -gt 0 ]; do
        if kubectl get hpa -n "$NAMESPACE" -o json | grep -q "currentCPUUtilizationPercentage\|currentMetrics"; then
            hpa_ready=true
            log_info "HPA metrics are available"
            break
        fi
        hpa_retries=$((hpa_retries - 1))
        if [ $hpa_retries -gt 0 ]; then
            log_debug "Waiting for HPA metrics... (retries left: $hpa_retries)"
            sleep 5
        fi
    done

    if [ "$hpa_ready" = false ]; then
        log_warn "HPA metrics may not be fully available - tests might be flaky"
    fi

    log_info "Running extended warmup for load testing..."
    for round in {1..3}; do
        log_debug "Warmup round $round/3"
        for endpoint in "$STAC_ENDPOINT/collections" "$RASTER_ENDPOINT/healthz" "$VECTOR_ENDPOINT/healthz"; do
            for _ in {1..5}; do
                curl -s -f "$endpoint" >/dev/null 2>&1 || true
                sleep 0.2
            done
        done
        sleep 2
    done

    log_info "Current HPA status before autoscaling tests:"
    kubectl get hpa -n "$NAMESPACE" || true

    local cmd="python3 -m pytest tests/autoscaling"
    [[ "$DEBUG_MODE" == "true" ]] && cmd="$cmd -v --tb=short"
    [[ -n "$pytest_args" ]] && cmd="$cmd $pytest_args"

    log_debug "Running: $cmd"

    if eval "$cmd"; then
        log_success "Autoscaling tests passed"

        # Log final HPA status after tests
        log_info "Final HPA status after autoscaling tests:"
        kubectl get hpa -n "$NAMESPACE" || true

        return 0
    else
        log_error "Autoscaling tests failed"

        log_info "HPA status after failed autoscaling tests:"
        kubectl get hpa -n "$NAMESPACE" || true

        return 1
    fi
}

run_autoscaling_tests "$@"
