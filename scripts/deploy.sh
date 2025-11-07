#!/bin/bash

# eoAPI deployment script

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/args.sh"
source "$SCRIPT_DIR/lib/deploy-core.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"

# Show help message
show_help() {
    cat << EOF
eoAPI deployment script

USAGE:
    $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
    deploy              Deploy eoAPI to current cluster [default]
    setup               Setup environment and dependencies only
    cleanup             Clean up eoAPI deployment
    status              Show deployment status
    info                Show deployment information and URLs

$(show_common_options)

EXAMPLES:
    $(basename "$0")                                    # Deploy with defaults
    $(basename "$0") deploy --namespace myns           # Deploy to specific namespace
    $(basename "$0") cleanup --release myrelease       # Cleanup specific release
    $(basename "$0") setup --debug                     # Setup with debug output
    $(basename "$0") setup --deps-only                 # Setup Helm dependencies only

$(show_environment_variables)

For more information, see: https://github.com/developmentseed/eoapi-k8s
EOF
}

# Main function
main() {
    local command="${1:-deploy}"
    shift || true

    # Parse arguments
    if ! parse_common_args "$@"; then
        local result=$?
        if [ $result -eq 2 ]; then
            show_help
            exit 0
        fi
        exit $result
    fi

    # Validate parsed arguments
    if ! validate_parsed_args basic; then
        exit 1
    fi

    # Enable debug logging if requested
    if [ "$DEBUG_MODE" = true ]; then
        log_info "=== eoAPI deployment script debug info ==="
        log_debug "Command: $command"
        log_debug "Script directory: $SCRIPT_DIR"
        log_debug "Working directory: $(pwd)"
        log_debug "User: $(whoami)"
        log_debug "Current context: $(kubectl config current-context 2>/dev/null || echo 'none')"
        log_debug "=== Parsed Variables ==="
        log_debug "NAMESPACE: '$NAMESPACE'"
        log_debug "RELEASE_NAME: '$RELEASE_NAME'"
        log_debug "TIMEOUT: '$TIMEOUT'"
        log_debug "DEPS_ONLY: '$DEPS_ONLY'"
        if [ "${#HELM_VALUES_FILES[@]}" -gt 0 ]; then
            log_debug "HELM_VALUES_FILES: ${HELM_VALUES_FILES[*]}"
        else
            log_debug "HELM_VALUES_FILES: (none)"
        fi
        if [ "${#HELM_SET_VALUES[@]}" -gt 0 ]; then
            log_debug "HELM_SET_VALUES: ${HELM_SET_VALUES[*]}"
        else
            log_debug "HELM_SET_VALUES: (none)"
        fi
    fi

    # Execute command
    case "$command" in
        deploy)
            cmd_deploy
            ;;
        setup)
            cmd_setup
            ;;
        cleanup)
            cmd_cleanup
            ;;
        status)
            cmd_status
            ;;
        info)
            cmd_info
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
cmd_deploy() {
    log_info "Starting eoAPI deployment..."

    # Run pre-flight checks
    if ! preflight_deploy; then
        exit 1
    fi

    # Deploy eoAPI
    if deploy_eoapi; then
        log_info "🎉 eoAPI deployment completed successfully!"
        get_deployment_info
    else
        log_error "❌ eoAPI deployment failed"
        exit 1
    fi
}

cmd_setup() {
    log_info "Setting up eoAPI environment..."

    # Validate tools
    if ! validate_deploy_tools; then
        exit 1
    fi

    if [ "$DEPS_ONLY" = true ]; then
        log_info "Setting up Helm dependencies only (--deps-only mode)..."

        # Only setup helm dependencies
        if setup_helm_dependencies; then
            log_info "✅ Helm dependencies setup completed successfully"
        else
            log_error "❌ Helm dependencies setup failed"
            exit 1
        fi
    else
        # Validate cluster connection
        if ! validate_cluster_connection; then
            exit 1
        fi

        # Setup components
        if setup_namespace && install_pgo && setup_helm_dependencies; then
            log_info "✅ Environment setup completed successfully"
        else
            log_error "❌ Environment setup failed"
            exit 1
        fi
    fi
}

cmd_cleanup() {
    log_info "Starting eoAPI cleanup..."

    # Basic validation
    if ! validate_kubectl; then
        exit 1
    fi

    # Cleanup deployment
    if cleanup_deployment; then
        log_info "🧹 eoAPI cleanup completed successfully!"
        show_cleanup_status
    else
        log_error "❌ eoAPI cleanup failed"
        exit 1
    fi
}

cmd_status() {
    log_info "Checking eoAPI deployment status..."

    if ! validate_kubectl; then
        exit 1
    fi

    if ! validate_cluster_connection; then
        exit 1
    fi

    # Auto-detect namespace if not specified
    if [ "$NAMESPACE" = "eoapi" ]; then
        local detected_namespace
        detected_namespace=$(detect_namespace)
        if [ -n "$detected_namespace" ] && [ "$detected_namespace" != "eoapi" ]; then
            log_info "Auto-detected namespace: $detected_namespace"
            NAMESPACE="$detected_namespace"
        fi
    fi

    # Auto-detect release name if not specified
    if [ "$RELEASE_NAME" = "eoapi" ]; then
        local detected_release
        detected_release=$(detect_release_name "$NAMESPACE")
        if [ -n "$detected_release" ] && [ "$detected_release" != "eoapi" ]; then
            log_info "Auto-detected release: $detected_release"
            RELEASE_NAME="$detected_release"
        fi
    fi

    # Check if deployment exists
    if helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_info "✅ eoAPI deployment found"
        helm status "$RELEASE_NAME" -n "$NAMESPACE"

        # Validate deployment
        if validate_eoapi_deployment "$NAMESPACE" "$RELEASE_NAME"; then
            log_info "✅ eoAPI deployment is healthy"
        else
            log_warn "⚠️ eoAPI deployment has issues"
        fi
    else
        log_warn "❌ No eoAPI deployment found"
        log_info "Available releases in namespace '$NAMESPACE':"
        helm list -n "$NAMESPACE" 2>/dev/null || echo "  (none)"
    fi
}

cmd_info() {
    log_info "Getting eoAPI deployment information..."

    if ! validate_kubectl; then
        exit 1
    fi

    if ! validate_cluster_connection; then
        exit 1
    fi

    # Auto-detect parameters
    if [ "$NAMESPACE" = "eoapi" ]; then
        NAMESPACE=$(detect_namespace)
    fi

    if [ "$RELEASE_NAME" = "eoapi" ]; then
        RELEASE_NAME=$(detect_release_name "$NAMESPACE")
    fi

    get_deployment_info
}

# Error handling
trap 'log_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
