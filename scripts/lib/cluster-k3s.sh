#!/bin/bash

# eoAPI Scripts - k3s Cluster Management Library
# Handles k3s-specific cluster operations

set -euo pipefail

# Source required libraries
if ! declare -f log_info >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
    source "$SCRIPT_DIR/common.sh"
fi

# k3s cluster configuration
K3S_DEFAULT_NAME="${CLUSTER_NAME:-eoapi-local}"
K3S_DEFAULT_HTTP_PORT="${HTTP_PORT:-8080}"
K3S_DEFAULT_HTTPS_PORT="${HTTPS_PORT:-8443}"
K3S_REGISTRY_PORT="${K3S_REGISTRY_PORT:-5001}"

# Create k3s cluster
k3s_create() {
    local cluster_name="${1:-$K3S_DEFAULT_NAME}"
    local http_port="${2:-$K3S_DEFAULT_HTTP_PORT}"
    local https_port="${3:-$K3S_DEFAULT_HTTPS_PORT}"

    log_info "Creating k3s cluster: $cluster_name"

    if k3d cluster list | grep -q "^$cluster_name "; then
        log_warn "Cluster '$cluster_name' already exists"
        return 0
    fi

    # Check port availability
    if ! check_port_available "$http_port"; then
        log_error "Port $http_port is already in use"
        return 1
    fi

    if ! check_port_available "$https_port"; then
        log_error "Port $https_port is already in use"
        return 1
    fi

    # Create cluster with ingress controller
    log_info "Creating k3s cluster with ports HTTP:$http_port, HTTPS:$https_port"

    local k3d_args=(
        cluster create "$cluster_name"
        --api-port 6550
        --servers 1
        --agents 1
        --port "$http_port:80@loadbalancer"
        --port "$https_port:443@loadbalancer"
        --k3s-arg "--disable=servicelb@server:*"
        --registry-create "$cluster_name-registry:0.0.0.0:$K3S_REGISTRY_PORT"
        --wait
    )

    if ! k3d "${k3d_args[@]}"; then
        log_error "Failed to create k3s cluster: $cluster_name"
        return 1
    fi

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=120s; then
        log_error "Cluster nodes failed to become ready"
        return 1
    fi

    # Wait for Traefik to be ready
    wait_for_traefik || {
        log_error "Failed to wait for Traefik ingress controller"
        return 1
    }

    log_info "✅ k3s cluster '$cluster_name' created successfully"
    log_info "Cluster endpoints:"
    log_info "  HTTP: http://localhost:$http_port"
    log_info "  HTTPS: https://localhost:$https_port"
    log_info "  Registry: localhost:$K3S_REGISTRY_PORT"

    return 0
}

# Start k3s cluster
k3s_start() {
    local cluster_name="${1:-$K3S_DEFAULT_NAME}"

    log_info "Starting k3s cluster: $cluster_name"

    if ! k3d cluster list | grep -q "^$cluster_name "; then
        log_error "Cluster '$cluster_name' does not exist"
        log_info "Use 'k3s_create' to create it first"
        return 1
    fi

    if k3d cluster list | grep "^$cluster_name " | grep -q "running"; then
        log_info "Cluster '$cluster_name' is already running"
        return 0
    fi

    if ! k3d cluster start "$cluster_name"; then
        log_error "Failed to start k3s cluster: $cluster_name"
        return 1
    fi

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=60s; then
        log_error "Cluster failed to become ready after start"
        return 1
    fi

    log_info "✅ k3s cluster '$cluster_name' started successfully"
    return 0
}

# Stop k3s cluster
k3s_stop() {
    local cluster_name="${1:-$K3S_DEFAULT_NAME}"

    log_info "Stopping k3s cluster: $cluster_name"

    if ! k3d cluster list | grep -q "^$cluster_name "; then
        log_warn "Cluster '$cluster_name' does not exist"
        return 0
    fi

    if ! k3d cluster list | grep "^$cluster_name " | grep -q "running"; then
        log_info "Cluster '$cluster_name' is already stopped"
        return 0
    fi

    if ! k3d cluster stop "$cluster_name"; then
        log_error "Failed to stop k3s cluster: $cluster_name"
        return 1
    fi

    log_info "✅ k3s cluster '$cluster_name' stopped successfully"
    return 0
}

# Delete k3s cluster
k3s_delete() {
    local cluster_name="${1:-$K3S_DEFAULT_NAME}"

    log_info "Deleting k3s cluster: $cluster_name"

    if ! k3d cluster list | grep -q "^$cluster_name "; then
        log_info "Cluster '$cluster_name' does not exist"
        return 0
    fi

    # Delete associated registry
    local registry_name="$cluster_name-registry"
    if k3d registry list | grep -q "$registry_name"; then
        log_debug "Deleting registry: $registry_name"
        k3d registry delete "$registry_name" 2>/dev/null || true
    fi

    if ! k3d cluster delete "$cluster_name"; then
        log_error "Failed to delete k3s cluster: $cluster_name"
        return 1
    fi

    log_info "✅ k3s cluster '$cluster_name' deleted successfully"
    return 0
}

# Show k3s cluster status
k3s_status() {
    local cluster_name="${1:-$K3S_DEFAULT_NAME}"

    log_info "k3s cluster status: $cluster_name"

    if ! command_exists k3d; then
        log_error "k3d is not installed"
        return 1
    fi

    # Show specific cluster status
    if k3d cluster list | grep -q "^$cluster_name "; then
        local status
        status=$(k3d cluster list | grep "^$cluster_name " | awk '{print $2}')
        log_info "Cluster '$cluster_name' status: $status"

        if [ "$status" = "running" ]; then
            # Show more details for running cluster
            log_info "Cluster details:"
            kubectl cluster-info 2>/dev/null || log_warn "Cannot get cluster info"

            log_info "Nodes:"
            kubectl get nodes -o wide 2>/dev/null || log_warn "Cannot get nodes"

            # Show port mappings
            local ports
            ports=$(k3d cluster list "$cluster_name" -o json 2>/dev/null | jq -r '.[0].network.externalIP // "unknown"' 2>/dev/null || echo "unknown")
            if [ "$ports" != "unknown" ]; then
                log_info "External access: $ports"
            fi
        fi
    else
        log_info "Cluster '$cluster_name' does not exist"
        log_info "Available clusters:"
        k3d cluster list 2>/dev/null || log_warn "Cannot list clusters"
    fi

    return 0
}

# Set kubectl context for k3s cluster
k3s_context() {
    local cluster_name="${1:-$K3S_DEFAULT_NAME}"

    log_info "Setting kubectl context for k3s cluster: $cluster_name"

    if ! k3d cluster list | grep -q "^$cluster_name "; then
        log_error "Cluster '$cluster_name' does not exist"
        return 1
    fi

    local context_name="k3d-$cluster_name"

    if ! kubectl config use-context "$context_name"; then
        log_error "Failed to set context: $context_name"
        return 1
    fi

    log_info "✅ kubectl context set to: $context_name"
    return 0
}

# Get cluster URLs
k3s_urls() {
    local cluster_name="${1:-$K3S_DEFAULT_NAME}"

    if ! k3d cluster list | grep -q "^$cluster_name "; then
        log_error "Cluster '$cluster_name' does not exist"
        return 1
    fi

    if ! k3d cluster list | grep "^$cluster_name " | grep -q "running"; then
        log_error "Cluster '$cluster_name' is not running"
        return 1
    fi

    # Extract port mappings
    local http_port https_port
    http_port=$(k3d cluster list "$cluster_name" -o json 2>/dev/null | \
                jq -r '.[0].nodes[] | select(.role == "loadbalancer") | .portMappings."80/tcp"[0].HostPort' 2>/dev/null || echo "$K3S_DEFAULT_HTTP_PORT")
    https_port=$(k3d cluster list "$cluster_name" -o json 2>/dev/null | \
                 jq -r '.[0].nodes[] | select(.role == "loadbalancer") | .portMappings."443/tcp"[0].HostPort' 2>/dev/null || echo "$K3S_DEFAULT_HTTPS_PORT")

    echo "k3s cluster URLs:"
    echo "  HTTP: http://localhost:${http_port:-$K3S_DEFAULT_HTTP_PORT}"
    echo "  HTTPS: https://localhost:${https_port:-$K3S_DEFAULT_HTTPS_PORT}"
    echo "  Registry: localhost:$K3S_REGISTRY_PORT"

    return 0
}

# Wait for Traefik to be ready (k3s built-in)
wait_for_traefik() {
    log_info "Waiting for Traefik ingress controller to be ready..."

    # Wait for Traefik CRD installation job to complete
    log_info "Waiting for Traefik CRD installation..."
    if ! kubectl wait --namespace kube-system \
        --for=condition=complete job/helm-install-traefik-crd \
        --timeout=180s; then
        log_error "Traefik CRD installation job failed"
        return 1
    fi

    # Wait for Traefik installation job to complete
    log_info "Waiting for Traefik installation..."
    if ! kubectl wait --namespace kube-system \
        --for=condition=complete job/helm-install-traefik \
        --timeout=180s; then
        log_error "Traefik installation job failed"
        return 1
    fi

    # Wait for Traefik deployment to be ready
    log_info "Waiting for Traefik deployment..."
    if ! kubectl wait --namespace kube-system \
        --for=condition=available deployment/traefik \
        --timeout=180s; then
        log_error "Traefik deployment failed to become available"
        return 1
    fi

    # Wait for Traefik pods to be ready
    if ! kubectl wait --namespace kube-system \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=traefik \
        --timeout=180s; then
        log_error "Traefik pods failed to become ready"
        return 1
    fi

    log_info "✅ Traefik ingress controller is ready"
    return 0
}

# Check if port is available
check_port_available() {
    local port="$1"

    if command_exists ss; then
        ss -tuln | grep -q ":$port " && return 1 || return 0
    elif command_exists netstat; then
        netstat -tuln 2>/dev/null | grep -q ":$port " && return 1 || return 0
    else
        # Fallback: try to bind to the port
        if command_exists python3; then
            python3 -c "import socket; s=socket.socket(); s.bind(('', $port)); s.close()" 2>/dev/null
        else
            log_warn "Cannot check port availability"
            return 0
        fi
    fi
}

# Cleanup k3s resources
k3s_cleanup() {
    local cluster_name="${1:-$K3S_DEFAULT_NAME}"

    log_info "Cleaning up k3s resources..."

    # Stop and delete cluster
    k3s_stop "$cluster_name" 2>/dev/null || true
    k3s_delete "$cluster_name" 2>/dev/null || true

    # Cleanup any leftover containers
    if command_exists docker; then
        local containers
        containers=$(docker ps -a --filter "label=app=k3d" --filter "label=k3d.cluster=$cluster_name" -q 2>/dev/null || echo "")
        if [ -n "$containers" ]; then
            log_debug "Cleaning up leftover containers"
            docker rm -f "$containers" 2>/dev/null || true
        fi
    fi

    log_info "✅ k3s resources cleaned up"
    return 0
}

# Export functions
export -f k3s_create k3s_start k3s_stop k3s_delete k3s_status
export -f k3s_context k3s_urls k3s_cleanup wait_for_traefik check_port_available
