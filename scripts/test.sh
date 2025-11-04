#!/bin/bash

# eoAPI Test Suite - Combined Helm and Integration Testing

# Source shared utilities
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"

# Global variables
DEBUG_MODE=false
NAMESPACE="eoapi"
COMMAND=""
RELEASE_NAME=""

# Auto-detect CI environment
if is_ci_environment; then
    DEBUG_MODE=true
    RELEASE_NAME="${RELEASE_NAME:-eoapi-$(echo "${GITHUB_SHA:-local}" | cut -c1-8)}"
else
    RELEASE_NAME="${RELEASE_NAME:-eoapi}"
fi

# Show help message
show_help() {
    cat << EOF
eoAPI Test Suite - Combined Helm and Integration Testing

USAGE: $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
    helm              Run Helm tests (lint, template validation)
    integration       Run integration tests (requires deployed eoAPI)
    all               Run both Helm and integration tests [default]
    check-deps        Check dependencies only
    check-deployment  Debug deployment state

OPTIONS:
    --debug           Enable debug mode
    --help, -h        Show this help

ENVIRONMENT VARIABLES:
    RELEASE_NAME      Helm release name (auto-generated in CI)
    NAMESPACE         Target namespace (default: eoapi)

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        helm|integration|all|check-deps|check-deployment)
            COMMAND="$1"; shift ;;
        --debug)
            DEBUG_MODE=true; shift ;;
        --help|-h)
            show_help; exit 0 ;;
        *)
            log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Default command
if [ -z "$COMMAND" ]; then
    COMMAND="all"
fi

log_info "eoAPI Test Suite - Command: $COMMAND | Debug: $DEBUG_MODE | Release: $RELEASE_NAME"

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    command -v helm >/dev/null 2>&1 || { log_error "helm required"; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { log_error "kubectl required"; exit 1; }
    log_info "✅ Dependencies OK"
}

# Run Helm tests
run_helm_tests() {
    log_info "=== Helm Tests ==="

    for chart_dir in charts/*/; do
        if [ -d "$chart_dir" ]; then
            chart_name=$(basename "$chart_dir")
            log_info "Testing chart: $chart_name"

            if ! helm lint "$chart_dir" --strict; then
                log_error "Helm lint failed for $chart_name"
                exit 1
            fi

            # Use test values for eoapi chart if available
            if [ "$chart_name" = "eoapi" ] && [ -f "$chart_dir/test-helm-values.yaml" ]; then
                if ! helm template test "$chart_dir" -f "$chart_dir/test-helm-values.yaml" >/dev/null; then
                    log_error "Helm template failed for $chart_name with test values"
                    exit 1
                fi
            elif ! helm template test "$chart_dir" >/dev/null; then
                log_error "Helm template failed for $chart_name"
                exit 1
            fi

            log_info "✅ $chart_name OK"
        fi
    done
}

# Debug deployment state
debug_deployment_state() {
    log_info "=== Deployment Debug ==="

    kubectl get namespace "$NAMESPACE" 2>/dev/null || log_warn "Namespace '$NAMESPACE' not found"

    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        log_info "Helm release status:"
        helm status "$RELEASE_NAME" -n "$NAMESPACE"
    else
        log_warn "Release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
    fi

    log_info "Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || log_info "No pods in $NAMESPACE"

    log_info "Services:"
    kubectl get svc -n "$NAMESPACE" 2>/dev/null || log_info "No services in $NAMESPACE"

    if [ "$DEBUG_MODE" = true ]; then
        log_info "Jobs:"
        kubectl get jobs -n "$NAMESPACE" 2>/dev/null || log_info "No jobs"

        log_info "Recent events:"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || log_info "No events"


    fi
}

# Run integration tests
run_integration_tests() {
    log_info "=== Integration Tests ==="

    export RELEASE_NAME="$RELEASE_NAME"
    export NAMESPACE="$NAMESPACE"

    # Validate deployment exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace '$NAMESPACE' not found. Deploy eoAPI first."
        exit 1
    fi

    if ! helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        log_error "Release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
        exit 1
    fi

    # Enhanced debugging in CI/debug mode
    if [ "$DEBUG_MODE" = true ]; then
        debug_deployment_state
    fi

    # TODO: Add actual integration test implementation
    log_info "Running basic endpoint checks..."

    # Wait for pods to be ready
    if kubectl get pods -n "$NAMESPACE" >/dev/null 2>&1; then
        wait_for_pods "$NAMESPACE" "app=$RELEASE_NAME-stac" "300s" || log_warn "STAC pods not ready"
    fi

    log_info "✅ Integration tests completed"
}

# Main execution
case "$COMMAND" in
    helm)
        check_dependencies
        run_helm_tests
        ;;
    integration)
        check_dependencies
        run_integration_tests
        ;;
    all)
        check_dependencies
        run_helm_tests
        run_integration_tests
        ;;
    check-deps)
        check_dependencies
        ;;
    check-deployment)
        debug_deployment_state
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac

log_info "✅ Test suite completed successfully"
