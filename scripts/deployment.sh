#!/usr/bin/env bash

# eoAPI Scripts - Deployment Management
# Deploy and debug eoAPI instances on Kubernetes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/k8s.sh"

# Defaults
readonly RELEASE_NAME="${RELEASE_NAME:-eoapi}"
readonly NAMESPACE="${NAMESPACE:-eoapi}"
readonly PGO_VERSION="${PGO_VERSION:-5.7.4}"
readonly TIMEOUT="${TIMEOUT:-6m}"

show_help() {
    cat <<EOF
Deployment Management for eoAPI

USAGE:
    $(basename "$0") [OPTIONS] <COMMAND> [ARGS]

COMMANDS:
    run             Deploy eoAPI with Helm
    debug           Show deployment diagnostics

OPTIONS:
    -h, --help      Show this help message
    -d, --debug     Enable debug mode
    -n, --namespace Set Kubernetes namespace
    --release NAME  Helm release name (default: ${RELEASE_NAME})
    --timeout TIME  Deployment timeout (default: ${TIMEOUT})

EXAMPLES:
    # Deploy eoAPI
    $(basename "$0") run

    # Debug deployment
    $(basename "$0") debug
EOF
}

run_deployment() {
    log_info "Deploying eoAPI (release: ${RELEASE_NAME}, namespace: ${NAMESPACE})"

    check_requirements kubectl helm || return 1
    validate_cluster || return 1

    create_namespace "$NAMESPACE"

    log_info "Installing PostgreSQL Operator v${PGO_VERSION}..."
    if helm list -q | grep -q "^pgo$"; then
        helm upgrade pgo oci://registry.developers.crunchydata.com/crunchydata/pgo \
            --version "$PGO_VERSION" --set disable_check_for_upgrades=true
    else
        helm install pgo oci://registry.developers.crunchydata.com/crunchydata/pgo \
            --version "$PGO_VERSION" --set disable_check_for_upgrades=true
    fi

    log_info "Waiting for PGO to be ready..."
    kubectl wait --for=condition=Available deployment/pgo --timeout=300s

    cd "$PROJECT_ROOT"
    log_info "Updating Helm dependencies..."
    helm dependency update charts/eoapi

    local helm_cmd="helm upgrade --install $RELEASE_NAME charts/eoapi -n $NAMESPACE --create-namespace"

    if [[ -f "charts/eoapi/profiles/experimental.yaml" ]]; then
        log_info "Applying experimental profile..."
        helm_cmd="$helm_cmd -f charts/eoapi/profiles/experimental.yaml"
    fi
    if [[ -f "charts/eoapi/profiles/local/k3s.yaml" ]]; then
        log_info "Applying k3s local profile..."
        helm_cmd="$helm_cmd -f charts/eoapi/profiles/local/k3s.yaml"
    fi

    helm_cmd="$helm_cmd --set eoapi-notifier.config.sources[0].type=pgstac"
    helm_cmd="$helm_cmd --set eoapi-notifier.config.sources[0].config.connection.existingSecret.name=$RELEASE_NAME-pguser-eoapi"

    if is_ci; then
        log_info "Applying CI-specific configurations..."

        helm_cmd="$helm_cmd --set testing=true"
        helm_cmd="$helm_cmd --set monitoring.prometheusAdapter.prometheus.url=http://$RELEASE_NAME-prometheus-server.eoapi.svc.cluster.local"
    fi

    helm_cmd="$helm_cmd --timeout $TIMEOUT"

    log_info "Deploying eoAPI..."
    if eval "$helm_cmd"; then
        log_success "eoAPI deployed successfully"

        if kubectl get job -n "$NAMESPACE" -l "app=$RELEASE_NAME-pgstac-migrate" >/dev/null 2>&1; then
            log_info "Waiting for pgstac-migrate job to complete..."
            if ! kubectl wait --for=condition=complete job -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE" --timeout=600s; then
                log_error "pgstac-migrate job failed to complete"
                kubectl describe job -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE"
                kubectl logs -l "app=$RELEASE_NAME-pgstac-migrate" -n "$NAMESPACE" --tail=50 || true
                return 1
            fi
        fi

        if kubectl get job -n "$NAMESPACE" -l "app=$RELEASE_NAME-pgstac-load-samples" >/dev/null 2>&1; then
            log_info "Waiting for pgstac-load-samples job to complete..."
            if ! kubectl wait --for=condition=complete job -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE" --timeout=600s; then
                log_error "pgstac-load-samples job failed to complete"
                kubectl describe job -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE"
                kubectl logs -l "app=$RELEASE_NAME-pgstac-load-samples" -n "$NAMESPACE" --tail=50 || true
                return 1
            fi
        fi

        log_info "Waiting for deployments to be ready..."
        kubectl wait --for=condition=Available deployment --all -n "$NAMESPACE" --timeout="$TIMEOUT" || {
            log_warn "Some deployments may not be ready yet"
        }

        echo ""
        kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME"
        echo ""

        log_info "Available services:"
        kubectl get svc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME"

        # Wait for monitoring stack if deployed
        if kubectl get deployment -l app.kubernetes.io/name=prometheus -n "$NAMESPACE" &>/dev/null; then
            log_info "Waiting for monitoring components..."
            kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=server,app.kubernetes.io/name=prometheus -n "$NAMESPACE" --timeout=120s &
            kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n "$NAMESPACE" --timeout=120s &
            kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus-adapter -n "$NAMESPACE" --timeout=120s &
            wait # Wait for all background jobs
            log_success "Monitoring stack ready"
            kubectl get hpa -n "$NAMESPACE" 2>/dev/null || true
        fi
    else
        log_error "Deployment failed"
        return 1
    fi
}

debug_deployment() {
    log_info "Debugging eoAPI deployment (namespace: ${NAMESPACE})"

    check_requirements kubectl helm || return 1

    echo ""
    echo "═══ Helm Releases ═══"
    helm list -n "$NAMESPACE"

    echo ""
    echo "═══ Pod Status ═══"
    kubectl get pods -n "$NAMESPACE" -o wide

    echo ""
    echo "═══ Pod Descriptions ═══"
    for pod in $(kubectl get pods -n "$NAMESPACE" -o name); do
        echo "── ${pod#pod/} ──"
        kubectl describe "$pod" -n "$NAMESPACE" | grep -E "^(Status:|Ready:|Restart Count:|Events:)" -A 5
        echo ""
    done

    echo "═══ Services ═══"
    kubectl get svc -n "$NAMESPACE"

    echo ""
    echo "═══ Ingress ═══"
    kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "No ingress found"

    echo ""
    echo "═══ Recent Events ═══"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20

    echo ""
    echo "═══ Recent Logs (last 50 lines per pod) ═══"
    for pod in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
        echo "── $pod ──"
        kubectl logs -n "$NAMESPACE" "$pod" --tail=50 2>/dev/null || echo "No logs available"
        echo ""
    done

    echo "═══ Health Check ═══"
    local issues=0

    pending=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
    if [[ $pending -gt 0 ]]; then
        log_warn "Found $pending pending pods"
        ((issues++))
    fi

    crashloop=$(kubectl get pods -n "$NAMESPACE" -o json | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason == "CrashLoopBackOff") | .metadata.name' 2>/dev/null | wc -l)
    if [[ $crashloop -gt 0 ]]; then
        log_warn "Found $crashloop pods in CrashLoopBackOff"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "No obvious issues detected"
    else
        log_warn "Found $issues potential issues"
    fi
}

main() {
    local timeout="$TIMEOUT"
    local release_name="$RELEASE_NAME"
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
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --release)
                release_name="$2"
                RELEASE_NAME="$release_name"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                TIMEOUT="$timeout"
                shift 2
                ;;
            run|debug)
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

    if [[ -z "$command" ]]; then
        log_error "No command specified"
        show_help
        exit 1
    fi

    case "$command" in
        run)
            run_deployment
            ;;
        debug)
            debug_deployment
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
