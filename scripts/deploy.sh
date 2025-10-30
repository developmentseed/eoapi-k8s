#!/bin/bash

# eoAPI Deployment Script

# Source shared utilities
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"

# Default values
PGO_VERSION="${PGO_VERSION:-5.7.4}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"
NAMESPACE="${NAMESPACE:-eoapi}"
TIMEOUT="${TIMEOUT:-10m}"
CI_MODE=false
COMMAND=""

# Auto-detect CI environment
CI_MODE=$(is_ci_environment && echo true || echo false)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        deploy|setup|cleanup)
            COMMAND="$1"; shift ;;
        --ci) CI_MODE=true; shift ;;
        --help|-h)
            echo "eoAPI Deployment Script"
            echo "Usage: $(basename "$0") [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  deploy     Deploy eoAPI (includes setup) [default]"
            echo "  setup      Setup Helm dependencies only"
            echo "  cleanup    Cleanup deployment resources"
            echo ""
            echo "Options:"
            echo "  --ci       Enable CI mode"
            echo "  --help     Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  PGO_VERSION    PostgreSQL Operator version (default: 5.7.4)"
            echo "  RELEASE_NAME   Helm release name (default: eoapi)"
            echo "  NAMESPACE      Kubernetes namespace (default: eoapi)"
            echo "  TIMEOUT        Helm install timeout (default: 10m)"
            exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Default to deploy if no command specified
if [ -z "$COMMAND" ]; then
    COMMAND="deploy"
fi

log_info "Starting eoAPI $COMMAND$([ "$CI_MODE" = true ] && echo " (CI MODE)" || echo "")..."
log_info "Release: $RELEASE_NAME | Namespace: $NAMESPACE | PGO Version: $PGO_VERSION"

# Run pre-flight checks (skip for setup-only mode)
if [ "$COMMAND" != "setup" ]; then
    preflight_deploy || exit 1
fi

# Install PostgreSQL operator
install_pgo() {
    log_info "Installing PostgreSQL Operator..."
    if helm list -A -q | grep -q "^pgo$"; then
        log_info "PGO already installed, upgrading..."
        helm upgrade pgo oci://registry.developers.crunchydata.com/crunchydata/pgo \
            --version "$PGO_VERSION" --set disable_check_for_upgrades=true
    else
        helm install pgo oci://registry.developers.crunchydata.com/crunchydata/pgo \
            --version "$PGO_VERSION" --set disable_check_for_upgrades=true
    fi

    # Wait for PostgreSQL operator
    log_info "Waiting for PostgreSQL Operator to be ready..."
    if ! kubectl wait --for=condition=Available deployment/pgo --timeout=300s; then
        log_error "PostgreSQL Operator failed to become ready"
        kubectl get pods -l postgres-operator.crunchydata.com/control-plane=postgres-operator
        exit 1
    fi
    kubectl get pods -l postgres-operator.crunchydata.com/control-plane=postgres-operator
}

# Integrated Helm dependency setup
setup_helm_dependencies() {
    log_info "Setting up Helm dependencies..."

    # Add repositories from Chart.yaml files
    for chart in charts/*/; do
        if [ -f "$chart/Chart.yaml" ]; then
            log_info "Processing $chart..."

            # Extract unique repository URLs
            if grep -q "repository:" "$chart/Chart.yaml" 2>/dev/null; then
                grep "repository:" "$chart/Chart.yaml" 2>/dev/null | \
                sed "s/.*repository: *//" | \
                grep -v "file://" | \
                sort -u | \
                while read -r repo; do
                    if [ -n "$repo" ]; then
                        repo_name=$(echo "$repo" | sed "s|https://||" | sed "s|/.*||" | sed "s/\./-/g")
                        log_info "Adding repository $repo_name -> $repo"
                        helm repo add "$repo_name" "$repo" 2>/dev/null || true
                    fi
                done
            fi
        fi
    done

    # Update repositories
    log_info "Updating helm repositories..."
    helm repo update

    # Build dependencies
    for chart in charts/*/; do
        if [ -f "$chart/Chart.yaml" ]; then
            log_info "Building dependencies for $chart..."
            (
                cd "$chart" || exit
                helm dependency build
            )
        fi
    done

    log_info "✅ Helm dependency setup complete"
}

# Deploy eoAPI function
deploy_eoapi() {
    log_info "Deploying eoAPI..."
    cd charts || exit

    # Build Helm command
    HELM_CMD="helm upgrade --install $RELEASE_NAME ./eoapi"
    HELM_CMD="$HELM_CMD --namespace $NAMESPACE --create-namespace"
    HELM_CMD="$HELM_CMD --timeout=$TIMEOUT"

    # Add base values file
    if [ -f "./eoapi/values.yaml" ]; then
        HELM_CMD="$HELM_CMD -f ./eoapi/values.yaml"
    fi

    # Add local base configuration for development environments
    if [ -f "./eoapi/local-base-values.yaml" ]; then
        case "$(kubectl config current-context 2>/dev/null || echo "unknown")" in
            *"minikube"*|*"k3d"*|"default")
                log_info "Using local base configuration..."
                HELM_CMD="$HELM_CMD -f ./eoapi/local-base-values.yaml"
                ;;
        esac
    fi

    # Local development configuration (detect cluster type)
    if [ "$CI_MODE" != true ]; then
        local current_context
        current_context=$(kubectl config current-context 2>/dev/null || echo "")

        case "$current_context" in
            *"k3d"*)
                if [ -f "./eoapi/local-k3s-values.yaml" ]; then
                    log_info "Adding k3s-specific overrides..."
                    HELM_CMD="$HELM_CMD -f ./eoapi/local-k3s-values.yaml"
                fi
                ;;
            "minikube")
                if [ -f "./eoapi/local-minikube-values.yaml" ]; then
                    log_info "Adding minikube-specific overrides..."
                    HELM_CMD="$HELM_CMD -f ./eoapi/local-minikube-values.yaml"
                fi
                ;;
        esac
    fi

    # CI-specific configuration
    if [ "$CI_MODE" = true ]; then
        log_info "Applying CI-specific overrides..."
        # Use base + k3s values, then override for CI
        if [ -f "./eoapi/local-base-values.yaml" ]; then
            HELM_CMD="$HELM_CMD -f ./eoapi/local-base-values.yaml"
        fi
        if [ -f "./eoapi/local-k3s-values.yaml" ]; then
            HELM_CMD="$HELM_CMD -f ./eoapi/local-k3s-values.yaml"
        fi
        HELM_CMD="$HELM_CMD --set testing=true"
        HELM_CMD="$HELM_CMD --set ingress.host=eoapi.local"
        HELM_CMD="$HELM_CMD --set eoapi-notifier.enabled=true"
    fi

    # Set git SHA if available
    GITHUB_SHA=${GITHUB_SHA:-}
    if [ -n "$GITHUB_SHA" ]; then
        HELM_CMD="$HELM_CMD --set gitSha=$GITHUB_SHA"
    elif [ -n "$(git rev-parse HEAD 2>/dev/null)" ]; then
        HELM_CMD="$HELM_CMD --set gitSha=$(git rev-parse HEAD | cut -c1-10)"
    fi

    # Execute deployment
    log_info "Running: $HELM_CMD"
    eval "$HELM_CMD"

    cd .. || exit

    # Verify deployment
    log_info "Verifying deployment..."
    kubectl get pods -n "$NAMESPACE" -o wide

    log_info "eoAPI deployment completed successfully!"
    log_info "Services available in namespace: $NAMESPACE"

    if [ "$CI_MODE" != true ]; then
        log_info "To run integration tests: make integration"
        log_info "To check status: kubectl get pods -n $NAMESPACE"
    fi
}

# Cleanup function
cleanup_deployment() {
    log_info "Cleaning up resources for release: $RELEASE_NAME"

    # Validate namespace exists
    if ! validate_namespace "$NAMESPACE"; then
        log_warn "Namespace '$NAMESPACE' not found, skipping cleanup"
        return 0
    fi

    # Function to safely delete resources
    cleanup_resource() {
        local resource_type="$1"
        local resources

        log_info "Cleaning up ${resource_type}..."
        resources=$(kubectl get "$resource_type" -n "$NAMESPACE" --no-headers 2>/dev/null | grep "$RELEASE_NAME" | awk '{print $1}' || true)

        if [ -n "$resources" ]; then
            log_info "  Found ${resource_type}: $resources"
            echo "$resources" | xargs -r kubectl delete "$resource_type" -n "$NAMESPACE"
        else
            log_info "  No ${resource_type} found for $RELEASE_NAME"
        fi
    }

    # Clean up resources in order (dependencies first)
    cleanup_resource "ingress"
    cleanup_resource "service"
    cleanup_resource "deployment"
    cleanup_resource "job"
    cleanup_resource "configmap"
    cleanup_resource "secret"
    cleanup_resource "pvc"

    # Try helm uninstall as well (if it's a helm release)
    log_info "Attempting helm uninstall..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || log_warn "No helm release found for $RELEASE_NAME"

    log_info "✅ Cleanup complete for release: $RELEASE_NAME"
}

# Execute based on command
case $COMMAND in
    setup)
        setup_helm_dependencies
        ;;
    cleanup)
        cleanup_deployment
        ;;
    deploy)
        install_pgo
        setup_helm_dependencies
        deploy_eoapi
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        exit 1
        ;;
esac
