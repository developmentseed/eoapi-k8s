#!/bin/bash

# eoAPI Scripts - Cleanup Library
# Contains deployment cleanup logic extracted from deploy.sh

set -euo pipefail

# Source required libraries
CLEANUP_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$CLEANUP_SCRIPT_DIR/common.sh"
source "$CLEANUP_SCRIPT_DIR/validation.sh"

# Main cleanup function
cleanup_deployment() {
    log_info "=== Starting eoAPI Cleanup ==="
    log_info "Cleaning up resources for release: $RELEASE_NAME in namespace: $NAMESPACE"

    # Validate namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_warn "Namespace '$NAMESPACE' not found, skipping cleanup"
        return 0
    fi

    # Cleanup steps
    cleanup_helm_release || log_warn "Failed to cleanup Helm release"
    cleanup_persistent_volumes || log_warn "Failed to cleanup persistent volumes"
    cleanup_custom_resources || log_warn "Failed to cleanup custom resources"
    cleanup_namespace || log_warn "Failed to cleanup namespace"

    log_info "✅ eoAPI cleanup completed"
    return 0
}

# Cleanup Helm release
cleanup_helm_release() {
    log_info "Cleaning up Helm release: $RELEASE_NAME"

    if helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_info "Uninstalling Helm release: $RELEASE_NAME"
        if helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout="$TIMEOUT"; then
            log_info "✅ Helm release uninstalled successfully"
        else
            log_error "Failed to uninstall Helm release: $RELEASE_NAME"
            return 1
        fi
    else
        log_debug "Helm release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
    fi

    return 0
}

# Cleanup persistent volumes and claims
cleanup_persistent_volumes() {
    log_info "Cleaning up persistent volumes and claims..."

    # Get PVCs in the namespace
    local pvcs
    pvcs=$(kubectl get pvc -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$pvcs" ]; then
        log_info "Found PVCs to cleanup: $pvcs"
        for pvc in $pvcs; do
            log_debug "Deleting PVC: $pvc"
            cleanup_resource pvc "$pvc" "$NAMESPACE"
        done
    else
        log_debug "No PVCs found in namespace: $NAMESPACE"
    fi

    # Cleanup orphaned PVs (those with reclaim policy Delete)
    local orphaned_pvs
    orphaned_pvs=$(kubectl get pv -o jsonpath='{.items[?(@.spec.claimRef.namespace=="'"$NAMESPACE"'")].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$orphaned_pvs" ]; then
        log_info "Found orphaned PVs to cleanup: $orphaned_pvs"
        for pv in $orphaned_pvs; do
            log_debug "Deleting PV: $pv"
            cleanup_resource pv "$pv" ""
        done
    else
        log_debug "No orphaned PVs found for namespace: $NAMESPACE"
    fi

    return 0
}

# Cleanup custom resources (PostgreSQL clusters, etc.)
cleanup_custom_resources() {
    log_info "Cleaning up custom resources..."

    # Cleanup PostgreSQL clusters
    cleanup_postgres_clusters

    # Cleanup other CRDs that might be present
    local crds=("postgresclusters.postgres-operator.crunchydata.com")

    for crd in "${crds[@]}"; do
        if kubectl get crd "$crd" >/dev/null 2>&1; then
            local resources
            resources=$(kubectl get "$crd" -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

            if [ -n "$resources" ]; then
                log_info "Found $crd resources to cleanup: $resources"
                for resource in $resources; do
                    log_debug "Deleting $crd: $resource"
                    cleanup_resource "$crd" "$resource" "$NAMESPACE"
                done
            fi
        fi
    done

    return 0
}

# Cleanup PostgreSQL clusters specifically
cleanup_postgres_clusters() {
    log_info "Cleaning up PostgreSQL clusters..."

    # Check if PostgreSQL operator CRD exists
    if ! kubectl get crd postgresclusters.postgres-operator.crunchydata.com >/dev/null 2>&1; then
        log_debug "PostgreSQL operator CRD not found, skipping cluster cleanup"
        return 0
    fi

    # Get PostgreSQL clusters in the namespace
    local pg_clusters
    pg_clusters=$(kubectl get postgresclusters -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$pg_clusters" ]; then
        log_info "Found PostgreSQL clusters to cleanup: $pg_clusters"

        for cluster in $pg_clusters; do
            log_info "Deleting PostgreSQL cluster: $cluster"

            # Try graceful deletion first
            if kubectl delete postgrescluster "$cluster" -n "$NAMESPACE" --timeout=60s >/dev/null 2>&1; then
                log_debug "PostgreSQL cluster deleted gracefully: $cluster"
            else
                log_warn "Graceful deletion failed for cluster: $cluster, forcing deletion"
                kubectl patch postgrescluster "$cluster" -n "$NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
                kubectl delete postgrescluster "$cluster" -n "$NAMESPACE" --force --grace-period=0 >/dev/null 2>&1 || true
            fi
        done

        # Wait for clusters to be fully removed
        log_info "Waiting for PostgreSQL clusters to be fully removed..."
        local max_wait=120
        local wait_time=0

        while [ $wait_time -lt $max_wait ]; do
            local remaining
            remaining=$(kubectl get postgresclusters -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

            if [ -z "$remaining" ]; then
                log_info "✅ All PostgreSQL clusters removed"
                break
            fi

            log_debug "Still waiting for clusters to be removed: $remaining"
            sleep 5
            wait_time=$((wait_time + 5))
        done

        if [ $wait_time -ge $max_wait ]; then
            log_warn "Timeout waiting for PostgreSQL clusters to be removed"
        fi
    else
        log_debug "No PostgreSQL clusters found in namespace: $NAMESPACE"
    fi

    return 0
}

# Cleanup namespace
cleanup_namespace() {
    log_info "Cleaning up namespace: $NAMESPACE"

    # Skip if it's a system namespace
    case "$NAMESPACE" in
        default|kube-*|postgres-operator)
            log_info "Skipping cleanup of system namespace: $NAMESPACE"
            return 0
            ;;
    esac

    # Check if namespace has other resources
    local remaining_resources
    remaining_resources=$(kubectl api-resources --verbs=list --namespaced -o name | \
        xargs -I {} sh -c "kubectl get {} -n $NAMESPACE --ignore-not-found --no-headers 2>/dev/null | wc -l" | \
        awk '{sum+=$1} END {print sum}' 2>/dev/null || echo "0")

    if [ "${remaining_resources:-0}" -gt 0 ]; then
        log_warn "Namespace '$NAMESPACE' still contains $remaining_resources resources"
        log_info "Use 'kubectl get all,pvc,secrets,configmaps -n $NAMESPACE' to see remaining resources"
        return 0
    fi

    # Delete the namespace
    log_info "Deleting empty namespace: $NAMESPACE"
    if kubectl delete namespace "$NAMESPACE" --timeout=60s >/dev/null 2>&1; then
        log_info "✅ Namespace deleted successfully: $NAMESPACE"
    else
        log_warn "Failed to delete namespace: $NAMESPACE"
        # Try to remove finalizers and force delete
        kubectl patch namespace "$NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
        kubectl delete namespace "$NAMESPACE" --force --grace-period=0 >/dev/null 2>&1 || true
    fi

    return 0
}

# Generic resource cleanup with retry logic
cleanup_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_namespace="$3"

    log_debug "Cleaning up $resource_type: $resource_name"

    local kubectl_args=(delete "$resource_type" "$resource_name")

    if [ -n "$resource_namespace" ]; then
        kubectl_args+=(--namespace "$resource_namespace")
    fi

    # Try graceful deletion first
    if kubectl "${kubectl_args[@]}" --timeout=30s >/dev/null 2>&1; then
        log_debug "✅ $resource_type/$resource_name deleted gracefully"
        return 0
    fi

    # If graceful deletion fails, try to remove finalizers
    log_debug "Graceful deletion failed for $resource_type/$resource_name, trying to remove finalizers"

    local patch_args=(patch "$resource_type" "$resource_name" -p '{"metadata":{"finalizers":null}}' --type=merge)
    if [ -n "$resource_namespace" ]; then
        patch_args+=(--namespace "$resource_namespace")
    fi

    kubectl "${patch_args[@]}" >/dev/null 2>&1 || true

    # Force deletion
    local force_args=(delete "$resource_type" "$resource_name" --force --grace-period=0)
    if [ -n "$resource_namespace" ]; then
        force_args+=(--namespace "$resource_namespace")
    fi

    if kubectl "${force_args[@]}" >/dev/null 2>&1; then
        log_debug "✅ $resource_type/$resource_name force deleted"
    else
        log_warn "Failed to delete $resource_type/$resource_name"
    fi

    return 0
}

# Cleanup PostgreSQL Operator (optional)
cleanup_pgo() {
    log_info "Cleaning up PostgreSQL Operator..."

    local pgo_namespace="${POSTGRES_OPERATOR_NAMESPACE:-postgres-operator}"

    # Check if PGO is installed
    if ! helm status pgo -n "$pgo_namespace" >/dev/null 2>&1; then
        log_debug "PostgreSQL Operator not found, skipping cleanup"
        return 0
    fi

    # Ask for confirmation in interactive mode
    if [ -t 0 ] && [ "${FORCE_CLEANUP:-false}" != "true" ]; then
        log_warn "This will remove the PostgreSQL Operator which may affect other deployments"
        read -p "Continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "PostgreSQL Operator cleanup cancelled"
            return 0
        fi
    fi

    log_info "Uninstalling PostgreSQL Operator..."
    if helm uninstall pgo -n "$pgo_namespace" --timeout="$TIMEOUT"; then
        log_info "✅ PostgreSQL Operator uninstalled"

        # Cleanup PGO namespace if empty
        local remaining_resources
        remaining_resources=$(kubectl get all -n "$pgo_namespace" --ignore-not-found --no-headers 2>/dev/null | wc -l || echo "0")

        if [ "${remaining_resources:-0}" -eq 0 ]; then
            log_info "Cleaning up empty PostgreSQL Operator namespace: $pgo_namespace"
            kubectl delete namespace "$pgo_namespace" >/dev/null 2>&1 || true
        fi
    else
        log_error "Failed to uninstall PostgreSQL Operator"
        return 1
    fi

    return 0
}

# Show cleanup status
show_cleanup_status() {
    log_info "=== Cleanup Status ==="

    # Check if release still exists
    if helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_warn "Helm release still exists: $RELEASE_NAME"
    else
        log_info "✅ Helm release cleaned up: $RELEASE_NAME"
    fi

    # Check if namespace still exists
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        local resource_count
        resource_count=$(kubectl get all -n "$NAMESPACE" --ignore-not-found --no-headers 2>/dev/null | wc -l || echo "0")

        if [ "${resource_count:-0}" -gt 0 ]; then
            log_warn "Namespace '$NAMESPACE' still contains $resource_count resources"
        else
            log_info "✅ Namespace is empty: $NAMESPACE"
        fi
    else
        log_info "✅ Namespace cleaned up: $NAMESPACE"
    fi

    return 0
}

# Export functions
export -f cleanup_deployment cleanup_helm_release cleanup_persistent_volumes
export -f cleanup_custom_resources cleanup_postgres_clusters cleanup_namespace
export -f cleanup_resource cleanup_pgo show_cleanup_status
