#!/bin/bash
# Observability utility functions for eoAPI Kubernetes deployments
# Provides monitoring, metrics, and autoscaling validation capabilities

# Colors for output formatting
readonly OBS_RED='\033[0;31m'
readonly OBS_GREEN='\033[0;32m'
readonly OBS_YELLOW='\033[1;33m'
readonly OBS_BLUE='\033[0;34m'
readonly OBS_NC='\033[0m' # No Color

# Logging functions
obs_log_info() {
    printf "${OBS_BLUE}[OBS-INFO]${OBS_NC} %s\n" "$1"
}

obs_log_success() {
    printf "${OBS_GREEN}[OBS-SUCCESS]${OBS_NC} %s\n" "$1"
}

obs_log_warning() {
    printf "${OBS_YELLOW}[OBS-WARNING]${OBS_NC} %s\n" "$1"
}

obs_log_error() {
    printf "${OBS_RED}[OBS-ERROR]${OBS_NC} %s\n" "$1"
}

# Check if a command exists
obs_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get namespace with fallback
get_obs_namespace() {
    echo "${NAMESPACE:-eoapi}"
}

# Get release name with fallback
get_obs_release_name() {
    echo "${RELEASE_NAME:-eoapi}"
}

# Check if monitoring components are deployed
check_monitoring_deployment() {
    local namespace
    namespace=$(get_obs_namespace)
    local component="$1"
    local label_selector="$2"

    if [ -z "$component" ] || [ -z "$label_selector" ]; then
        obs_log_error "check_monitoring_deployment requires component name and label selector"
        return 1
    fi

    local pod_count
    pod_count=$(kubectl get pods -n "$namespace" -l "$label_selector" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [ "$pod_count" -gt 0 ]; then
        obs_log_success "$component is running ($pod_count pods)"
        return 0
    else
        # Check if pods exist but not running
        local total_pods
        total_pods=$(kubectl get pods -n "$namespace" -l "$label_selector" --no-headers 2>/dev/null | wc -l)
        if [ "$total_pods" -gt 0 ]; then
            obs_log_warning "$component pods exist but not running ($total_pods pods)"
            return 1
        else
            obs_log_info "$component not deployed"
            return 2
        fi
    fi
}

# Check Prometheus deployment and health
check_prometheus_health() {
    local namespace
    namespace=$(get_obs_namespace)

    obs_log_info "Checking Prometheus health..."

    # Check deployment
    if ! check_monitoring_deployment "Prometheus" "app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server"; then
        return $?
    fi

    # Check service exists
    if ! kubectl get svc -n "$namespace" -l "app.kubernetes.io/name=prometheus" >/dev/null 2>&1; then
        obs_log_warning "Prometheus service not found"
        return 1
    fi

    obs_log_success "Prometheus is healthy"
    return 0
}

# Check Grafana deployment and health
check_grafana_health() {
    local namespace
    namespace=$(get_obs_namespace)

    obs_log_info "Checking Grafana health..."

    # Check deployment
    if ! check_monitoring_deployment "Grafana" "app.kubernetes.io/name=grafana"; then
        return $?
    fi

    # Check service exists
    if ! kubectl get svc -n "$namespace" -l "app.kubernetes.io/name=grafana" >/dev/null 2>&1; then
        obs_log_warning "Grafana service not found"
        return 1
    fi

    # Check for admin secret
    if ! kubectl get secret -n "$namespace" -o name | grep -q grafana; then
        obs_log_warning "Grafana admin secret not found"
    fi

    obs_log_success "Grafana is healthy"
    return 0
}

# Check prometheus-adapter health
check_prometheus_adapter_health() {
    local namespace
    namespace=$(get_obs_namespace)

    obs_log_info "Checking prometheus-adapter health..."

    # Check deployment
    if ! check_monitoring_deployment "prometheus-adapter" "app.kubernetes.io/name=prometheus-adapter"; then
        return $?
    fi

    # Check custom metrics API
    if kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" >/dev/null 2>&1; then
        obs_log_success "Custom metrics API is available"
    else
        obs_log_warning "Custom metrics API not accessible"
        return 1
    fi

    obs_log_success "prometheus-adapter is healthy"
    return 0
}

# Check HPA resources and status
check_hpa_status() {
    local namespace
    namespace=$(get_obs_namespace)
    local service_name="$1"  # optional: check specific service

    obs_log_info "Checking HPA status..."

    local hpa_selector=""
    if [ -n "$service_name" ]; then
        hpa_selector="-l app.kubernetes.io/component=$service_name-hpa"
    fi

    if ! kubectl get hpa -n "$namespace" "$hpa_selector" >/dev/null 2>&1; then
        obs_log_info "No HPA resources found"
        return 2
    fi

    local hpa_count
    hpa_count=$(kubectl get hpa -n "$namespace" "$hpa_selector" --no-headers 2>/dev/null | wc -l)
    obs_log_info "Found $hpa_count HPA resource(s)"

    # Check HPA status details
    local unhealthy_hpas=""
    local unhealthy_count=0
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local hpa_name
            local targets
            hpa_name=$(echo "$line" | awk '{print $1}')
            targets=$(echo "$line" | awk '{print $4}')

            if echo "$targets" | grep -q "<unknown>"; then
                unhealthy_hpas="$unhealthy_hpas $hpa_name"
                unhealthy_count=$((unhealthy_count + 1))
                obs_log_warning "HPA $hpa_name has unknown metrics"
            else
                obs_log_success "HPA $hpa_name is reporting metrics: $targets"
            fi
        fi
    done << EOF
$(kubectl get hpa -n "$namespace" "$hpa_selector" --no-headers 2>/dev/null)
EOF

    if [ $unhealthy_count -eq 0 ]; then
        obs_log_success "All HPA resources are healthy"
        return 0
    else
        obs_log_warning "$unhealthy_count HPA resource(s) have issues:$unhealthy_hpas"
        return 1
    fi
}

# Get pod resource metrics
get_pod_metrics() {
    local namespace
    namespace=$(get_obs_namespace)
    local service_name="$1"

    if [ -z "$service_name" ]; then
        obs_log_error "get_pod_metrics requires service name"
        return 1
    fi

    obs_log_info "Getting metrics for $service_name..."

    if ! obs_command_exists kubectl; then
        obs_log_error "kubectl not found"
        return 1
    fi

    if ! kubectl top pods -n "$namespace" -l "app=eoapi-$service_name" --no-headers 2>/dev/null; then
        obs_log_warning "Cannot get pod metrics for $service_name (metrics-server may not be ready)"
        return 1
    fi

    return 0
}

# Validate custom metrics API
validate_custom_metrics_api() {
    obs_log_info "Validating custom metrics API..."

    if ! kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" >/dev/null 2>&1; then
        obs_log_error "Custom metrics API not available"
        return 1
    fi

    # Get available metrics
    local metrics_json
    metrics_json=$(kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" 2>/dev/null)
    if [ -n "$metrics_json" ]; then
        local metric_count
        metric_count=$(echo "$metrics_json" | grep -o '"name"' | wc -l)
        obs_log_success "Custom metrics API is available with $metric_count metric types"
    else
        obs_log_warning "Custom metrics API available but no metrics registered"
    fi

    return 0
}

# Setup port forwarding for monitoring services
setup_monitoring_port_forward() {
    local service="$1"
    local local_port="$2"
    local remote_port="$3"
    local namespace
    namespace=$(get_obs_namespace)

    if [ -z "$service" ] || [ -z "$local_port" ] || [ -z "$remote_port" ]; then
        obs_log_error "setup_monitoring_port_forward requires service, local_port, and remote_port"
        return 1
    fi

    obs_log_info "Setting up port forward for $service ($local_port:$remote_port)..."

    # Check if service exists
    if ! kubectl get svc "$service" -n "$namespace" >/dev/null 2>&1; then
        obs_log_error "Service $service not found in namespace $namespace"
        return 1
    fi

    # Start port forwarding in background
    kubectl port-forward "svc/$service" "$local_port:$remote_port" -n "$namespace" >/dev/null 2>&1 &
    local pf_pid=$!

    # Give it time to establish
    sleep 3

    # Check if port forward is working
    if kill -0 $pf_pid 2>/dev/null; then
        obs_log_success "Port forward established (PID: $pf_pid)"
        echo $pf_pid  # Return PID for cleanup
        return 0
    else
        obs_log_error "Failed to establish port forward"
        return 1
    fi
}

# Wait for monitoring stack to be ready
wait_for_monitoring_stack() {
    local timeout="${1:-300}"  # 5 minutes default
    local namespace
    namespace=$(get_obs_namespace)

    obs_log_info "Waiting for monitoring stack to be ready (timeout: ${timeout}s)..."

    local start_time
    start_time=$(date +%s)
    local components="prometheus:app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server grafana:app.kubernetes.io/name=grafana prometheus-adapter:app.kubernetes.io/name=prometheus-adapter"

    while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
        local all_ready=true

        for component_spec in $components; do
            local component_name=${component_spec%%:*}
            local selector=${component_spec#*:}

            if ! kubectl wait --for=condition=Ready pod -l "$selector" -n "$namespace" --timeout=10s >/dev/null 2>&1; then
                obs_log_info "Waiting for $component_name to be ready..."
                all_ready=false
                break
            fi
        done

        if [ "$all_ready" = true ]; then
            obs_log_success "Monitoring stack is ready"
            return 0
        fi

        sleep 10
    done

    obs_log_error "Timeout waiting for monitoring stack to be ready"
    return 1
}

# Generate synthetic load for testing autoscaling
generate_synthetic_load() {
    local base_url="$1"
    local duration="${2:-60}"
    local concurrent_requests="${3:-5}"
    local delay="${4:-0.1}"

    if [ -z "$base_url" ]; then
        obs_log_error "generate_synthetic_load requires base_url"
        return 1
    fi

    obs_log_info "Generating synthetic load..."
    obs_log_info "URL: $base_url, Duration: ${duration}s, Concurrent: $concurrent_requests, Delay: ${delay}s"

    if ! obs_command_exists curl; then
        obs_log_error "curl not found"
        return 1
    fi

    # Test endpoints for load generation
    local endpoints="/stac/collections /stac/search?collections=noaa-emergency-response&limit=50 /raster/collections /vector/collections"

    local success_count=0
    local error_count=0
    local pids=""

    # Worker function for load generation
    load_worker() {
        local end_time=$(($(date +%s) + duration))

        while [ "$(date +%s)" -lt "$end_time" ]; do
            for endpoint in $endpoints; do
                local url="$base_url$endpoint"
                if curl -s -f "$url" >/dev/null 2>&1; then
                    success_count=$((success_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
                sleep "$delay"
            done
        done
    }

    # Start concurrent workers
    local i=1
    while [ "$i" -le "$concurrent_requests" ]; do
        load_worker $i &
        pids="$pids $!"
        i=$((i + 1))
    done

    # Wait for all workers to complete
    for pid in $pids; do
        wait "$pid"
    done

    local total_requests=$((success_count + error_count))
    local success_rate=0
    if [ $total_requests -gt 0 ]; then
        success_rate=$(( (success_count * 100) / total_requests ))
    fi

    obs_log_info "Load test completed: $total_requests requests ($success_count success, $error_count errors, ${success_rate}% success rate)"

    return 0
}

# Get comprehensive monitoring stack status
get_monitoring_stack_status() {
    local namespace
    namespace=$(get_obs_namespace)

    obs_log_info "=== Monitoring Stack Status ==="

    # Check each component
    local components="Prometheus:app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server Grafana:app.kubernetes.io/name=grafana prometheus-adapter:app.kubernetes.io/name=prometheus-adapter kube-state-metrics:app.kubernetes.io/name=kube-state-metrics node-exporter:app.kubernetes.io/name=prometheus-node-exporter"

    local healthy_count=0
    local total_count=5

    for component_spec in $components; do
        local component_name=${component_spec%%:*}
        local selector=${component_spec#*:}

        if check_monitoring_deployment "$component_name" "$selector"; then
            healthy_count=$((healthy_count + 1))
        fi
    done

    obs_log_info "Healthy components: $healthy_count/$total_count"

    # Check HPA status
    check_hpa_status "$@"

    # Check custom metrics API
    validate_custom_metrics_api

    obs_log_info "=== End Monitoring Stack Status ==="

    return 0
}

# Cleanup monitoring port forwards
cleanup_monitoring_port_forwards() {
    obs_log_info "Cleaning up monitoring port forwards..."

    # Kill any kubectl port-forward processes
    pkill -f "kubectl port-forward.*prometheus" 2>/dev/null || true
    pkill -f "kubectl port-forward.*grafana" 2>/dev/null || true

    obs_log_info "Port forward cleanup completed"
}

# Test Prometheus connectivity (with port forward)
test_prometheus_connectivity() {
    local namespace
    namespace=$(get_obs_namespace)
    local timeout="${1:-30}"

    obs_log_info "Testing Prometheus connectivity..."

    # Find Prometheus service
    local prom_service
    prom_service=$(kubectl get svc -n "$namespace" -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$prom_service" ]; then
        obs_log_error "Prometheus service not found"
        return 1
    fi

    # Setup port forward
    local pf_pid
    if ! pf_pid=$(setup_monitoring_port_forward "$prom_service" 9090 80); then
        return 1
    fi

    # Test connectivity
    local connected=false
    local start_time
    start_time=$(date +%s)

    while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
        if curl -s "http://localhost:9090/api/v1/query?query=up" >/dev/null 2>&1; then
            connected=true
            break
        fi
        sleep 2
    done

    # Cleanup port forward
    kill "$pf_pid" 2>/dev/null || true

    if [ "$connected" = true ]; then
        obs_log_success "Prometheus is accessible and responding"
        return 0
    else
        obs_log_error "Cannot connect to Prometheus API"
        return 1
    fi
}

# Validate observability prerequisites
validate_observability_prerequisites() {
    obs_log_info "Validating observability prerequisites..."

    local missing_deps=""
    local missing_count=0

    # Check required tools
    local required_tools="kubectl curl python3"
    for tool in $required_tools; do
        if ! obs_command_exists "$tool"; then
            missing_deps="$missing_deps $tool"
            missing_count=$((missing_count + 1))
        fi
    done

    if [ $missing_count -gt 0 ]; then
        obs_log_error "Missing required tools:$missing_deps"
        return 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        obs_log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    # Check namespace exists
    local namespace
    namespace=$(get_obs_namespace)
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        obs_log_error "Namespace $namespace does not exist"
        return 1
    fi

    obs_log_success "Observability prerequisites validated"
    return 0
}

# Functions are available when script is sourced
# Note: Function exports removed for compatibility with different shells
