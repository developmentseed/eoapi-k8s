#!/bin/bash

# eoAPI Scripts - Minikube Cluster Management Library
# Handles minikube-specific cluster operations

set -euo pipefail

# Source required libraries
if ! declare -f log_info >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
    source "$SCRIPT_DIR/common.sh"
fi

# Minikube cluster configuration
MINIKUBE_DEFAULT_NAME="${CLUSTER_NAME:-eoapi-local}"
MINIKUBE_DEFAULT_DRIVER="${MINIKUBE_DRIVER:-docker}"
MINIKUBE_DEFAULT_MEMORY="${MINIKUBE_MEMORY:-4g}"
MINIKUBE_DEFAULT_CPUS="${MINIKUBE_CPUS:-2}"
MINIKUBE_DEFAULT_DISK="${MINIKUBE_DISK:-20g}"

# Create minikube cluster
minikube_create() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"
    local driver="${2:-$MINIKUBE_DEFAULT_DRIVER}"
    local memory="${3:-$MINIKUBE_DEFAULT_MEMORY}"
    local cpus="${4:-$MINIKUBE_DEFAULT_CPUS}"
    local disk="${5:-$MINIKUBE_DEFAULT_DISK}"

    log_info "Creating minikube cluster: $cluster_name"

    if minikube status -p "$cluster_name" >/dev/null 2>&1; then
        log_warn "Cluster '$cluster_name' already exists"
        return 0
    fi

    # Validate driver availability
    if ! validate_minikube_driver "$driver"; then
        log_error "Driver '$driver' is not available"
        return 1
    fi

    log_info "Creating minikube cluster with:"
    log_info "  Name: $cluster_name"
    log_info "  Driver: $driver"
    log_info "  Memory: $memory"
    log_info "  CPUs: $cpus"
    log_info "  Disk: $disk"

    local minikube_args=(
        start
        --profile "$cluster_name"
        --driver "$driver"
        --memory "$memory"
        --cpus "$cpus"
        --disk-size "$disk"
        --kubernetes-version stable
        --wait timeout=300s
    )

    # Don't add addons during creation - we'll add them after startup

    if ! minikube "${minikube_args[@]}"; then
        log_error "Failed to create minikube cluster: $cluster_name"
        return 1
    fi

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=300s; then
        log_error "Cluster nodes failed to become ready"
        return 1
    fi

    # Install addons after cluster is ready
    log_info "Installing addons..."
    minikube_install_addons "$cluster_name" "ingress" "dashboard" "metrics-server"

    log_info "✅ minikube cluster '$cluster_name' created successfully"

    # Show cluster info
    minikube_urls "$cluster_name"

    return 0
}

# Start minikube cluster
minikube_start() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"

    log_info "Starting minikube cluster: $cluster_name"

    local status
    status=$(minikube status -p "$cluster_name" --format="{{.Host}}" 2>/dev/null || echo "NotFound")

    case "$status" in
        "Running")
            log_info "Cluster '$cluster_name' is already running"
            return 0
            ;;
        "Stopped")
            log_info "Starting existing cluster: $cluster_name"
            ;;
        "NotFound")
            log_error "Cluster '$cluster_name' does not exist"
            log_info "Use 'minikube_create' to create it first"
            return 1
            ;;
        *)
            log_warn "Cluster '$cluster_name' is in unknown state: $status"
            ;;
    esac

    if ! minikube start --profile "$cluster_name"; then
        log_error "Failed to start minikube cluster: $cluster_name"
        return 1
    fi

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=180s; then
        log_error "Cluster failed to become ready after start"
        return 1
    fi

    log_info "✅ minikube cluster '$cluster_name' started successfully"
    return 0
}

# Stop minikube cluster
minikube_stop() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"

    log_info "Stopping minikube cluster: $cluster_name"

    local status
    status=$(minikube status -p "$cluster_name" --format="{{.Host}}" 2>/dev/null || echo "NotFound")

    case "$status" in
        "Stopped")
            log_info "Cluster '$cluster_name' is already stopped"
            return 0
            ;;
        "NotFound")
            log_warn "Cluster '$cluster_name' does not exist"
            return 0
            ;;
        "Running")
            log_info "Stopping running cluster: $cluster_name"
            ;;
        *)
            log_debug "Cluster '$cluster_name' status: $status"
            ;;
    esac

    if ! minikube stop --profile "$cluster_name"; then
        log_error "Failed to stop minikube cluster: $cluster_name"
        return 1
    fi

    log_info "✅ minikube cluster '$cluster_name' stopped successfully"
    return 0
}

# Delete minikube cluster
minikube_delete() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"

    log_info "Deleting minikube cluster: $cluster_name"

    if ! minikube status -p "$cluster_name" >/dev/null 2>&1; then
        log_info "Cluster '$cluster_name' does not exist"
        return 0
    fi

    if ! minikube delete --profile "$cluster_name"; then
        log_error "Failed to delete minikube cluster: $cluster_name"
        return 1
    fi

    log_info "✅ minikube cluster '$cluster_name' deleted successfully"
    return 0
}

# Show minikube cluster status
minikube_status() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"

    log_info "minikube cluster status: $cluster_name"

    if ! command_exists minikube; then
        log_error "minikube is not installed"
        return 1
    fi

    if ! minikube status -p "$cluster_name" >/dev/null 2>&1; then
        log_info "Cluster '$cluster_name' does not exist"
        log_info "Available profiles:"
        minikube profile list 2>/dev/null || log_warn "Cannot list profiles"
        return 0
    fi

    # Show detailed status
    log_info "Cluster '$cluster_name' status:"
    minikube status -p "$cluster_name" 2>/dev/null || log_warn "Cannot get cluster status"

    # Show additional info if running
    local host_status
    host_status=$(minikube status -p "$cluster_name" --format="{{.Host}}" 2>/dev/null || echo "Unknown")

    if [ "$host_status" = "Running" ]; then
        log_info "Cluster details:"
        kubectl cluster-info 2>/dev/null || log_warn "Cannot get cluster info"

        log_info "Nodes:"
        kubectl get nodes -o wide 2>/dev/null || log_warn "Cannot get nodes"

        log_info "Enabled addons:"
        minikube addons list -p "$cluster_name" 2>/dev/null | grep enabled || log_warn "Cannot get addons"
    fi

    return 0
}

# Set kubectl context for minikube cluster
minikube_context() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"

    log_info "Setting kubectl context for minikube cluster: $cluster_name"

    if ! minikube status -p "$cluster_name" >/dev/null 2>&1; then
        log_error "Cluster '$cluster_name' does not exist"
        return 1
    fi

    local context_name="$cluster_name"

    # Update kubeconfig
    if ! minikube update-context -p "$cluster_name"; then
        log_error "Failed to update kubectl context"
        return 1
    fi

    if ! kubectl config use-context "$context_name"; then
        log_error "Failed to set context: $context_name"
        return 1
    fi

    log_info "✅ kubectl context set to: $context_name"
    return 0
}

# Get cluster URLs
minikube_urls() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"

    if ! minikube status -p "$cluster_name" >/dev/null 2>&1; then
        log_error "Cluster '$cluster_name' does not exist"
        return 1
    fi

    local host_status
    host_status=$(minikube status -p "$cluster_name" --format="{{.Host}}" 2>/dev/null || echo "Unknown")

    if [ "$host_status" != "Running" ]; then
        log_error "Cluster '$cluster_name' is not running"
        return 1
    fi

    echo "minikube cluster URLs:"

    # Get cluster IP
    local cluster_ip
    cluster_ip=$(minikube ip -p "$cluster_name" 2>/dev/null || echo "unknown")
    echo "  Cluster IP: $cluster_ip"

    # Get service URLs
    echo "  Dashboard: $(minikube dashboard --url -p "$cluster_name" 2>/dev/null || echo 'run: minikube dashboard')"

    # Show service endpoints
    echo "Services (use 'minikube service <name> --url' to get URLs):"
    kubectl get services --all-namespaces 2>/dev/null | grep -v "ClusterIP.*<none>" || echo "  No external services found"

    return 0
}

# Validate minikube driver
validate_minikube_driver() {
    local driver="$1"

    case "$driver" in
        docker)
            if ! command_exists docker; then
                log_error "Docker is not installed"
                return 1
            fi
            if ! docker info >/dev/null 2>&1; then
                log_error "Docker daemon is not running"
                return 1
            fi
            ;;
        podman)
            if ! command_exists podman; then
                log_error "Podman is not installed"
                return 1
            fi
            ;;
        virtualbox)
            if ! command_exists VBoxManage; then
                log_error "VirtualBox is not installed"
                return 1
            fi
            ;;
        vmware)
            if ! command_exists vmrun; then
                log_error "VMware is not installed"
                return 1
            fi
            ;;
        kvm2)
            if ! command_exists virsh; then
                log_error "KVM/libvirt is not installed"
                return 1
            fi
            ;;
        hyperv)
            # Windows only - assume it's available if requested
            log_debug "Assuming Hyper-V is available"
            ;;
        *)
            log_warn "Unknown driver: $driver"
            ;;
    esac

    return 0
}

# Diagnose ingress controller issues
minikube_diagnose_ingress_issues() {
    local pod_status
    pod_status=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null || echo "No controller pod found")
    log_debug "Ingress controller pod: $pod_status"

    # Check for common issues
    if kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | grep -q "0/1.*Running"; then
        log_debug "Controller pod is running but not ready - checking recent events"
        kubectl get events -n ingress-nginx --sort-by='.lastTimestamp' --field-selector type=Warning | tail -3 2>/dev/null || true
    fi
}

# Install minikube addons
minikube_install_addons() {
    local cluster_name="$1"
    shift || true
    local addons=("$@")

    if [ ${#addons[@]} -eq 0 ]; then
        addons=("ingress" "dashboard" "metrics-server")
    fi

    log_info "Installing minikube addons: ${addons[*]}"

    for addon in "${addons[@]}"; do
        log_debug "Enabling addon: $addon"
        if ! minikube -p "$cluster_name" addons enable "$addon" >/dev/null 2>&1; then
            log_warn "Failed to enable addon: $addon"
        fi
    done

    # Wait for ingress controller if it was installed
    if [[ " ${addons[*]} " =~ " ingress " ]]; then
        log_info "Waiting for ingress controller to be ready..."
        local max_attempts=12  # 2 minutes total
        local attempt=0

        while [ $attempt -lt $max_attempts ]; do
            if kubectl wait --namespace ingress-nginx \
                --for=condition=ready pod \
                --selector=app.kubernetes.io/component=controller \
                --timeout=10s >/dev/null 2>&1; then
                log_debug "✅ Ingress controller is ready"
                break
            fi

            attempt=$((attempt + 1))

            # Show diagnostic info every 30 seconds (3 attempts)
            if [ $((attempt % 3)) -eq 0 ]; then
                minikube_diagnose_ingress_issues
            fi

            if [ $attempt -eq $max_attempts ]; then
                log_error "❌ Ingress controller failed to become ready within 2 minutes"
                log_error "Final diagnostic information:"
                minikube_diagnose_ingress_issues
                return 1
            fi

            log_debug "Waiting for ingress controller... (attempt $attempt/$max_attempts)"
            sleep 10
        done
    fi

    return 0
}

# Get minikube logs
minikube_logs() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"

    log_info "Getting logs for minikube cluster: $cluster_name"

    if ! minikube status -p "$cluster_name" >/dev/null 2>&1; then
        log_error "Cluster '$cluster_name' does not exist"
        return 1
    fi

    minikube logs -p "$cluster_name"
    return 0
}

# Cleanup minikube resources
minikube_cleanup() {
    local cluster_name="${1:-$MINIKUBE_DEFAULT_NAME}"

    log_info "Cleaning up minikube resources..."

    # Stop and delete cluster
    minikube_stop "$cluster_name" 2>/dev/null || true
    minikube_delete "$cluster_name" 2>/dev/null || true

    # Cleanup docker containers if using docker driver
    if [ "${MINIKUBE_DEFAULT_DRIVER}" = "docker" ] && command_exists docker; then
        local containers
        containers=$(docker ps -a --filter "label=created_by.minikube.sigs.k8s.io" --filter "label=name.minikube.sigs.k8s.io=$cluster_name" -q 2>/dev/null || echo "")
        if [ -n "$containers" ]; then
            log_debug "Cleaning up leftover containers"
            docker rm -f "$containers" 2>/dev/null || true
        fi
    fi

    log_info "✅ minikube resources cleaned up"
    return 0
}

# Export functions
export -f minikube_create minikube_start minikube_stop minikube_delete minikube_status
export -f minikube_context minikube_urls minikube_cleanup minikube_install_addons minikube_logs
export -f validate_minikube_driver
