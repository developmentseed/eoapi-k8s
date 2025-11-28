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
    autoscaling     Delegate to autoscaling.sh for HPA tests
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

    # Test autoscaling behavior
    $(basename "$0") autoscaling --debug

    # Find breaking points
    $(basename "$0") stress --debug

    # Run all load tests
    $(basename "$0") all
EOF
}


wait_for_services() {
    local base_url="$1"

    # Wait for deployments to be available
    for service in stac raster vector; do
        kubectl wait --for=condition=Available deployment/"${RELEASE_NAME}-${service}" -n "$NAMESPACE" --timeout=60s >/dev/null 2>&1 || \
            log_warn "Service $service may not be ready"
    done

    # Test basic connectivity
    for endpoint in "$base_url/stac" "$base_url/raster/healthz" "$base_url/vector/healthz"; do
        if ! curl -s -f -m 5 "$endpoint" >/dev/null 2>&1; then
            log_warn "Endpoint not responding: $endpoint"
        fi
    done
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

# Common setup for load tests
setup_load_test_environment() {
    local namespace="$1"
    local skip_python="${2:-false}"

    validate_cluster || return 1
    validate_namespace "$namespace" || return 1

    if [[ "$skip_python" != "true" ]]; then
        validate_python_with_requirements "tests/requirements.txt" "${SCRIPT_DIR}/.." || return 1
    fi

    local base_url
    if ! base_url=$(get_base_url "$namespace"); then
        log_error "Cannot reach eoAPI endpoints"
        return 1
    fi

    log_info "Using base URL: $base_url"
    wait_for_services "$base_url"

    echo "$base_url"  # Return base_url for caller
}

load_baseline() {
    log_info "Running baseline load test..."

    local base_url
    base_url=$(setup_load_test_environment "$NAMESPACE" "true") || return 1

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
    log_warn "Service-specific load tests not yet implemented"
    log_info "Use 'load_baseline', 'load_normal', or 'load_stress' instead"
    return 0
}

load_autoscaling() {
    log_info "Running autoscaling tests..."

    validate_autoscaling_environment "$NAMESPACE" || return 1

    validate_python_with_requirements "tests/requirements.txt" "${SCRIPT_DIR}/.." || return 1

    # Wait for deployments
    for service in stac raster vector; do
        kubectl wait --for=condition=Available deployment/"${RELEASE_NAME}-${service}" -n "$NAMESPACE" --timeout=90s || return 1
    done

    # Get ingress host
    local ingress_host
    ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "localhost")

    # Set environment for Python tests
    export STAC_ENDPOINT="http://$ingress_host/stac"
    export RASTER_ENDPOINT="http://$ingress_host/raster"
    export VECTOR_ENDPOINT="http://$ingress_host/vector"

    log_info "Running Python autoscaling tests..."
    cd "${SCRIPT_DIR}/.."

    local cmd="python3 -m pytest tests/autoscaling"
    [[ "$DEBUG_MODE" == "true" ]] && cmd="$cmd -v --tb=short"

    if eval "$cmd"; then
        log_success "Autoscaling tests passed"
    else
        log_error "Autoscaling tests failed"
        return 1
    fi
}

load_normal() {
    log_info "Running normal load test scenario..."

    local base_url
    base_url=$(setup_load_test_environment "$NAMESPACE") || return 1

    log_info "Running Python normal load test..."
    cd "${SCRIPT_DIR}/.."

    local cmd="python3 -m tests.load.load_tester normal --base-url $base_url"
    [[ "$DEBUG_MODE" == "true" ]] && cmd="$cmd --duration 30 --users 5"

    log_debug "Running: $cmd"

    if eval "$cmd"; then
        log_success "Normal load test completed"
    else
        log_error "Normal load test failed"
        return 1
    fi
}

load_stress() {
    log_info "Running stress test to find breaking points..."

    local base_url
    base_url=$(setup_load_test_environment "$NAMESPACE") || return 1

    log_info "Running Python stress test module..."
    cd "${SCRIPT_DIR}/.."

    local cmd="python3 -m tests.load.load_tester stress --base-url $base_url"
    [[ "$DEBUG_MODE" == "true" ]] && cmd="$cmd --test-duration 5 --max-workers 20"

    log_debug "Running: $cmd"

    if eval "$cmd"; then
        log_success "Stress test completed"
    else
        log_error "Stress test failed"
        return 1
    fi
}

load_chaos() {
    log_info "Running chaos testing with pod failures..."

    if ! command_exists kubectl; then
        log_error "kubectl required for chaos testing"
        return 1
    fi

    local base_url
    base_url=$(setup_load_test_environment "$NAMESPACE") || return 1

    log_info "Running Python chaos test..."
    cd "${SCRIPT_DIR}/.."

    local cmd="python3 -m tests.load.load_tester chaos --base-url $base_url --namespace $NAMESPACE"
    [[ "$DEBUG_MODE" == "true" ]] && cmd="$cmd --duration 60 --kill-interval 30"

    log_debug "Running: $cmd"

    if eval "$cmd"; then
        log_success "Chaos test completed"
    else
        log_error "Chaos test failed"
        return 1
    fi
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
            load_normal
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
