#!/usr/bin/env bash

# eoAPI Scripts - Cluster Management
# Manages local k3d clusters for development and testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/k8s.sh"

readonly CLUSTER_NAME="${CLUSTER_NAME:-eoapi-local}"

show_help() {
    cat <<EOF
Cluster Management for eoAPI

USAGE:
    $(basename "$0") [OPTIONS] <COMMAND> [ARGS]

COMMANDS:
    start           Create or start k3d cluster
    stop            Stop cluster without deleting
    clean           Delete cluster and remove temporary files
    status          Show cluster info and resources
    inspect         Detailed cluster diagnostics

OPTIONS:
    -h, --help      Show this help message
    -d, --debug     Enable debug mode
    --name NAME     Cluster name (default: ${CLUSTER_NAME})

EXAMPLES:
    # Start a new cluster
    $(basename "$0") start

    # Check cluster status
    $(basename "$0") status

    # Clean up everything
    $(basename "$0") clean
EOF
}

cluster_exists() {
    local cluster_name="${1:-$CLUSTER_NAME}"
    k3d cluster list 2>/dev/null | grep -q "^${cluster_name}"
}

start_cluster() {
    local cluster_name="${CLUSTER_NAME}"

    log_info "Starting k3d cluster: ${cluster_name}"

    check_requirements k3d docker kubectl || {
        log_error "Missing required tools"
        log_info "Install k3d from: https://k3d.io"
        return 1
    }

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        return 1
    fi

    if cluster_exists "$cluster_name"; then
        log_info "Cluster '${cluster_name}' already exists"
        k3d cluster start "$cluster_name" 2>/dev/null || {
            log_error "Failed to start cluster"
            return 1
        }
    else
        log_info "Creating new k3d cluster..."

        k3d cluster create "$cluster_name" \
            -p "80:80@loadbalancer" \
            -p "443:443@loadbalancer" \
            --agents 1 \
            --k3s-arg "--disable=metrics-server@server:0" \
            --wait || {
            log_error "Failed to create cluster"
            return 1
        }

        # Install metrics-server for HPA
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

        log_info "Waiting for traefik ingress controller..."
        kubectl wait --namespace kube-system \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/name=traefik \
            --timeout=90s || log_warn "Traefik not ready yet"
    fi

    log_success "Cluster ready"
    kubectl cluster-info
    return 0
}

stop_cluster() {
    local cluster_name="${CLUSTER_NAME}"

    log_info "Stopping k3d cluster: ${cluster_name}"

    if ! cluster_exists "$cluster_name"; then
        log_warn "Cluster '${cluster_name}' does not exist"
        return 0
    fi

    k3d cluster stop "$cluster_name" || {
        log_error "Failed to stop cluster"
        return 1
    }

    log_success "Cluster stopped"
    return 0
}

clean_cluster() {
    local cluster_name="${CLUSTER_NAME}"

    log_info "Cleaning up cluster and temporary files"

    # Delete k3d cluster
    if cluster_exists "$cluster_name"; then
        log_info "Deleting k3d cluster: ${cluster_name}"
        k3d cluster delete "$cluster_name" || log_error "Failed to delete cluster"
    fi

    rm -rf "${PROJECT_ROOT}/.tmp" "${PROJECT_ROOT}/.pytest_cache"
    find "${PROJECT_ROOT}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "${PROJECT_ROOT}" -type f -name "*.pyc" -delete 2>/dev/null || true

    log_success "Cleanup completed"
    return 0
}

show_status() {
    local cluster_name="${CLUSTER_NAME}"

    log_info "Cluster Status Report"
    echo ""

    if ! cluster_exists "$cluster_name"; then
        log_warn "Cluster '${cluster_name}' does not exist"
        return 1
    fi

    # Set kubectl context
    kubectl config use-context "k3d-${cluster_name}" >/dev/null 2>&1 || {
        log_error "Failed to set kubectl context"
        return 1
    }

    echo "═══ Cluster: ${cluster_name} ═══"
    kubectl get nodes -o wide
    echo ""

    echo "═══ Namespaces ═══"
    kubectl get namespaces
    echo ""

    echo "═══ Pods (All Namespaces) ═══"
    kubectl get pods --all-namespaces
    echo ""

    echo "═══ Services ═══"
    kubectl get services --all-namespaces
    echo ""

    return 0
}

inspect_cluster() {
    local cluster_name="${CLUSTER_NAME}"

    log_info "Detailed Cluster Inspection"
    echo ""

    if ! cluster_exists "$cluster_name"; then
        log_error "Cluster '${cluster_name}' does not exist"
        return 1
    fi

    kubectl config use-context "k3d-${cluster_name}" >/dev/null 2>&1 || {
        log_error "Failed to set kubectl context"
        return 1
    }

    echo "═══ Resource Usage ═══"
    kubectl top nodes 2>/dev/null || log_warn "Metrics not available"
    echo ""

    kubectl top pods --all-namespaces --sort-by=cpu 2>/dev/null | head -20
    echo ""

    echo "═══ Recent Events ═══"
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20
    echo ""

    echo "═══ Failed/Pending Pods ═══"
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded
    echo ""

    echo "═══ Docker Containers ═══"
    docker ps --filter "name=k3d-${cluster_name}" --format "table {{.Names}}\t{{.Status}}"
    echo ""

    log_success "Inspection completed"
    return 0
}

wait_ready() {
    log_info "Waiting for cluster readiness..."

    # Wait for core DNS
    kubectl wait --for=condition=Ready pod -l k8s-app=kube-dns -n kube-system --timeout=120s || true

    # Wait for metrics-server if exists
    kubectl wait --for=condition=Ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s 2>/dev/null || {
        log_warn "Metrics server not ready"
    }

    log_success "Cluster ready"
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
            --name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            start|stop|clean|status|inspect|wait-ready)
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

    [[ -z "$command" ]] && { show_help; exit 1; }

    case "$command" in
        start) start_cluster ;;
        stop) stop_cluster ;;
        clean) clean_cluster ;;
        status) show_status ;;
        inspect) inspect_cluster ;;
        wait-ready) wait_ready ;;
        *) log_error "Unknown command: $command"; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
