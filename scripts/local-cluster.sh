#!/bin/bash

# eoAPI local cluster management script
# management for minikube and k3s local development clusters

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/args.sh"
source "$SCRIPT_DIR/lib/cluster-minikube.sh"
source "$SCRIPT_DIR/lib/cluster-k3s.sh"

# Show help message
show_help() {
    cat << EOF
eoAPI local cluster management script
minikube and k3s support for local development

USAGE:
    $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
    create              Create and start local cluster
    start               Start existing cluster
    stop                Stop cluster
    delete              Delete cluster
    status              Show cluster status
    context             Set kubectl context to cluster
    urls                Show cluster access URLs
    deploy              Create cluster and deploy eoAPI
    cleanup             Stop and delete cluster

$(show_cluster_options)
$(show_common_options)

MINIKUBE SPECIFIC OPTIONS:
    --driver DRIVER     Minikube driver (docker, virtualbox, etc.)
    --memory SIZE       Memory allocation (default: 4g)
    --cpus COUNT        CPU allocation (default: 2)
    --disk-size SIZE    Disk size (default: 20g)

ENVIRONMENT VARIABLES:
    MINIKUBE_DRIVER     Minikube driver (default: docker)
    MINIKUBE_MEMORY     Memory for minikube (default: 4g)
    MINIKUBE_CPUS       CPUs for minikube (default: 2)
    MINIKUBE_DISK       Disk size for minikube (default: 20g)
    K3S_REGISTRY_PORT   Registry port for k3s (default: 5001)

EXAMPLES:
    $(basename "$0") create --type minikube
    $(basename "$0") start --type k3s --name my-cluster
    $(basename "$0") deploy --type minikube --debug
    $(basename "$0") urls --type k3s

For more information, see: https://github.com/developmentseed/eoapi-k8s
EOF
}

# Main function
main() {
    local command="${1:-create}"
    shift || true

    # Parse arguments
    if ! parse_cluster_args "$@"; then
        local result=$?
        if [ $result -eq 2 ]; then
            show_help
            exit 0
        fi
        exit $result
    fi

    # Validate parsed arguments
    if ! validate_parsed_args cluster; then
        exit 1
    fi

    # Enable debug logging if requested
    if [ "$DEBUG_MODE" = true ]; then
        log_info "=== Local cluster management debug info ==="
        log_debug "Command: $command"
        log_debug "Cluster type: $CLUSTER_TYPE"
        log_debug "Cluster name: $CLUSTER_NAME"
        log_debug "Script directory: $SCRIPT_DIR"
        log_debug "Working directory: $(pwd)"
    fi

    # Validate tools for the selected cluster type
    if ! validate_local_cluster_tools "$CLUSTER_TYPE"; then
        exit 1
    fi

    # Execute command
    case "$command" in
        create)
            cmd_create
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        delete)
            cmd_delete
            ;;
        status)
            cmd_status
            ;;
        context)
            cmd_context
            ;;
        urls)
            cmd_urls
            ;;
        deploy)
            cmd_deploy
            ;;
        cleanup)
            cmd_cleanup
            ;;
        --help|-h|help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            log_info "Use '$(basename "$0") --help' for usage information"
            exit 1
            ;;
    esac
}

# Command implementations
cmd_create() {
    log_info "Creating $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    case "$CLUSTER_TYPE" in
        minikube)
            local driver="${MINIKUBE_DRIVER:-docker}"
            local memory="${MINIKUBE_MEMORY:-4g}"
            local cpus="${MINIKUBE_CPUS:-2}"
            local disk="${MINIKUBE_DISK:-20g}"

            if minikube_create "$CLUSTER_NAME" "$driver" "$memory" "$cpus" "$disk"; then
                log_info "✅ minikube cluster created successfully"
                minikube_context "$CLUSTER_NAME"
            else
                log_error "❌ Failed to create minikube cluster"
                exit 1
            fi
            ;;
        k3s)
            if k3s_create "$CLUSTER_NAME" "$HTTP_PORT" "$HTTPS_PORT"; then
                log_info "✅ k3s cluster created successfully"
                k3s_context "$CLUSTER_NAME"
            else
                log_error "❌ Failed to create k3s cluster"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported cluster type: $CLUSTER_TYPE"
            exit 1
            ;;
    esac
}

cmd_start() {
    log_info "Starting $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    case "$CLUSTER_TYPE" in
        minikube)
            if minikube_start "$CLUSTER_NAME"; then
                log_info "✅ minikube cluster started successfully"
                minikube_context "$CLUSTER_NAME"
            else
                log_error "❌ Failed to start minikube cluster"
                exit 1
            fi
            ;;
        k3s)
            if k3s_start "$CLUSTER_NAME"; then
                log_info "✅ k3s cluster started successfully"
                k3s_context "$CLUSTER_NAME"
            else
                log_error "❌ Failed to start k3s cluster"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported cluster type: $CLUSTER_TYPE"
            exit 1
            ;;
    esac
}

cmd_stop() {
    log_info "Stopping $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    case "$CLUSTER_TYPE" in
        minikube)
            if minikube_stop "$CLUSTER_NAME"; then
                log_info "✅ minikube cluster stopped successfully"
            else
                log_error "❌ Failed to stop minikube cluster"
                exit 1
            fi
            ;;
        k3s)
            if k3s_stop "$CLUSTER_NAME"; then
                log_info "✅ k3s cluster stopped successfully"
            else
                log_error "❌ Failed to stop k3s cluster"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported cluster type: $CLUSTER_TYPE"
            exit 1
            ;;
    esac
}

cmd_delete() {
    log_info "Deleting $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    case "$CLUSTER_TYPE" in
        minikube)
            if minikube_delete "$CLUSTER_NAME"; then
                log_info "✅ minikube cluster deleted successfully"
            else
                log_error "❌ Failed to delete minikube cluster"
                exit 1
            fi
            ;;
        k3s)
            if k3s_delete "$CLUSTER_NAME"; then
                log_info "✅ k3s cluster deleted successfully"
            else
                log_error "❌ Failed to delete k3s cluster"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported cluster type: $CLUSTER_TYPE"
            exit 1
            ;;
    esac
}

cmd_status() {
    case "$CLUSTER_TYPE" in
        minikube)
            minikube_status "$CLUSTER_NAME"
            ;;
        k3s)
            k3s_status "$CLUSTER_NAME"
            ;;
        *)
            log_error "Unsupported cluster type: $CLUSTER_TYPE"
            exit 1
            ;;
    esac
}

cmd_context() {
    log_info "Setting kubectl context for $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    case "$CLUSTER_TYPE" in
        minikube)
            if minikube_context "$CLUSTER_NAME"; then
                log_info "✅ kubectl context set successfully"
            else
                log_error "❌ Failed to set kubectl context"
                exit 1
            fi
            ;;
        k3s)
            if k3s_context "$CLUSTER_NAME"; then
                log_info "✅ kubectl context set successfully"
            else
                log_error "❌ Failed to set kubectl context"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported cluster type: $CLUSTER_TYPE"
            exit 1
            ;;
    esac
}

cmd_urls() {
    case "$CLUSTER_TYPE" in
        minikube)
            minikube_urls "$CLUSTER_NAME"
            ;;
        k3s)
            k3s_urls "$CLUSTER_NAME"
            ;;
        *)
            log_error "Unsupported cluster type: $CLUSTER_TYPE"
            exit 1
            ;;
    esac
}

cmd_deploy() {
    log_info "Creating $CLUSTER_TYPE cluster and deploying eoAPI..."

    # Create cluster if needed
    if ! cmd_create; then
        exit 1
    fi

    # Deploy eoAPI
    log_info "Deploying eoAPI to local cluster..."
    if "$SCRIPT_DIR/deploy.sh" deploy --namespace "$NAMESPACE" --release "$RELEASE_NAME"; then
        log_info "🎉 Local cluster created and eoAPI deployed successfully!"

        # Show access information
        cmd_urls
        log_info ""
        log_info "eoAPI should be accessible at the above URLs under these paths:"
        log_info "  /stac    - STAC API"
        log_info "  /raster  - TiTiler"
        log_info "  /vector  - TiPG"
        log_info "  /browser - STAC Browser"
    else
        log_error "❌ Failed to deploy eoAPI"
        exit 1
    fi
}

cmd_cleanup() {
    log_info "Cleaning up $CLUSTER_TYPE cluster: $CLUSTER_NAME"

    case "$CLUSTER_TYPE" in
        minikube)
            minikube_cleanup "$CLUSTER_NAME"
            ;;
        k3s)
            k3s_cleanup "$CLUSTER_NAME"
            ;;
        *)
            log_error "Unsupported cluster type: $CLUSTER_TYPE"
            exit 1
            ;;
    esac

    log_info "✅ Cluster cleanup completed"
}

# Error handling
trap 'log_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
