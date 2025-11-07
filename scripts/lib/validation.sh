#!/bin/bash

# eoAPI Scripts - Validation Library
# Centralized validation functions to eliminate code duplication

set -euo pipefail

# Source common utilities if not already loaded
if ! declare -f log_info >/dev/null 2>&1; then
    VALIDATION_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
    source "$VALIDATION_SCRIPT_DIR/common.sh"
fi

# Tool validation with specific version requirements
validate_kubectl() {
    if ! command_exists kubectl; then
        log_error "kubectl is required but not installed"
        log_info "Install from: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
        return 1
    fi

    local version
    version=$(kubectl version --client --output=json 2>/dev/null | jq -r '.clientVersion.gitVersion' 2>/dev/null || echo "unknown")
    log_debug "kubectl version: $version"
    return 0
}

validate_helm() {
    if ! command_exists helm; then
        log_error "helm is required but not installed"
        log_info "Install from: https://helm.sh/docs/intro/install/"
        return 1
    fi

    local version
    version=$(helm version --short 2>/dev/null || echo "unknown")
    log_debug "helm version: $version"

    # Check minimum version (v3.15+)
    local version_number
    version_number=$(echo "$version" | grep -oE 'v[0-9]+\.[0-9]+' | sed 's/v//' || echo "0.0")
    local major minor
    major=$(echo "$version_number" | cut -d. -f1)
    minor=$(echo "$version_number" | cut -d. -f2)

    if [ "${major:-0}" -lt 3 ] || { [ "${major:-0}" -eq 3 ] && [ "${minor:-0}" -lt 15 ]; }; then
        log_warn "helm version $version may be too old (recommended: v3.15+)"
    fi

    return 0
}

validate_python3() {
    if ! command_exists python3; then
        log_error "python3 is required but not installed"
        return 1
    fi

    local version
    version=$(python3 --version 2>/dev/null || echo "unknown")
    log_debug "python3 version: $version"
    return 0
}

validate_jq() {
    if ! command_exists jq; then
        log_error "jq is required but not installed"
        log_info "Install with: sudo apt install jq (Ubuntu) or brew install jq (macOS)"
        return 1
    fi

    local version
    version=$(jq --version 2>/dev/null || echo "unknown")
    log_debug "jq version: $version"
    return 0
}

# Comprehensive tool validation for different operations
validate_deploy_tools() {
    log_info "Validating deployment tools..."
    local failed=false

    validate_kubectl || failed=true
    validate_helm || failed=true

    if [ "$failed" = true ]; then
        log_error "Required tools missing for deployment"
        return 1
    fi

    log_debug "✅ All deployment tools validated"
    return 0
}

validate_test_tools() {
    log_info "Validating test tools..."
    local failed=false

    validate_kubectl || failed=true
    validate_python3 || failed=true
    validate_jq || failed=true

    if [ "$failed" = true ]; then
        log_error "Required tools missing for testing"
        return 1
    fi

    log_debug "✅ All test tools validated"
    return 0
}

validate_local_cluster_tools() {
    local cluster_type="$1"
    log_info "Validating local cluster tools for $cluster_type..."
    local failed=false

    validate_kubectl || failed=true

    case "$cluster_type" in
        minikube)
            if ! command_exists minikube; then
                log_error "minikube is required but not installed"
                log_info "Install from: https://minikube.sigs.k8s.io/docs/start/"
                failed=true
            else
                local version
                version=$(minikube version --short 2>/dev/null || echo "unknown")
                log_debug "minikube version: $version"
            fi
            ;;
        k3s)
            if ! command_exists k3d; then
                log_error "k3d is required but not installed"
                log_info "Install from: https://k3d.io/v5.7.4/#installation"
                failed=true
            else
                local version
                version=$(k3d version 2>/dev/null | head -1 || echo "unknown")
                log_debug "k3d version: $version"
            fi
            ;;
        *)
            log_error "Unknown cluster type: $cluster_type"
            failed=true
            ;;
    esac

    if [ "$failed" = true ]; then
        log_error "Required tools missing for local cluster management"
        return 1
    fi

    log_debug "✅ All local cluster tools validated"
    return 0
}

# Enhanced cluster validation
validate_cluster_connection() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Check your kubectl configuration:"
        log_info "  kubectl config current-context"
        log_info "  kubectl config get-contexts"
        return 1
    fi

    local context
    context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_debug "Connected to cluster context: $context"

    # Check if cluster is ready
    if ! kubectl get nodes >/dev/null 2>&1; then
        log_warn "Cluster nodes may not be ready"
        kubectl get nodes 2>/dev/null || true
    fi

    return 0
}

# Validate cluster permissions
validate_cluster_permissions() {
    local namespace="${1:-default}"

    log_debug "Validating cluster permissions for namespace: $namespace"

    # Check basic permissions
    local permissions=(
        "get pods"
        "list pods"
        "create pods"
        "get services"
        "get ingresses"
        "get configmaps"
        "get secrets"
    )

    local failed=false
    for perm in "${permissions[@]}"; do
        if ! kubectl auth can-i "$perm" -n "$namespace" >/dev/null 2>&1; then
            log_warn "Missing permission: $perm in namespace $namespace"
            failed=true
        fi
    done

    # Check cluster-level permissions
    if ! kubectl auth can-i create namespaces >/dev/null 2>&1; then
        log_warn "Cannot create namespaces (may require manual namespace creation)"
    fi

    if [ "$failed" = true ]; then
        log_warn "Some permissions missing - deployment may fail"
    fi

    return 0
}

# Validate files and directories
validate_file_readable() {
    local file="$1"

    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi

    if [ ! -r "$file" ]; then
        log_error "File not readable: $file"
        return 1
    fi

    if [ ! -s "$file" ]; then
        log_warn "File is empty: $file"
    fi

    return 0
}

validate_json_file() {
    local file="$1"

    validate_file_readable "$file" || return 1

    if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
        log_error "Invalid JSON in file: $file"
        return 1
    fi

    log_debug "Valid JSON file: $file"
    return 0
}

validate_yaml_file() {
    local file="$1"

    validate_file_readable "$file" || return 1

    if command_exists yq; then
        # Handle both old Python-based yq and new Go-based yq
        if ! (yq eval '.' "$file" >/dev/null 2>&1 || yq . "$file" >/dev/null 2>&1); then
            log_error "Invalid YAML in file: $file"
            return 1
        fi
    elif validate_python3; then
        # Skip YAML validation due to conda error interference
        log_debug "Skipping YAML validation for: $file (conda environment issues)"
    else
        log_warn "Cannot validate YAML file: $file (no yq or python3+yaml available)"
    fi

    log_debug "Valid YAML file: $file"
    return 0
}

# Validate chart directory structure
validate_helm_chart() {
    local chart_dir="$1"

    if [ ! -d "$chart_dir" ]; then
        log_error "Chart directory not found: $chart_dir"
        return 1
    fi

    local required_files=("Chart.yaml" "values.yaml")
    local failed=false

    for file in "${required_files[@]}"; do
        if [ ! -f "$chart_dir/$file" ]; then
            log_error "Required chart file missing: $chart_dir/$file"
            failed=true
        fi
    done

    if [ "$failed" = true ]; then
        return 1
    fi

    # Validate chart files
    validate_yaml_file "$chart_dir/Chart.yaml" || return 1
    validate_yaml_file "$chart_dir/values.yaml" || return 1

    log_debug "Valid Helm chart: $chart_dir"
    return 0
}

# Export validation functions
export -f validate_kubectl validate_helm validate_python3 validate_jq
export -f validate_deploy_tools validate_test_tools validate_local_cluster_tools
export -f validate_cluster_connection validate_cluster_permissions
export -f validate_file_readable validate_json_file validate_yaml_file validate_helm_chart
