#!/bin/bash

# eoAPI Scripts - Core Deployment Library
# Contains the main deployment logic extracted from deploy.sh

set -euo pipefail

# Source required libraries
DEPLOY_CORE_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DEPLOY_CORE_SCRIPT_DIR/common.sh"
source "$DEPLOY_CORE_SCRIPT_DIR/validation.sh"

# Default configuration
PGO_VERSION="${PGO_VERSION:-5.7.4}"
POSTGRES_OPERATOR_NAMESPACE="${POSTGRES_OPERATOR_NAMESPACE:-postgres-operator}"

# Main deployment function
deploy_eoapi() {
    log_info "=== Starting eoAPI Deployment ==="

    # Debug: Show current variable values
    log_debug "Current deployment configuration:"
    log_debug "  NAMESPACE: '$NAMESPACE'"
    log_debug "  RELEASE_NAME: '$RELEASE_NAME'"
    log_debug "  TIMEOUT: '$TIMEOUT'"
    log_debug "  DEBUG_MODE: '$DEBUG_MODE'"
    if [ "${#HELM_VALUES_FILES[@]}" -gt 0 ]; then
        log_debug "  HELM_VALUES_FILES: ${HELM_VALUES_FILES[*]}"
    fi
    if [ "${#HELM_SET_VALUES[@]}" -gt 0 ]; then
        log_debug "  HELM_SET_VALUES: ${HELM_SET_VALUES[*]}"
    fi

    # Ensure we're in the correct directory
    local project_root
    project_root="$(cd "$DEPLOY_CORE_SCRIPT_DIR/../.." && pwd)"

    log_debug "Project root: $project_root"
    cd "$project_root" || {
        log_error "Failed to change to project root directory: $project_root"
        return 1
    }

    # Pre-deployment validation
    validate_deploy_tools || return 1
    validate_cluster_connection || return 1

    # Run deployment steps
    setup_namespace || return 1
    install_pgo || return 1
    setup_helm_dependencies || return 1
    deploy_eoapi_chart || return 1

    log_info "✅ eoAPI deployment completed successfully"
    return 0
}

# Setup target namespace
setup_namespace() {
    log_info "Setting up namespace: $NAMESPACE"
    log_debug "Current NAMESPACE variable value: '$NAMESPACE'"
    log_debug "Current RELEASE_NAME variable value: '$RELEASE_NAME'"

    # List existing namespaces for debugging
    if [ "$DEBUG_MODE" = true ]; then
        log_debug "Existing namespaces:"
        kubectl get namespaces --no-headers | awk '{print "  - " $1}' >&2
    fi

    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_debug "Namespace '$NAMESPACE' already exists"
    else
        log_info "Creating namespace: $NAMESPACE"
        log_debug "Running: kubectl create namespace $NAMESPACE"
        if ! kubectl create namespace "$NAMESPACE"; then
            log_error "Failed to create namespace: $NAMESPACE"
            log_error "kubectl error output:"
            kubectl create namespace "$NAMESPACE" 2>&1 || true
            return 1
        fi
        log_info "✅ Successfully created namespace: $NAMESPACE"
    fi

    # Verify namespace was created/exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace verification failed - namespace '$NAMESPACE' does not exist after setup"
        return 1
    fi

    log_debug "✅ Namespace '$NAMESPACE' is ready"
    return 0
}

# Install PostgreSQL Operator
install_pgo() {
    log_info "Installing PostgreSQL Operator..."

    # Check if PGO is already installed
    local existing_pgo
    existing_pgo=$(helm list -A -q 2>/dev/null | grep "^pgo$" || echo "")

    if [ -n "$existing_pgo" ]; then
        log_info "PostgreSQL Operator already installed, checking version..."
        local current_version
        current_version=$(helm list -A -f "^pgo$" -o json 2>/dev/null | jq -r '.[0].app_version // "unknown"' 2>/dev/null || echo "unknown")
        log_debug "Current PGO version: $current_version"

        if [ "$current_version" != "$PGO_VERSION" ]; then
            log_info "Upgrading PostgreSQL Operator from $current_version to $PGO_VERSION"
            upgrade_pgo || return 1
        else
            log_debug "PostgreSQL Operator version $PGO_VERSION already installed"
        fi
        return 0
    fi

    log_info "Installing fresh PostgreSQL Operator v$PGO_VERSION"

    # Create namespace for PGO
    if ! kubectl get namespace "$POSTGRES_OPERATOR_NAMESPACE" >/dev/null 2>&1; then
        log_info "Creating PostgreSQL Operator namespace: $POSTGRES_OPERATOR_NAMESPACE"
        kubectl create namespace "$POSTGRES_OPERATOR_NAMESPACE" || {
            log_error "Failed to create PostgreSQL Operator namespace"
            return 1
        }
    fi

    # Install PGO
    if ! helm install pgo \
        --create-namespace \
        --namespace "$POSTGRES_OPERATOR_NAMESPACE" \
        --version "$PGO_VERSION" \
        oci://registry.developers.crunchydata.com/crunchydata/pgo; then
        log_error "Failed to install PostgreSQL Operator"
        return 1
    fi

    # Wait for PGO to be ready
    log_info "Waiting for PostgreSQL Operator to be ready..."
    if ! kubectl wait --for=condition=Available deployment/pgo \
        -n "$POSTGRES_OPERATOR_NAMESPACE" \
        --timeout=300s; then
        log_error "PostgreSQL Operator failed to become ready"
        return 1
    fi

    log_info "✅ PostgreSQL Operator installed successfully"
    return 0
}

# Upgrade PostgreSQL Operator
upgrade_pgo() {
    log_info "Upgrading PostgreSQL Operator to v$PGO_VERSION"

    if ! helm upgrade pgo \
        --namespace "$POSTGRES_OPERATOR_NAMESPACE" \
        --version "$PGO_VERSION" \
        oci://registry.developers.crunchydata.com/crunchydata/pgo; then
        log_error "Failed to upgrade PostgreSQL Operator"
        return 1
    fi

    # Wait for upgrade to complete
    if ! kubectl wait --for=condition=Available deployment/pgo \
        -n "$POSTGRES_OPERATOR_NAMESPACE" \
        --timeout=300s; then
        log_error "PostgreSQL Operator upgrade failed to complete"
        return 1
    fi

    log_info "✅ PostgreSQL Operator upgraded successfully"
    return 0
}

# Setup Helm dependencies
setup_helm_dependencies() {
    log_info "Setting up Helm dependencies..."

    local charts_dir="./charts"
    if [ ! -d "$charts_dir" ]; then
        log_error "Charts directory not found: $charts_dir"
        return 1
    fi

    # Update Helm repositories
    log_info "Updating Helm repositories..."
    if ! helm repo update; then
        log_warn "Failed to update Helm repositories, continuing anyway..."
    fi

    # Build dependencies for each chart
    for chart_dir in "$charts_dir"/*; do
        if [ -d "$chart_dir" ] && [ -f "$chart_dir/Chart.yaml" ]; then
            local chart_name
            chart_name=$(basename "$chart_dir")

            if [ -f "$chart_dir/Chart.lock" ]; then
                log_debug "Dependencies already locked for $chart_name"
                continue
            fi

            log_info "Building dependencies for chart: $chart_name"
            if ! helm dependency build "$chart_dir"; then
                log_error "Failed to build dependencies for chart: $chart_name"
                return 1
            fi
        fi
    done

    log_info "✅ Helm dependencies setup completed"
    return 0
}

# Deploy the main eoAPI chart
deploy_eoapi_chart() {
    log_info "Deploying eoAPI chart..."

    local chart_path="./charts/eoapi"

    # Validate chart exists
    if ! validate_helm_chart "$chart_path"; then
        log_error "Invalid eoAPI chart at: $chart_path"
        return 1
    fi

    # Check if release already exists
    if helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_info "eoAPI release already exists, upgrading..."
        upgrade_eoapi_chart || return 1
    else
        log_info "Installing new eoAPI release..."
        install_eoapi_chart || return 1
    fi

    # Wait for deployment to be ready
    wait_for_eoapi_ready || return 1

    log_info "✅ eoAPI chart deployed successfully"
    return 0
}

# Install eoAPI chart
install_eoapi_chart() {
    local chart_path="./charts/eoapi"

    local helm_args=(
        install "$RELEASE_NAME" "$chart_path"
        --namespace "$NAMESPACE"
        --create-namespace
        --timeout "$TIMEOUT"
    )

    # Add values files if they exist
    if [ -f "values.yaml" ]; then
        helm_args+=(--values "values.yaml")
        log_debug "Using values file: values.yaml"
    fi

    if [ -f "values-local.yaml" ]; then
        helm_args+=(--values "values-local.yaml")
        log_debug "Using local values file: values-local.yaml"
    fi

    # Add custom values files from command line
    if [ "${#HELM_VALUES_FILES[@]}" -gt 0 ]; then
        for values_file in "${HELM_VALUES_FILES[@]}"; do
            helm_args+=(--values "$values_file")
            log_debug "Using custom values file: $values_file"
        done
    fi

    # Add --set values if provided
    if [ "${#HELM_SET_VALUES[@]}" -gt 0 ]; then
        for value in "${HELM_SET_VALUES[@]}"; do
            helm_args+=(--set "$value")
            log_debug "Adding --set: $value"
        done
    fi

    # Execute helm install
    if ! helm "${helm_args[@]}"; then
        log_error "Failed to install eoAPI chart"
        return 1
    fi

    return 0
}

# Upgrade eoAPI chart
upgrade_eoapi_chart() {
    local chart_path="./charts/eoapi"

    local helm_args=(
        upgrade "$RELEASE_NAME" "$chart_path"
        --namespace "$NAMESPACE"
        --timeout "$TIMEOUT"
        --wait
    )

    # Add values files if they exist
    if [ -f "values.yaml" ]; then
        helm_args+=(--values "values.yaml")
        log_debug "Using values file: values.yaml"
    fi

    if [ -f "values-local.yaml" ]; then
        helm_args+=(--values "values-local.yaml")
        log_debug "Using local values file: values-local.yaml"
    fi

    # Add custom values files from command line
    if [ "${#HELM_VALUES_FILES[@]}" -gt 0 ]; then
        for values_file in "${HELM_VALUES_FILES[@]}"; do
            helm_args+=(--values "$values_file")
            log_debug "Using custom values file: $values_file"
        done
    fi

    # Add --set values if provided
    if [ "${#HELM_SET_VALUES[@]}" -gt 0 ]; then
        for value in "${HELM_SET_VALUES[@]}"; do
            helm_args+=(--set "$value")
            log_debug "Adding --set: $value"
        done
    fi

    # Execute helm upgrade
    if ! helm "${helm_args[@]}"; then
        log_error "Failed to upgrade eoAPI chart"
        return 1
    fi

    return 0
}

# Wait for eoAPI deployment to be ready
wait_for_eoapi_ready() {
    log_info "Waiting for eoAPI services to be ready..."

    local services=("stac" "raster" "vector")
    local max_attempts=30
    local attempt=0

    for service in "${services[@]}"; do
        log_info "Waiting for $service service to be ready..."

        attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if wait_for_pods "$NAMESPACE" "app=$RELEASE_NAME-$service" "60s"; then
                log_info "✅ $service service is ready"
                break
            fi

            attempt=$((attempt + 1))
            if [ $attempt -eq $max_attempts ]; then
                log_error "Timeout waiting for $service service to be ready"
                return 1
            fi

            log_debug "Attempt $attempt/$max_attempts for $service service..."
            sleep 10
        done
    done

    log_info "✅ All eoAPI services are ready"
    return 0
}

# Get deployment status and URLs
get_deployment_info() {
    log_info "=== eoAPI Deployment Information ==="

    # Show Helm release status
    log_info "Helm release status:"
    helm status "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || {
        log_warn "Unable to get Helm release status"
    }

    # Show service URLs
    log_info "Service endpoints:"
    local ingress_ip
    ingress_ip=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -n "$ingress_ip" ]; then
        log_info "  STAC API: http://$ingress_ip/stac"
        log_info "  TiTiler: http://$ingress_ip/raster"
        log_info "  TiPG: http://$ingress_ip/vector"
        log_info "  STAC Browser: http://$ingress_ip/browser"
    else
        log_info "  Use 'kubectl port-forward' to access services locally"
        log_info "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-stac 8080:80"
    fi

    return 0
}

# Export functions
export -f deploy_eoapi setup_namespace install_pgo upgrade_pgo
export -f setup_helm_dependencies deploy_eoapi_chart
export -f install_eoapi_chart upgrade_eoapi_chart wait_for_eoapi_ready
export -f get_deployment_info
