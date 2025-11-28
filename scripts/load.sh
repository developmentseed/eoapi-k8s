#!/usr/bin/env bash

# eoAPI Scripts - Load Testing Management
# Run various load testing scenarios for eoAPI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"

NAMESPACE="${NAMESPACE:-eoapi}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"

show_help() {
    cat <<EOF
Load testing for eoAPI

USAGE:
    $(basename "$0") [OPTIONS] <COMMAND> [ARGS]

COMMANDS:
    baseline        Low load, verify monitoring works
    autoscaling     Test HPA scaling under load
    normal          Realistic scenario
    stress          Find breaking points
    chaos           Kill pods during load, test resilience
    all             Run all load tests

OPTIONS:
    -h, --help      Show this help message
    -d, --debug     Enable debug mode
    -n, --namespace Set Kubernetes namespace
    --release NAME  Helm release name (default: ${RELEASE_NAME})

EXAMPLES:
    # Run baseline load test
    $(basename "$0") baseline

    # Test individual services
    $(basename "$0") services --debug

    # Test autoscaling behavior
    $(basename "$0") autoscaling --debug

    # Run all load tests
    $(basename "$0") all
EOF
}

get_base_url() {
    # Try localhost first (most common in local dev)
    if curl -s -f -m 3 "http://localhost/stac" >/dev/null 2>&1; then
        echo "http://localhost"
        return 0
    fi

    # Try ingress if configured
    local host
    host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    if [[ -n "$host" ]] && curl -s -f -m 3 "http://$host/stac" >/dev/null 2>&1; then
        echo "http://$host"
        return 0
    fi

    return 1
}

test_endpoint() {
    local url="$1"
    local duration="${2:-30}"
    local concurrency="${3:-2}"

    if ! command_exists hey; then
        log_error "hey not found. Install with: go install github.com/rakyll/hey@latest"
        return 1
    fi

    log_info "Testing $url (${duration}s, ${concurrency}c)"
    hey -z "${duration}s" -c "$concurrency" "$url" 2>/dev/null | grep -E "(Total:|Requests/sec:|Average:|Status code)"
}

monitor_during_test() {
    local duration="$1"
    log_info "Monitor with: watch kubectl get pods -n $NAMESPACE"
    sleep "$duration" &
    local sleep_pid=$!

    # Show initial state
    kubectl get hpa -n "$NAMESPACE" 2>/dev/null | head -2 || true

    wait $sleep_pid
}

load_baseline() {
    log_info "Running baseline load test..."

    validate_cluster || return 1
    validate_namespace "$NAMESPACE" || return 1

    local base_url
    if ! base_url=$(get_base_url); then
        log_error "Cannot reach eoAPI endpoints"
        return 1
    fi
    log_info "Using base URL: $base_url"

    # Wait for deployments
    for service in stac raster vector; do
        kubectl wait --for=condition=Available deployment/"${RELEASE_NAME}-${service}" -n "$NAMESPACE" --timeout=60s 2>/dev/null || \
            log_warn "Service $service may not be ready"
    done

    log_info "Running light load tests..."
    log_info "Monitor pods: kubectl get pods -n $NAMESPACE -w"

    # STAC collections (30s, 2 concurrent)
    test_endpoint "$base_url/stac/collections" &
    monitor_during_test 30
    wait

    # STAC search (60s, 3 concurrent)
    if command_exists curl && command_exists hey; then
        log_info "Testing STAC search (60s, 3c)"
        hey -z 60s -c 3 -m POST -H "Content-Type: application/json" -d '{"limit":10}' "$base_url/stac/search" 2>/dev/null | \
            grep -E "(Total:|Requests/sec:|Average:|Status code)"
    fi

    # Health checks
    test_endpoint "$base_url/raster/healthz"
    test_endpoint "$base_url/vector/healthz"

    log_success "Baseline load test completed"
}

load_services() {
    log_info "Running service-specific load tests..."
    # TODO: Implement individual service testing
}

load_autoscaling() {
    log_info "Running autoscaling tests..."

    validate_cluster || return 1
    validate_namespace "$NAMESPACE" || return 1

    # Check HPA exists
    if ! kubectl get hpa -n "$NAMESPACE" >/dev/null 2>&1 || [[ $(kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l) -eq 0 ]]; then
        log_error "No HPA resources found. Deploy with autoscaling enabled."
        return 1
    fi

    # Check metrics server
    if ! kubectl get deployment -A | grep -q metrics-server; then
        log_error "metrics-server required for autoscaling tests"
        return 1
    fi

    local base_url
    if ! base_url=$(get_base_url); then
        log_error "Cannot reach eoAPI endpoints"
        return 1
    fi
    log_info "Using base URL: $base_url"

    # Wait for services
    for service in stac raster vector; do
        kubectl wait --for=condition=Available deployment/"${RELEASE_NAME}-${service}" -n "$NAMESPACE" --timeout=90s || return 1
    done

    log_info "Current HPA status:"
    kubectl get hpa -n "$NAMESPACE"

    log_info "Generating sustained load to trigger autoscaling..."

    # Generate load that should trigger HPA (10 min, 15 concurrent)
    if command_exists hey; then
        log_info "Starting sustained load test (10 minutes)..."
        hey -z 600s -c 15 "$base_url/stac/search" -m POST \
            -H "Content-Type: application/json" -d '{"limit":100}' &
        local load_pid=$!

        # Monitor HPA changes every 30s
        log_info "Monitoring HPA scaling..."
        for i in {1..20}; do
            sleep 30
            log_info "HPA status after ${i}x30s:"
            kubectl get hpa -n "$NAMESPACE" --no-headers | awk '{print $1 ": " $6 "/" $7 " replicas, CPU: " $3}'
        done

        # Stop load test
        kill $load_pid 2>/dev/null || true
        wait $load_pid 2>/dev/null || true

        log_info "Final HPA status:"
        kubectl get hpa -n "$NAMESPACE"
        log_success "Autoscaling test completed"
    else
        log_error "hey required for autoscaling tests"
        return 1
    fi
}

load_normal() {
    log_info "Running normal load test scenario..."
    # TODO: Implement realistic mixed scenario
}

load_stress() {
    log_info "Running stress test to find breaking points..."
    # TODO: Implement stress testing
}

load_chaos() {
    log_info "Running chaos testing with pod failures..."
    # TODO: Implement chaos testing
}

load_all() {
    local failed=0

    log_info "Running all load tests..."

    load_baseline || ((failed++))
    load_services || ((failed++))
    load_autoscaling || ((failed++))
    load_normal || ((failed++))
    load_stress || ((failed++))
    load_chaos || ((failed++))

    if [[ $failed -eq 0 ]]; then
        log_success "All load tests passed"
        return 0
    else
        log_error "$failed load test suites failed"
        return 1
    fi
}

main() {
    local command=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--debug)
                export DEBUG_MODE=true
                shift
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --release)
                RELEASE_NAME="$2"
                shift 2
                ;;
            baseline|services|autoscaling|normal|stress|chaos|all)
                command="$1"
                shift
                break
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    [[ -z "$command" ]] && command="all"

    case "$command" in
        baseline)
            load_baseline
            ;;
        services)
            load_services
            ;;
        autoscaling)
            load_autoscaling
            ;;
        normal)
            load_mixed
            ;;
        stress)
            load_stress
            ;;
        chaos)
            load_chaos
            ;;
        all)
            load_all
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
