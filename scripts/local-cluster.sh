#!/bin/bash

# Local Cluster Management Script
# Unified management for both minikube and k3s local development clusters

# Source shared utilities
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"

# Default values
CLUSTER_TYPE="${CLUSTER_TYPE:-minikube}"
CLUSTER_NAME="${CLUSTER_NAME:-eoapi-local}"
HTTP_PORT="${HTTP_PORT:-8080}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
COMMAND=""

# Show help message
show_help() {
    cat << EOF
Local Cluster Management Script - Unified minikube and k3s support

USAGE:
    $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
    create              Create and start local cluster
    start               Start existing cluster
    stop                Stop cluster
    delete              Delete cluster
    status              Show cluster status
    context             Set kubectl context to cluster
    url                 Show cluster access URLs
    deploy              Create cluster and deploy eoAPI

OPTIONS:
    --type TYPE         Cluster type: minikube or k3s (default: minikube)
    --name NAME         Cluster name (default: eoapi-local)
    --http-port PORT    HTTP port for k3s (default: 8080)
    --https-port PORT   HTTPS port for k3s (default: 8443)
    --help, -h          Show this help message

ENVIRONMENT VARIABLES:
    CLUSTER_TYPE        Cluster type (minikube or k3s)
    CLUSTER_NAME        Cluster name
    HTTP_PORT           HTTP port for k3s ingress
    HTTPS_PORT          HTTPS port for k3s ingress

EXAMPLES:
    $(basename "$0") create --type minikube
    $(basename "$0") start --type k3s --name my-cluster
    $(basename "$0") deploy --type k3s
    CLUSTER_TYPE=minikube $(basename "$0") create

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        create|start|stop|delete|status|context|url|deploy)
            COMMAND="$1"; shift ;;
        --type)
            CLUSTER_TYPE="$2"; shift 2 ;;
        --name)
            CLUSTER_NAME="$2"; shift 2 ;;
        --http-port)
            HTTP_PORT="$2"; shift 2 ;;
        --https-port)
            HTTPS_PORT="$2"; shift 2 ;;
        --help|-h)
            show_help; exit 0 ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1 ;;
    esac
done

# Default to status if no command specified
if [ -z "$COMMAND" ]; then
    COMMAND="status"
fi

# Validate cluster type
case "$CLUSTER_TYPE" in
    minikube|k3s) ;;
    *)
        log_error "Invalid cluster type: $CLUSTER_TYPE. Must be 'minikube' or 'k3s'"
        exit 1 ;;
esac

# Check required tools
check_requirements() {
    case "$CLUSTER_TYPE" in
        minikube)
            if ! command_exists minikube; then
                log_error "minikube is required but not installed"
                log_info "Install minikube: https://minikube.sigs.k8s.io/docs/start/"
                exit 1
            fi
            ;;
        k3s)
            if ! command_exists k3d; then
                log_error "k3d is required but not installed"
                log_info "Install k3d: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
                exit 1
            fi
            ;;
    esac
}

# Get cluster context name
get_context_name() {
    case "$CLUSTER_TYPE" in
        minikube) echo "minikube" ;;
        k3s) echo "k3d-$CLUSTER_NAME" ;;
    esac
}

# Check if cluster exists
cluster_exists() {
    case "$CLUSTER_TYPE" in
        minikube)
            minikube profile list -o json 2>/dev/null | grep -q "\"Name\":\"minikube\"" || return 1
            ;;
        k3s)
            k3d cluster list | grep -q "^$CLUSTER_NAME" || return 1
            ;;
    esac
}

# Check if cluster is running
cluster_running() {
    case "$CLUSTER_TYPE" in
        minikube)
            minikube status >/dev/null 2>&1 || return 1
            ;;
        k3s)
            k3d cluster list | grep "^$CLUSTER_NAME" | grep -qE "[0-9]+/[0-9]+" || return 1
            ;;
    esac
}

# Create cluster
create_cluster() {
    log_info "Creating $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    if cluster_exists && cluster_running; then
        log_info "Cluster '$CLUSTER_NAME' already exists and is running"
        set_context
        show_cluster_info
        return 0
    fi

    case "$CLUSTER_TYPE" in
        minikube)
            if minikube start --profile minikube; then
                log_info "✅ Minikube cluster created successfully"
                # Enable ingress addon
                minikube addons enable ingress
                log_info "✅ Ingress addon enabled"
            else
                log_error "Failed to create minikube cluster"
                exit 1
            fi
            ;;
        k3s)
            if k3d cluster create "$CLUSTER_NAME" \
                --port "$HTTP_PORT:80@loadbalancer" \
                --port "$HTTPS_PORT:443@loadbalancer" \
                --wait; then
                log_info "✅ k3s cluster created successfully"
            else
                log_error "Failed to create k3s cluster"
                exit 1
            fi
            ;;
    esac

    set_context
    show_cluster_info
}

# Start existing cluster
start_cluster() {
    log_info "Starting $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    if ! cluster_exists; then
        log_error "Cluster '$CLUSTER_NAME' does not exist"
        log_info "Create it first with: $0 create --type $CLUSTER_TYPE"
        exit 1
    fi

    if cluster_running; then
        log_info "Cluster '$CLUSTER_NAME' is already running"
        set_context
        return 0
    fi

    case "$CLUSTER_TYPE" in
        minikube)
            if minikube start; then
                log_info "✅ Minikube cluster started successfully"
            else
                log_error "Failed to start minikube cluster"
                exit 1
            fi
            ;;
        k3s)
            if k3d cluster start "$CLUSTER_NAME"; then
                log_info "✅ k3s cluster started successfully"
            else
                log_error "Failed to start k3s cluster"
                exit 1
            fi
            ;;
    esac

    set_context
    show_cluster_info
}

# Stop cluster
stop_cluster() {
    log_info "Stopping $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    if ! cluster_exists; then
        log_warn "Cluster '$CLUSTER_NAME' does not exist"
        return 0
    fi

    if ! cluster_running; then
        log_info "Cluster '$CLUSTER_NAME' is already stopped"
        return 0
    fi

    case "$CLUSTER_TYPE" in
        minikube)
            if minikube stop; then
                log_info "✅ Minikube cluster stopped successfully"
            else
                log_error "Failed to stop minikube cluster"
                exit 1
            fi
            ;;
        k3s)
            if k3d cluster stop "$CLUSTER_NAME"; then
                log_info "✅ k3s cluster stopped successfully"
            else
                log_error "Failed to stop k3s cluster"
                exit 1
            fi
            ;;
    esac
}

# Delete cluster
delete_cluster() {
    log_info "Deleting $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    if ! cluster_exists; then
        log_warn "Cluster '$CLUSTER_NAME' does not exist"
        return 0
    fi

    case "$CLUSTER_TYPE" in
        minikube)
            if minikube delete; then
                log_info "✅ Minikube cluster deleted successfully"
            else
                log_error "Failed to delete minikube cluster"
                exit 1
            fi
            ;;
        k3s)
            if k3d cluster delete "$CLUSTER_NAME"; then
                log_info "✅ k3s cluster deleted successfully"
            else
                log_error "Failed to delete k3s cluster"
                exit 1
            fi
            ;;
    esac
}

# Show cluster status
show_status() {
    log_info "$CLUSTER_TYPE cluster status:"
    echo ""

    case "$CLUSTER_TYPE" in
        minikube)
            if command_exists minikube; then
                minikube status 2>/dev/null || log_warn "Minikube cluster not found or not running"
                echo ""
                if cluster_exists && cluster_running; then
                    log_info "Cluster 'minikube' is running"
                    show_cluster_info
                else
                    log_warn "Cluster 'minikube' does not exist or is not running"
                fi
            else
                log_error "minikube is not installed"
            fi
            ;;
        k3s)
            if command_exists k3d; then
                k3d cluster list
                echo ""
                if cluster_exists; then
                    if cluster_running; then
                        log_info "Cluster '$CLUSTER_NAME' is running"
                        show_cluster_info
                    else
                        log_warn "Cluster '$CLUSTER_NAME' exists but is not running"
                    fi
                else
                    log_warn "Cluster '$CLUSTER_NAME' does not exist"
                fi
            else
                log_error "k3d is not installed"
            fi
            ;;
    esac
}

# Set kubectl context
set_context() {
    local context
    context=$(get_context_name)

    if ! cluster_running; then
        log_error "Cluster '$CLUSTER_NAME' is not running"
        return 1
    fi

    if kubectl config use-context "$context" >/dev/null 2>&1; then
        log_info "✅ kubectl context set to: $context"
    else
        log_error "Failed to set kubectl context to: $context"
        return 1
    fi
}

# Get cluster access URLs
get_cluster_urls() {
    if ! cluster_running; then
        log_error "Cluster is not running"
        return 1
    fi

    case "$CLUSTER_TYPE" in
        minikube)
            # Get minikube service URL for ingress
            local ingress_url
            ingress_url=$(minikube service ingress-nginx-controller -n ingress-nginx --url 2>/dev/null | head -n 1)
            if [ -n "$ingress_url" ]; then
                echo "$ingress_url"
            else
                echo "http://$(minikube ip)"
            fi
            ;;
        k3s)
            echo "http://localhost:$HTTP_PORT"
            echo "https://localhost:$HTTPS_PORT"
            ;;
    esac
}

# Show cluster information
show_cluster_info() {
    if cluster_running; then
        echo ""
        log_info "Cluster endpoints:"
        get_cluster_urls | while read -r url; do
            echo "  $url"
        done
        echo ""
        log_info "kubectl context: $(get_context_name)"

        case "$CLUSTER_TYPE" in
            minikube)
                echo ""
                log_info "Ingress controller: nginx-ingress"
                log_info "Dashboard: minikube dashboard"
                ;;
            k3s)
                echo ""
                log_info "Ingress controller: Traefik (built-in)"
                log_info "Note: Add entries to /etc/hosts for custom hostnames"
                ;;
        esac

        echo ""
        log_info "To deploy eoAPI: make deploy"
        log_info "To run tests: make integration"
    fi
}

# Deploy eoAPI to cluster
deploy_eoapi() {
    log_info "Creating cluster and deploying eoAPI..."

    # Create cluster if it doesn't exist or start if stopped
    if ! cluster_running; then
        if cluster_exists; then
            start_cluster
        else
            create_cluster
        fi
    else
        set_context
    fi

    # Deploy eoAPI using the main deploy script
    log_info "Deploying eoAPI to $CLUSTER_TYPE cluster..."
    if command -v make >/dev/null 2>&1; then
        make deploy
    else
        "$SCRIPT_DIR/deploy.sh"
    fi
}

# Main execution
log_info "Local Cluster Management ($CLUSTER_TYPE)"
log_info "Cluster: $CLUSTER_NAME | Type: $CLUSTER_TYPE"
if [ "$CLUSTER_TYPE" = "k3s" ]; then
    log_info "Ports: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT"
fi

check_requirements

case $COMMAND in
    create)
        create_cluster
        ;;
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    delete)
        delete_cluster
        ;;
    status)
        show_status
        ;;
    context)
        set_context
        ;;
    url)
        get_cluster_urls
        ;;
    deploy)
        deploy_eoapi
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
