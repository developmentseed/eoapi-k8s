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

# Initial environment debugging
log_info "=== eoAPI Deployment Script Starting ==="
log_debug "Script location: $0"
log_debug "Script directory: $SCRIPT_DIR"
log_debug "Working directory: $(pwd)"
log_debug "Environment variables:"
log_debug "  PGO_VERSION: $PGO_VERSION"
log_debug "  RELEASE_NAME: $RELEASE_NAME"
log_debug "  NAMESPACE: $NAMESPACE"
log_debug "  TIMEOUT: $TIMEOUT"
log_debug "  CI_MODE: $CI_MODE"

# Validate basic tools and environment
log_debug "=== Environment Validation ==="
log_debug "Bash version: $BASH_VERSION"
log_debug "Available tools check:"
if command -v kubectl >/dev/null 2>&1; then
    log_debug "  kubectl: $(kubectl version --client --short 2>/dev/null || echo 'version unavailable')"
else
    log_error "kubectl not found in PATH"
    exit 1
fi

if command -v helm >/dev/null 2>&1; then
    log_debug "  helm: $(helm version --short 2>/dev/null || echo 'version unavailable')"
else
    log_error "helm not found in PATH"
    exit 1
fi

# Kubernetes connectivity will be checked later for commands that need it
log_debug "Kubernetes connectivity check deferred until needed"

# Check project structure
log_debug "Project structure validation:"
if [ -d "charts" ]; then
    log_debug "  ✅ charts/ directory found"
    charts_list=""
    for chart_dir in charts/*/; do
        if [ -d "$chart_dir" ]; then
            chart_name=$(basename "$chart_dir")
            charts_list="$charts_list$chart_name "
        fi
    done
    log_debug "  Available charts: ${charts_list:-none}"
else
    log_error "  ❌ charts/ directory not found in $(pwd)"
    # shellcheck disable=SC2012
    log_debug "  Directory contents: $(ls -la | head -10)"
    exit 1
fi

log_debug "=== Environment validation complete ==="

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

# Check Kubernetes connectivity for commands that need it
if [ "$COMMAND" != "setup" ]; then
    log_debug "Validating Kubernetes connectivity for command: $COMMAND"
    if kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
        log_debug "  ✅ Cluster connection successful"
        log_debug "  Current context: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
    else
        log_error "  ❌ Cannot connect to Kubernetes cluster"
        exit 1
    fi
fi

# Pre-deployment debugging for CI
pre_deployment_debug() {
    log_info "=== Pre-deployment State Check ==="

    # Check basic cluster state
    log_info "Cluster nodes:"
    kubectl get nodes -o wide || log_error "Cannot get cluster nodes"
    echo ""

    log_info "All namespaces:"
    kubectl get namespaces || log_error "Cannot get namespaces"
    echo ""

    # Check PGO status
    log_info "PostgreSQL Operator status:"
    kubectl get deployment pgo -o wide 2>/dev/null || log_info "PGO not found (expected for fresh install)"
    kubectl get pods -l postgres-operator.crunchydata.com/control-plane=postgres-operator -o wide 2>/dev/null || log_info "No PGO pods found (expected for fresh install)"
    echo ""

    # Check for any existing knative-operator
    log_info "Looking for knative-operator before deployment:"
    kubectl get deployment knative-operator --all-namespaces -o wide 2>/dev/null || log_info "knative-operator not found yet (expected)"
    echo ""

    # Check available helm repositories
    log_info "Helm repositories:"
    helm repo list 2>/dev/null || log_info "No helm repositories configured yet"
    echo ""

    # Check if target namespace exists
    log_info "$NAMESPACE namespace check:"
    kubectl get namespace "$NAMESPACE" 2>/dev/null || log_info "$NAMESPACE namespace doesn't exist yet (expected)"
    echo ""

    # Script validation in CI
    log_info "Script validation complete"
    log_debug "Working directory: $(pwd)"
    log_debug "Environment: RELEASE_NAME=$RELEASE_NAME, PGO_VERSION=$PGO_VERSION"

    return 0
}

# Run pre-flight checks (skip for setup-only mode)
if [ "$COMMAND" != "setup" ]; then
    preflight_deploy || exit 1

    # Run extended debugging in CI mode
    if [ "$CI_MODE" = true ]; then
        pre_deployment_debug || exit 1
    fi
fi

# Install PostgreSQL operator
install_pgo() {
    log_info "Installing PostgreSQL Operator..."

    # Debug: Show current state before installation
    log_debug "Current working directory: $(pwd)"
    log_debug "Checking for existing PGO installation..."

    # Check if PGO is already installed
    existing_pgo=$(helm list -A -q 2>/dev/null | grep "^pgo$" || echo "")

    if [ -n "$existing_pgo" ]; then
        log_info "PGO already installed, upgrading..."
        log_debug "Existing PGO release: $existing_pgo"

        if ! helm upgrade pgo oci://registry.developers.crunchydata.com/crunchydata/pgo \
            --version "$PGO_VERSION" --set disable_check_for_upgrades=true 2>&1; then
            log_error "Failed to upgrade PostgreSQL Operator"
            log_debug "Helm list output:"
            helm list -A || true
            log_debug "Available helm repositories:"
            helm repo list || echo "No repositories configured"
            exit 1
        fi
        log_info "✅ PGO upgrade completed"
    else
        log_info "Installing new PGO instance..."

        if ! helm install pgo oci://registry.developers.crunchydata.com/crunchydata/pgo \
            --version "$PGO_VERSION" --set disable_check_for_upgrades=true 2>&1; then
            log_error "Failed to install PostgreSQL Operator"
            log_debug "Helm installation failed. Checking environment..."
            log_debug "Kubernetes connectivity:"
            kubectl cluster-info || echo "Cluster info unavailable"
            log_debug "Available namespaces:"
            kubectl get namespaces || echo "Cannot list namespaces"
            log_debug "Helm version:"
            helm version || echo "Helm version unavailable"
            exit 1
        fi
        log_info "✅ PGO installation completed"
    fi

    # Wait for PostgreSQL operator with enhanced debugging
    log_info "Waiting for PostgreSQL Operator to be ready..."
    log_debug "Checking for PGO deployment..."

    # First check if deployment exists
    if ! kubectl get deployment pgo >/dev/null 2>&1; then
        log_warn "PGO deployment not found, waiting for it to be created..."
        sleep 10

        if ! kubectl get deployment pgo >/dev/null 2>&1; then
            log_error "PGO deployment was not created"
            log_debug "All deployments in default namespace:"
            kubectl get deployments -o wide || echo "Cannot list deployments"
            log_debug "All pods in default namespace:"
            kubectl get pods -o wide || echo "Cannot list pods"
            log_debug "Recent events:"
            kubectl get events --sort-by='.lastTimestamp' | tail -10 || echo "Cannot get events"
            exit 1
        fi
    fi

    log_debug "PGO deployment found, waiting for readiness..."
    if ! kubectl wait --for=condition=Available deployment/pgo --timeout=300s; then
        log_error "PostgreSQL Operator failed to become ready within timeout"

        log_debug "=== PGO Debugging Information ==="
        log_debug "PGO deployment status:"
        kubectl describe deployment pgo || echo "Cannot describe PGO deployment"
        log_debug "PGO pods:"
        kubectl get pods -l postgres-operator.crunchydata.com/control-plane=postgres-operator -o wide || echo "Cannot get PGO pods"
        log_debug "PGO pod logs:"
        kubectl logs -l postgres-operator.crunchydata.com/control-plane=postgres-operator --tail=30 || echo "Cannot get PGO logs"
        log_debug "Recent events:"
        kubectl get events --sort-by='.lastTimestamp' | tail -15 || echo "Cannot get events"

        exit 1
    fi

    log_info "✅ PostgreSQL Operator is ready"
    kubectl get pods -l postgres-operator.crunchydata.com/control-plane=postgres-operator -o wide
}

# Integrated Helm dependency setup
setup_helm_dependencies() {
    log_info "Setting up Helm dependencies..."

    # Ensure we're in the k8s project root directory
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

    log_debug "Script directory: $SCRIPT_DIR"
    log_debug "Project root: $PROJECT_ROOT"

    cd "$PROJECT_ROOT" || {
        log_error "Failed to change to project root directory: $PROJECT_ROOT"
        exit 1
    }

    # Validate charts directory exists
    if [ ! -d "charts" ]; then
        log_error "charts/ directory not found in $(pwd)"
        log_error "Directory contents:"
        ls -la || true
        exit 1
    fi

    # Debug: Show current working directory and chart structure
    log_debug "Current working directory: $(pwd)"
    log_debug "Available charts directories:"
    ls -la charts/ || log_error "Failed to list charts/ directory"

    # Debug: Show initial helm repo state
    log_debug "Initial helm repositories:"
    helm repo list 2>/dev/null || log_debug "No repositories configured yet"

    # Add repositories from Chart.yaml files
    for chart in charts/*/; do
        if [ -f "$chart/Chart.yaml" ]; then
            log_info "Processing $chart..."
            log_debug "Chart.yaml content for $chart:"
            cat "$chart/Chart.yaml" | grep -A5 -B5 "repository:" || log_debug "No repository section found"

            # Extract unique repository URLs
            if grep -q "repository:" "$chart/Chart.yaml" 2>/dev/null; then
                log_debug "Found repository entries in $chart"
                repositories=$(grep "repository:" "$chart/Chart.yaml" 2>/dev/null | sed "s/.*repository: *//" | grep -v "file://" | sort -u)
                log_debug "Extracted repositories: $repositories"

                echo "$repositories" | while read -r repo; do
                    if [ -n "$repo" ]; then
                        # Clean up repository URL and create name
                        clean_repo=$(echo "$repo" | sed 's/"//g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                        repo_name=$(echo "$clean_repo" | sed "s|https://||" | sed "s|oci://||" | sed "s|/.*||" | sed "s/\./-/g")
                        log_info "Adding repository $repo_name -> $clean_repo"

                        # Add repository with error checking
                        if helm repo add "$repo_name" "$clean_repo" 2>&1; then
                            log_info "✅ Successfully added repository: $repo_name"
                        else
                            log_warn "⚠️ Failed to add repository: $repo_name ($clean_repo)"
                        fi
                    fi
                done
            else
                log_debug "No repository entries found in $chart/Chart.yaml"
            fi
        else
            log_warn "Chart.yaml not found in $chart"
        fi
    done

    # Debug: Show repositories after adding
    log_debug "Repositories after adding:"
    helm repo list || log_debug "Still no repositories configured"

    # Update repositories
    log_info "Updating helm repositories..."
    if helm repo update 2>&1; then
        log_info "✅ Repository update successful"
    else
        log_error "❌ Repository update failed"
        helm repo list || log_debug "No repositories to update"
    fi

    # Build dependencies
    for chart in charts/*/; do
        if [ -f "$chart/Chart.yaml" ]; then
            log_info "Building dependencies for $chart..."
            log_debug "Chart directory contents:"
            ls -la "$chart/" || true

            (
                cd "$chart" || exit
                log_debug "Building dependencies in $(pwd)"
                if helm dependency build 2>&1; then
                    log_info "✅ Dependencies built successfully for $chart"
                    log_debug "Dependencies after build:"
                    ls -la charts/ 2>/dev/null || log_debug "No charts/ subdirectory"
                else
                    log_error "❌ Failed to build dependencies for $chart"
                fi
            )
        fi
    done

    # Final debug: Show final state
    log_debug "Final helm repository state:"
    helm repo list || log_debug "No repositories configured"
    log_debug "Final Chart.lock files:"
    find charts/ -name "Chart.lock" -exec ls -la {} \; || log_debug "No Chart.lock files found"

    log_info "✅ Helm dependency setup complete"
}

# Deploy eoAPI function
deploy_eoapi() {
    log_info "Deploying eoAPI..."

    # Ensure we're in the k8s project root directory
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

    cd "$PROJECT_ROOT" || {
        log_error "Failed to change to project root directory: $PROJECT_ROOT"
        exit 1
    }

    # Validate charts directory exists
    if [ ! -d "charts" ]; then
        log_error "charts/ directory not found in $(pwd)"
        exit 1
    fi

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

    # Environment-specific configuration
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
        # Fix eoapi-notifier secret name dynamically
        HELM_CMD="$HELM_CMD --set eoapi-notifier.config.sources[0].config.connection.existingSecret.name=$RELEASE_NAME-pguser-eoapi"
        # Enable autoscaling for CI tests
        HELM_CMD="$HELM_CMD --set stac.autoscaling.enabled=true"
        HELM_CMD="$HELM_CMD --set stac.autoscaling.type=cpu"
        HELM_CMD="$HELM_CMD --set stac.autoscaling.targets.cpu=75"
        HELM_CMD="$HELM_CMD --set stac.autoscaling.minReplicas=1"
        HELM_CMD="$HELM_CMD --set stac.autoscaling.maxReplicas=3"
        HELM_CMD="$HELM_CMD --set raster.autoscaling.enabled=true"
        HELM_CMD="$HELM_CMD --set raster.autoscaling.type=cpu"
        HELM_CMD="$HELM_CMD --set raster.autoscaling.targets.cpu=75"
        HELM_CMD="$HELM_CMD --set raster.autoscaling.minReplicas=1"
        HELM_CMD="$HELM_CMD --set raster.autoscaling.maxReplicas=3"
        HELM_CMD="$HELM_CMD --set vector.autoscaling.enabled=true"
        HELM_CMD="$HELM_CMD --set vector.autoscaling.type=cpu"
        HELM_CMD="$HELM_CMD --set vector.autoscaling.targets.cpu=75"
        HELM_CMD="$HELM_CMD --set vector.autoscaling.minReplicas=1"
        HELM_CMD="$HELM_CMD --set vector.autoscaling.maxReplicas=3"
    elif [ -f "./eoapi/test-local-values.yaml" ]; then
        log_info "Using local test configuration..."
        HELM_CMD="$HELM_CMD -f ./eoapi/test-local-values.yaml"
        # Fix eoapi-notifier secret name dynamically for local mode too
        HELM_CMD="$HELM_CMD --set eoapi-notifier.config.sources[0].config.connection.existingSecret.name=$RELEASE_NAME-pguser-eoapi"
    else
        # Local development configuration (detect cluster type)
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

    cd "$PROJECT_ROOT" || exit

    # Wait for pgstac jobs to complete first
    if kubectl get job -n "$NAMESPACE" -l "app=$RELEASE_NAME-pgstac-migrate" >/dev/null 2>&1; then
        log_info "Waiting for pgstac-migrate job to complete..."
        if ! kubectl wait --for=condition=complete job -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE" --timeout=600s; then
            log_error "pgstac-migrate job failed to complete"
            kubectl describe job -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE"
            kubectl logs -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE" --tail=50 || true
            exit 1
        fi
    fi

    if kubectl get job -n "$NAMESPACE" -l "app=$RELEASE_NAME-pgstac-load-samples" >/dev/null 2>&1; then
        log_info "Waiting for pgstac-load-samples job to complete..."
        if ! kubectl wait --for=condition=complete job -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE" --timeout=600s; then
            log_error "pgstac-load-samples job failed to complete"
            kubectl describe job -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE"
            kubectl logs -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE" --tail=50 || true
            exit 1
        fi
    fi

    # Verify deployment
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

# CI-specific post-deployment validation
validate_ci_deployment() {
    log_info "=== CI Post-Deployment Validation ==="

    # Validate Helm dependencies
    log_info "Validating Helm Dependencies Post-Deployment..."

    # Check helm repositories
    log_info "Configured helm repositories:"
    helm repo list 2>/dev/null || log_warn "No repositories configured"
    echo ""

    # Check if Chart.lock files exist
    log_info "Chart.lock files:"
    find charts/ -name "Chart.lock" -exec ls -la {} \; 2>/dev/null || log_info "No Chart.lock files found"
    echo ""

    # Check if dependencies were downloaded
    log_info "Downloaded chart dependencies:"
    find charts/ -name "charts" -type d -exec ls -la {} \; 2>/dev/null || log_info "No chart dependencies found"
    echo ""

    # Check knative-operator specifically
    log_info "Checking for knative-operator deployment:"
    kubectl get deployment knative-operator --all-namespaces -o wide 2>/dev/null || log_info "knative-operator deployment not found"
    echo ""

    # Check helm release status
    log_info "Helm release status:"
    helm status "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || log_warn "Release status unavailable"
    echo ""

    # Check target namespace resources
    log_info "Resources in $NAMESPACE namespace:"
    kubectl get all -n "$NAMESPACE" -o wide 2>/dev/null || log_warn "No resources in $NAMESPACE namespace"
    echo ""

    # Check pod status specifically
    log_info "Pod status:"
    kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || log_warn "No pods in $NAMESPACE namespace"

    # Knative Integration Debug
    log_info "=== Knative Integration Debug ==="
    kubectl get deployments -l app.kubernetes.io/name=knative-operator --all-namespaces 2>/dev/null || log_info "Knative operator not found"
    kubectl get crd | grep knative 2>/dev/null || log_info "No Knative CRDs found"
    kubectl get knativeservings --all-namespaces -o wide 2>/dev/null || log_info "No KnativeServing resources"
    kubectl get knativeeventings --all-namespaces -o wide 2>/dev/null || log_info "No KnativeEventing resources"
    kubectl get pods -n knative-serving 2>/dev/null || log_info "No knative-serving namespace"
    kubectl get pods -n knative-eventing 2>/dev/null || log_info "No knative-eventing namespace"
    kubectl get pods -l app.kubernetes.io/name=eoapi-notifier -n "$NAMESPACE" 2>/dev/null || log_info "No eoapi-notifier pods"
    kubectl get ksvc -n "$NAMESPACE" 2>/dev/null || log_info "No Knative services in $NAMESPACE namespace"
    kubectl get sinkbindings -n "$NAMESPACE" 2>/dev/null || log_info "No SinkBindings in $NAMESPACE namespace"

    return 0
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

        # Post-deployment validation in CI mode
        if [ "$CI_MODE" = true ]; then
            validate_ci_deployment || exit 1
        fi
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        exit 1
        ;;
esac
