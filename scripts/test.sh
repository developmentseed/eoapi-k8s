#!/usr/bin/env bash

# eoAPI Scripts - Test Management
# Run various test suites for eoAPI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"

readonly CHART_PATH="${PROJECT_ROOT}/charts/eoapi"
NAMESPACE="${NAMESPACE:-eoapi}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"

show_help() {
    cat <<EOF
Test Management for eoAPI

USAGE:
    $(basename "$0") [OPTIONS] <COMMAND> [ARGS]

COMMANDS:
    schema          Validate Helm chart schema
    lint            Run Helm lint on chart
    unit            Run Helm unit tests
    integration     Run integration tests with pytest
    notification    Run notification tests with database access
    autoscaling     Run autoscaling tests with pytest
    all             Run all tests

OPTIONS:
    -h, --help      Show this help message
    -d, --debug     Enable debug mode
    -n, --namespace Set Kubernetes namespace
    --release NAME  Helm release name (default: ${RELEASE_NAME})
    --pytest-args   Additional pytest arguments

EXAMPLES:
    # Run schema validation
    $(basename "$0") schema

    # Run linting
    $(basename "$0") lint

    # Run unit tests
    $(basename "$0") unit

    # Run integration tests with debug
    $(basename "$0") integration --debug

    # Run autoscaling tests with debug
    $(basename "$0") autoscaling --debug

    # Run all tests
    $(basename "$0") all
EOF
}

test_schema() {
    log_info "Running schema validation..."

    if ! command_exists ajv; then
        log_info "Installing ajv-cli and ajv-formats..."
        npm install -g ajv-cli ajv-formats >/dev/null 2>&1 || {
            log_error "Failed to install ajv-cli. Install manually: npm install -g ajv-cli ajv-formats"
            return 1
        }
    fi

    cd "$PROJECT_ROOT"

    if [[ ! -f "charts/eoapi/values.schema.json" ]]; then
        log_error "Schema file not found: charts/eoapi/values.schema.json"
        return 1
    fi

    if ajv compile -s charts/eoapi/values.schema.json --spec=draft2020 --allow-union-types -c ajv-formats; then
        log_success "Schema validation passed"
    else
        log_error "Schema validation failed"
        return 1
    fi
}

test_lint() {
    log_info "Running Helm lint..."

    check_requirements helm || return 1

    if helm lint "$CHART_PATH"; then
        log_success "Helm lint passed"
    else
        log_error "Helm lint failed"
        return 1
    fi
}

test_unit() {
    log_info "Running Helm unit tests..."

    check_requirements helm || return 1

    if ! helm plugin list 2>/dev/null | grep -q unittest; then
        log_error "Helm unittest plugin not installed"
        log_info "Install it with: curl -fsSL https://raw.githubusercontent.com/helm-unittest/helm-unittest/main/install-binary.sh | bash"
        return 1
    fi

    if helm unittest "$CHART_PATH"; then
        log_success "Unit tests passed"
    else
        log_error "Unit tests failed"
        return 1
    fi
}

test_integration() {
    local pytest_args="${1:-}"
    export NAMESPACE="$NAMESPACE"
    export RELEASE_NAME="$RELEASE_NAME"
    export DEBUG_MODE="$DEBUG_MODE"
    "${SCRIPT_DIR}/test/integration.sh" "$pytest_args"
}

test_autoscaling() {
    local pytest_args="${1:-}"
    export NAMESPACE="$NAMESPACE"
    export RELEASE_NAME="$RELEASE_NAME"
    export DEBUG_MODE="$DEBUG_MODE"
    "${SCRIPT_DIR}/test/autoscaling.sh" "$pytest_args"
}

test_notification() {
    local pytest_args="${1:-}"
    export NAMESPACE="$NAMESPACE"
    export RELEASE_NAME="$RELEASE_NAME"
    export DEBUG_MODE="$DEBUG_MODE"
    "${SCRIPT_DIR}/test/notification.sh" "$pytest_args"
}

test_all() {
    local failed=0

    log_info "Running all tests..."

    test_schema || ((failed++))
    test_lint || ((failed++))
    test_unit || ((failed++))

    if validate_cluster 2>/dev/null; then
        test_integration || ((failed++))
        test_autoscaling || ((failed++))
        test_notification || ((failed++))
    else
        log_warn "Skipping integration tests - no cluster connection"
    fi

    if [[ $failed -eq 0 ]]; then
        log_success "All tests passed"
        return 0
    else
        log_error "$failed test suites failed"
        return 1
    fi
}

main() {
    local command=""
    local pytest_args=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--debug)
                DEBUG_MODE=true
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
            --pytest-args)
                pytest_args="$2"
                shift 2
                ;;
            schema|lint|unit|notification|integration|autoscaling|all)
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
        schema)
            test_schema
            ;;
        lint)
            test_lint
            ;;
        unit)
            test_unit
            ;;
        integration)
            test_integration "$pytest_args"
            ;;
        notification)
            test_notification "$pytest_args"
            ;;
        autoscaling)
            test_autoscaling "$pytest_args"
            ;;
        all)
            test_all
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
