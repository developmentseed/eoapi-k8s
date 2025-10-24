#!/bin/bash

# eoAPI Scripts - Shared Utilities Library
# Source this file in other scripts: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1" >&2; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate required tools
validate_tools() {
    local tools=("$@")
    local missing=()

    for tool in "${tools[@]}"; do
        if ! command_exists "$tool"; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        return 1
    fi

    log_debug "All required tools available: ${tools[*]}"
    return 0
}

# Check Kubernetes cluster connectivity
validate_cluster() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Ensure kubectl is configured and cluster is accessible"
        return 1
    fi

    local context
    context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_debug "Connected to cluster: $context"
    return 0
}

# Detect CI environment
is_ci_environment() {
    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" || -n "${JENKINS_URL:-}" ]]
}

# Validate namespace exists or can be created
validate_namespace() {
    local namespace="${1:-}"

    if [ -z "$namespace" ]; then
        log_error "Namespace not specified"
        return 1
    fi

    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log_debug "Namespace '$namespace' exists"
        return 0
    fi

    log_warn "Namespace '$namespace' does not exist"
    return 1
}

# Auto-detect release name from deployed resources
detect_release_name() {
    local namespace="${1:-}"

    # Try helm releases first
    local release_name
    release_name=$(helm list ${namespace:+-n "$namespace"} -o json 2>/dev/null | \
                  jq -r '.[] | select(.name | contains("eoapi")) | .name' 2>/dev/null | head -1 || echo "")

    # Fallback to pod labels
    if [ -z "$release_name" ]; then
        release_name=$(kubectl get pods ${namespace:+-n "$namespace"} \
                      -l app.kubernetes.io/name=stac -o jsonpath='{.items[0].metadata.labels.app\.kubernetes\.io/instance}' \
                      2>/dev/null || echo "eoapi")
    fi

    echo "${release_name:-eoapi}"
}

# Auto-detect namespace from deployed eoAPI resources
detect_namespace() {
    kubectl get pods --all-namespaces -l app.kubernetes.io/name=stac \
        -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || echo "eoapi"
}

# Wait for pods with label selector
wait_for_pods() {
    local namespace="$1"
    local selector="$2"
    local timeout="${3:-300s}"

    log_info "Waiting for pods with selector: $selector"

    if ! kubectl wait --for=condition=Ready pod -l "$selector" -n "$namespace" --timeout="$timeout" 2>/dev/null; then
        log_error "Pods failed to become ready: $selector"
        kubectl get pods -n "$namespace" -l "$selector" -o wide 2>/dev/null || true
        return 1
    fi

    return 0
}

# Check if eoAPI is deployed
validate_eoapi_deployment() {
    local namespace="$1"
    local release_name="$2"

    log_info "Validating eoAPI deployment in namespace: $namespace"

    local services=("stac" "raster" "vector")
    local missing_services=()

    for service in "${services[@]}"; do
        local patterns=(
            "app.kubernetes.io/instance=$release_name,app.kubernetes.io/name=$service"
            "app=$release_name-$service"
        )

        local found=false
        for pattern in "${patterns[@]}"; do
            if kubectl get pods -n "$namespace" -l "$pattern" >/dev/null 2>&1; then
                found=true
                break
            fi
        done

        if [ "$found" = false ]; then
            missing_services+=("$service")
        fi
    done

    if [ ${#missing_services[@]} -ne 0 ]; then
        log_error "Missing eoAPI services: ${missing_services[*]}"
        return 1
    fi

    log_info "eoAPI deployment validated successfully"
    return 0
}

# Pre-flight checks for deployment
preflight_deploy() {
    log_info "Running pre-flight checks for deployment..."

    validate_tools kubectl helm || return 1
    validate_cluster || return 1

    # Check Helm repositories are accessible
    if ! helm repo list >/dev/null 2>&1; then
        log_warn "No Helm repositories configured"
    fi

    log_info "✅ Pre-flight checks passed"
    return 0
}

# Pre-flight checks for ingestion
preflight_ingest() {
    local namespace="$1"
    local collections_file="$2"
    local items_file="$3"

    log_info "Running pre-flight checks for ingestion..."

    validate_tools kubectl || return 1
    validate_cluster || return 1
    validate_namespace "$namespace" || return 1

    # Check input files
    for file in "$collections_file" "$items_file"; do
        if [ ! -f "$file" ]; then
            log_error "Input file not found: $file"
            return 1
        fi

        if [ ! -s "$file" ]; then
            log_error "Input file is empty: $file"
            return 1
        fi

        # Basic JSON validation
        if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
            log_error "Invalid JSON in file: $file"
            return 1
        fi
    done

    log_info "✅ Pre-flight checks passed"
    return 0
}

# Pre-flight checks for testing
preflight_test() {
    local test_type="$1"

    log_info "Running pre-flight checks for $test_type tests..."

    case "$test_type" in
        helm)
            validate_tools helm || return 1
            ;;
        integration)
            validate_tools kubectl python3 || return 1
            validate_cluster || return 1
            ;;
        observability)
            validate_tools kubectl python3 || return 1
            validate_cluster || return 1
            ;;
        *)
            log_error "Unknown test type: $test_type"
            return 1
            ;;
    esac

    log_info "✅ Pre-flight checks passed"
    return 0
}

# Cleanup function for trapped errors
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code: $exit_code"
    fi
}

# Set up error handling
trap cleanup_on_exit EXIT

# Export functions for use in other scripts
export -f log_info log_warn log_error log_debug
export -f command_exists validate_tools validate_cluster
export -f is_ci_environment validate_namespace
export -f detect_release_name detect_namespace
export -f wait_for_pods validate_eoapi_deployment
export -f preflight_deploy preflight_ingest preflight_test
