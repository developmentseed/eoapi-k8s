#!/usr/bin/env bash

# eoAPI Scripts - Kubernetes Helper Functions
# Source this file in other scripts: source "$(dirname "$0")/lib/k8s.sh"

# Include guard to prevent multiple sourcing
[[ -n "${_EOAPI_K8S_SH_LOADED:-}" ]] && return
readonly _EOAPI_K8S_SH_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

get_pod_name() {
    local namespace="$1"
    local selector="$2"

    kubectl get pods -n "$namespace" -l "$selector" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

get_service_endpoint() {
    local namespace="$1"
    local service="$2"
    local port="${3:-}"

    local cluster_ip
    cluster_ip=$(kubectl get svc "$service" -n "$namespace" \
        -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

    if [[ -z "$cluster_ip" ]]; then
        return 1
    fi

    if [[ -n "$port" ]]; then
        echo "${cluster_ip}:${port}"
    else
        local svc_port
        svc_port=$(kubectl get svc "$service" -n "$namespace" \
            -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "")
        echo "${cluster_ip}:${svc_port}"
    fi
}

resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"

    if [[ -n "$namespace" ]]; then
        kubectl get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null
    else
        kubectl get "$resource_type" "$resource_name" &>/dev/null
    fi
}

get_pod_status() {
    local namespace="$1"
    local pod_name="$2"

    kubectl get pod "$pod_name" -n "$namespace" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown"
}

all_pods_ready() {
    local namespace="$1"
    local selector="$2"

    local not_ready
    not_ready=$(kubectl get pods -n "$namespace" -l "$selector" \
        -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status!="True")].metadata.name}' \
        2>/dev/null || echo "error")

    [[ -z "$not_ready" ]]
}

port_forward() {
    local namespace="$1"
    local service="$2"
    local local_port="$3"
    local remote_port="${4:-$3}"

    log_info "Setting up port forward: localhost:$local_port -> $service:$remote_port"

    # Find a pod for the service
    local pod_name
    pod_name=$(get_pod_name "$namespace" "app.kubernetes.io/name=$service")

    if [[ -z "$pod_name" ]]; then
        # Try alternative label
        pod_name=$(get_pod_name "$namespace" "app=$service")
    fi

    if [[ -z "$pod_name" ]]; then
        log_error "No pod found for service: $service"
        return 1
    fi

    kubectl port-forward -n "$namespace" "pod/$pod_name" "${local_port}:${remote_port}"
}

exec_in_pod() {
    local namespace="$1"
    local pod_name="$2"
    local container="${3:-}"
    shift 3
    local cmd=("$@")

    if [[ -n "$container" ]]; then
        kubectl exec -n "$namespace" "$pod_name" -c "$container" -- "${cmd[@]}"
    else
        kubectl exec -n "$namespace" "$pod_name" -- "${cmd[@]}"
    fi
}

get_pod_logs() {
    local namespace="$1"
    local pod_name="$2"
    local container="${3:-}"
    local lines="${4:-100}"

    local opts=("--tail=$lines")
    [[ -n "$container" ]] && opts+=("-c" "$container")

    kubectl logs -n "$namespace" "$pod_name" "${opts[@]}"
}

scale_deployment() {
    local namespace="$1"
    local deployment="$2"
    local replicas="$3"

    log_info "Scaling $deployment to $replicas replicas"
    kubectl scale deployment "$deployment" -n "$namespace" --replicas="$replicas"
}

get_ingress_url() {
    local namespace="$1"
    local ingress_name="$2"

    local host
    host=$(kubectl get ingress "$ingress_name" -n "$namespace" \
        -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")

    if [[ -n "$host" ]]; then
        echo "http://${host}"
    else
        # Try to get LoadBalancer IP
        local ip
        ip=$(kubectl get ingress "$ingress_name" -n "$namespace" \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

        [[ -n "$ip" ]] && echo "http://${ip}" || echo ""
    fi
}

apply_manifest() {
    local manifest="$1"
    local namespace="${2:-}"

    local opts=()
    [[ -n "$namespace" ]] && opts+=("-n" "$namespace")

    if [[ "$manifest" =~ ^https?:// ]]; then
        log_info "Applying manifest from URL: $manifest"
        kubectl apply "${opts[@]}" -f "$manifest"
    elif [[ -f "$manifest" ]]; then
        log_info "Applying manifest from file: $manifest"
        kubectl apply "${opts[@]}" -f "$manifest"
    else
        log_error "Manifest not found: $manifest"
        return 1
    fi
}

delete_by_label() {
    local namespace="$1"
    local resource_type="$2"
    local label="$3"

    log_info "Deleting $resource_type with label: $label"
    kubectl delete "$resource_type" -n "$namespace" -l "$label" --ignore-not-found=true
}

wait_for_rollout() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-300}"

    log_info "Waiting for deployment rollout: $deployment"
    kubectl rollout status deployment "$deployment" -n "$namespace" --timeout="${timeout}s"
}

get_resource_usage() {
    local namespace="$1"
    local pod_name="${2:-}"

    if [[ -n "$pod_name" ]]; then
        kubectl top pod "$pod_name" -n "$namespace" --no-headers 2>/dev/null || echo "Metrics not available"
    else
        kubectl top pods -n "$namespace" --no-headers 2>/dev/null || echo "Metrics not available"
    fi
}

create_namespace() {
    local namespace="$1"

    if ! resource_exists "namespace" "$namespace"; then
        log_info "Creating namespace: $namespace"
        kubectl create namespace "$namespace"
    else
        log_debug "Namespace already exists: $namespace"
    fi
}

get_secret_value() {
    local namespace="$1"
    local secret_name="$2"
    local key="$3"

    kubectl get secret "$secret_name" -n "$namespace" \
        -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d
}

upsert_secret() {
    local namespace="$1"
    local secret_name="$2"
    local key="$3"
    local value="$4"

    if resource_exists "secret" "$secret_name" "$namespace"; then
        log_info "Updating secret: $secret_name"
        kubectl delete secret "$secret_name" -n "$namespace" --ignore-not-found=true
    else
        log_info "Creating secret: $secret_name"
    fi

    kubectl create secret generic "$secret_name" -n "$namespace" \
        --from-literal="${key}=${value}"
}

get_configmap_value() {
    local namespace="$1"
    local configmap_name="$2"
    local key="${3:-}"

    if [[ -n "$key" ]]; then
        kubectl get configmap "$configmap_name" -n "$namespace" \
            -o jsonpath="{.data.$key}" 2>/dev/null
    else
        kubectl get configmap "$configmap_name" -n "$namespace" \
            -o jsonpath='{.data}' 2>/dev/null
    fi
}

patch_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local patch="$4"
    local patch_type="${5:-strategic}"

    log_info "Patching $resource_type/$resource_name"
    kubectl patch "$resource_type" "$resource_name" -n "$namespace" \
        --type="$patch_type" -p "$patch"
}

# Export functions
export -f get_pod_name get_service_endpoint resource_exists
export -f get_pod_status all_pods_ready port_forward
export -f exec_in_pod get_pod_logs scale_deployment
export -f get_ingress_url apply_manifest delete_by_label
export -f wait_for_rollout get_resource_usage create_namespace
export -f get_secret_value upsert_secret get_configmap_value
export -f patch_resource
