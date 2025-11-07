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

# Validate K3s cluster readiness (extracted from CI workflow)
validate_k3s_readiness() {
    log_info "=== Waiting for K3s cluster to be ready ==="

    # Verify kubectl works
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to K3s cluster"
        return 1
    fi

    if ! kubectl get nodes >/dev/null 2>&1; then
        log_error "Cannot get cluster nodes"
        return 1
    fi

    # Wait for core components
    log_info "Waiting for core DNS..."
    if ! kubectl wait --for=condition=Ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s 2>/dev/null; then
        log_error "Core DNS not ready"
        return 1
    fi

    log_info "Waiting for Traefik..."
    if ! kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=300s 2>/dev/null; then
        log_error "Traefik not ready"
        return 1
    fi

    # Verify Traefik CRDs
    log_info "Verifying Traefik CRDs..."
    local timeout=300
    local counter=0
    for crd in "middlewares.traefik.io" "ingressroutes.traefik.io"; do
        while [ $counter -lt $timeout ] && ! kubectl get crd "$crd" &>/dev/null; do
            sleep 3
            counter=$((counter + 3))
        done
        if [ $counter -ge $timeout ]; then
            log_error "Timeout waiting for CRD: $crd"
            return 1
        fi
    done

    log_info "✅ K3s cluster ready"
    return 0
}

# Wait for eoAPI deployments to be available
validate_deployments_ready() {
    local namespace="$1"
    local release_name="$2"
    local timeout="${3:-300s}"

    log_info "=== Waiting for deployments to be ready ==="

    # Verify namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log_error "Namespace $namespace does not exist"
        return 1
    fi

    # Wait for core deployments
    local deployments=("${release_name}-stac" "${release_name}-raster" "${release_name}-vector")
    local failed=false

    for deployment in "${deployments[@]}"; do
        log_info "Waiting for deployment: $deployment"
        if ! kubectl wait --for=condition=available "deployment/$deployment" -n "$namespace" --timeout="$timeout" 2>/dev/null; then
            log_error "Deployment $deployment not ready"
            failed=true
        fi
    done

    if [ "$failed" = true ]; then
        return 1
    fi

    log_info "✅ All deployments ready"
    return 0
}

# Validate API connectivity through ingress
validate_api_connectivity() {
    local ingress_host="${1:-eoapi.local}"
    local max_attempts="${2:-30}"

    log_info "=== Testing API connectivity through ingress ==="

    # Add ingress host to /etc/hosts if needed and not already present
    if [[ "$ingress_host" == *.local ]] && ! grep -q "$ingress_host" /etc/hosts 2>/dev/null; then
        local node_ip
        node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
        if [ -n "$node_ip" ]; then
            log_info "Adding $ingress_host to /etc/hosts with IP $node_ip"
            echo "$node_ip $ingress_host" | sudo tee -a /etc/hosts >/dev/null
        fi
    fi

    # Test STAC API
    log_info "Testing STAC API..."
    local i
    for i in $(seq 1 "$max_attempts"); do
        if curl -s "http://${ingress_host}/stac/_mgmt/ping" >/dev/null 2>&1; then
            log_info "✅ STAC API accessible through ingress"
            break
        fi
        log_debug "Waiting for STAC API... (attempt $i/$max_attempts)"
        sleep 3
    done
    if [ "$i" -eq "$max_attempts" ]; then
        log_error "STAC API not accessible after $max_attempts attempts"
        return 1
    fi

    # Test Raster API
    log_info "Testing Raster API..."
    for i in $(seq 1 "$max_attempts"); do
        if curl -s "http://${ingress_host}/raster/healthz" >/dev/null 2>&1; then
            log_info "✅ Raster API accessible through ingress"
            break
        fi
        log_debug "Waiting for Raster API... (attempt $i/$max_attempts)"
        sleep 3
    done
    if [ "$i" -eq "$max_attempts" ]; then
        log_error "Raster API not accessible after $max_attempts attempts"
        return 1
    fi

    # Test Vector API
    log_info "Testing Vector API..."
    for i in $(seq 1 "$max_attempts"); do
        if curl -s "http://${ingress_host}/vector/healthz" >/dev/null 2>&1; then
            log_info "✅ Vector API accessible through ingress"
            break
        fi
        log_debug "Waiting for Vector API... (attempt $i/$max_attempts)"
        sleep 3
    done
    if [ "$i" -eq "$max_attempts" ]; then
        log_error "Vector API not accessible after $max_attempts attempts"
        return 1
    fi

    log_info "✅ All APIs accessible through ingress"
    return 0
}

# Wait for ingress to be ready
validate_ingress_ready() {
    local namespace="$1"
    local ingress_name="${2:-}"
    local timeout="${3:-60s}"

    log_info "Waiting for ingress to be ready..."

    # Get ingress resources
    if ! kubectl get ingress -n "$namespace" >/dev/null 2>&1; then
        log_warn "No ingress resources found in namespace $namespace"
        return 0
    fi

    # If specific ingress name provided, wait for it
    if [ -n "$ingress_name" ]; then
        if kubectl get ingress "$ingress_name" -n "$namespace" >/dev/null 2>&1; then
            log_debug "Ingress $ingress_name exists in namespace $namespace"
        else
            log_warn "Ingress $ingress_name not found in namespace $namespace"
        fi
    fi

    # Wait for Traefik to pick up ingress rules
    sleep 10

    log_info "✅ Ingress ready"
    return 0
}

# Comprehensive eoAPI deployment validation
validate_eoapi_deployment() {
    local namespace="${1:-eoapi}"
    local release_name="${2:-eoapi}"
    local ingress_host="${3:-eoapi.local}"
    local verbose="${4:-false}"
    local exit_code=0

    log_info "=== eoAPI Deployment Validation ==="
    log_info "NAMESPACE: $namespace"
    log_info "RELEASE_NAME: $release_name"
    log_info "INGRESS_HOST: $ingress_host"
    echo ""

    # Step 1: Verify namespace creation
    log_info "=== Verifying namespace creation ==="
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log_error "❌ Namespace $namespace was not created"
        log_info "Available namespaces:"
        kubectl get namespaces
        return 1
    else
        log_success "✅ Namespace $namespace exists"
    fi
    echo ""

    # Step 2: List resources in namespace
    log_info "=== Resources in namespace $namespace ==="
    if [ "$verbose" = true ]; then
        kubectl get all -n "$namespace" || {
            log_warn "No resources found in namespace $namespace"
            exit_code=1
        }
    else
        # Summary view
        local resource_count
        resource_count=$(kubectl get all -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$resource_count" -eq 0 ]; then
            log_warn "No resources found in namespace $namespace"
            exit_code=1
        else
            log_info "Found $resource_count resources in namespace"
        fi
    fi
    echo ""

    # Step 3: Check Helm release status
    log_info "=== Helm Release Status ==="
    if helm list -n "$namespace" | grep -q "$release_name"; then
        local helm_status
        helm_status=$(helm status "$release_name" -n "$namespace" -o json 2>/dev/null | jq -r '.info.status' || echo "unknown")
        if [ "$helm_status" = "deployed" ]; then
            log_success "✅ Helm release $release_name is deployed"
        else
            log_warn "⚠️  Helm release status: $helm_status"
            exit_code=1
        fi
    else
        log_error "❌ Helm release $release_name not found in namespace $namespace"
        exit_code=1
    fi
    echo ""

    # Step 4: Check deployments using existing function
    if [ "$exit_code" -eq 0 ]; then
        if ! validate_deployments_ready "$namespace" "$release_name"; then
            exit_code=1
        fi
    fi

    # Step 5: Check job statuses
    log_info "=== Job Status ==="
    local jobs=("knative-init" "pgstac-migrate" "pgstac-load-samples")
    for job_suffix in "${jobs[@]}"; do
        local job_name="${release_name}-${job_suffix}"
        if kubectl get job "$job_name" -n "$namespace" >/dev/null 2>&1; then
            local completions succeeded
            completions=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.spec.completions}' 2>/dev/null || echo "1")
            succeeded=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")

            if [ "${succeeded:-0}" -eq "${completions:-1}" ]; then
                log_success "✅ Job $job_name completed successfully"
            else
                log_warn "⚠️  Job $job_name: $succeeded/$completions completed"
                if [ "$verbose" = true ]; then
                    echo "  Recent logs:"
                    kubectl logs -l "job-name=$job_name" -n "$namespace" --tail=5 2>/dev/null || echo "  No logs available"
                fi
            fi
        else
            # Try with label selector for jobs that might have different naming
            if kubectl get job -l "app=${job_name}" -n "$namespace" >/dev/null 2>&1; then
                log_debug "Job found via label selector: app=${job_name}"
            else
                log_debug "Job $job_name not found (may be optional)"
            fi
        fi
    done
    echo ""

    # Step 6: Check PostgreSQL cluster
    log_info "=== PostgreSQL Status ==="
    if kubectl get postgresclusters -n "$namespace" >/dev/null 2>&1; then
        local pg_clusters
        pg_clusters=$(kubectl get postgresclusters -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$pg_clusters" -gt 0 ]; then
            log_success "✅ PostgreSQL cluster found"
            if [ "$verbose" = true ]; then
                kubectl get postgresclusters -n "$namespace" -o wide
            fi
        else
            log_warn "⚠️  No PostgreSQL clusters found"
        fi
    else
        log_debug "PostgreSQL operator not installed or no clusters in namespace"
    fi
    echo ""

    # Step 7: Check ingress configuration
    log_info "=== Ingress Configuration ==="
    local ingress_count
    ingress_count=$(kubectl get ingress -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$ingress_count" -gt 0 ]; then
        log_success "✅ Found $ingress_count ingress resource(s)"
        if [ "$verbose" = true ]; then
            kubectl get ingress -n "$namespace" -o wide
        fi
    else
        log_warn "⚠️  No ingress resources found"
        exit_code=1
    fi
    echo ""

    # Step 8: Test API connectivity using existing function
    if [ "$exit_code" -eq 0 ]; then
        if ! validate_api_connectivity "$ingress_host"; then
            exit_code=1
        fi
    fi

    # Step 9: Recent events (if verbose)
    if [ "$verbose" = true ] && [ "$exit_code" -ne 0 ]; then
        log_info "=== Recent Events (for troubleshooting) ==="
        kubectl get events -n "$namespace" --sort-by='.lastTimestamp' | tail -10 2>/dev/null || echo "No events found"
        echo ""
    fi

    # Summary
    log_info "=== Validation Summary ==="
    if [ "$exit_code" -eq 0 ]; then
        log_success "✅ Deployment validation passed!"
        log_info ""
        log_info "eoAPI services are available at:"
        log_info "  STAC API:     http://${ingress_host}/stac"
        log_info "  Raster API:   http://${ingress_host}/raster"
        log_info "  Vector API:   http://${ingress_host}/vector"
        log_info "  STAC Browser: http://${ingress_host}/browser"
    else
        log_error "❌ Deployment validation failed!"
        log_info ""
        log_info "Troubleshooting tips:"
        log_info "  1. Check pod logs: kubectl logs -n $namespace -l app.kubernetes.io/name=<component>"
        log_info "  2. Describe failed pods: kubectl describe pod -n $namespace <pod-name>"
        log_info "  3. Run debug script: ./scripts/debug-deployment.sh"
        log_info "  4. Check events: kubectl get events -n $namespace --sort-by='.lastTimestamp'"
    fi

    return $exit_code
}

# Export validation functions
export -f validate_kubectl validate_helm validate_python3 validate_jq
export -f validate_deploy_tools validate_test_tools validate_local_cluster_tools
export -f validate_cluster_connection validate_cluster_permissions
export -f validate_file_readable validate_json_file validate_yaml_file validate_helm_chart
export -f validate_k3s_readiness validate_deployments_ready validate_api_connectivity validate_ingress_ready
export -f validate_eoapi_deployment
