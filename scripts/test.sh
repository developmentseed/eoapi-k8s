#!/bin/bash
# shellcheck source=lib/common.sh

# eoAPI Test Suite
# Combined Helm and Integration Testing Script
# Supports both local development and CI environments

# Source shared utilities
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"

# Global variables
DEBUG_MODE=false
NAMESPACE=""
COMMAND=""

# Auto-detect CI environment
if is_ci_environment; then
    DEBUG_MODE=true
fi

# Show help message
show_help() {
    cat << EOF
eoAPI Test Suite - Combined Helm and Integration Testing

USAGE:
    $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
    helm              Run Helm tests only (lint, unit tests, template validation)
    integration       Run integration tests only (requires deployed eoAPI)
    all               Run both Helm and integration tests [default]
    check-deps        Check and install dependencies only
    check-deployment  Check eoAPI deployment status only

OPTIONS:
    --debug           Enable debug mode with enhanced logging and diagnostics
    --help, -h        Show this help message

DESCRIPTION:
    This script provides comprehensive testing for eoAPI:

    Helm Tests:
    - Chart linting with strict validation
    - Helm unit tests (if test files exist)
    - Template validation and rendering
    - Kubernetes manifest validation (if kubeval available)

    Integration Tests:
    - Deployment verification
    - Service readiness checks
    - API endpoint testing
    - Comprehensive failure debugging

REQUIREMENTS:
    Helm Tests: helm, helm unittest plugin
    Integration Tests: kubectl, python/pytest, deployed eoAPI instance

ENVIRONMENT VARIABLES:
    RELEASE_NAME             Override release name detection
    STAC_ENDPOINT            Override STAC API endpoint
    RASTER_ENDPOINT          Override Raster API endpoint
    VECTOR_ENDPOINT          Override Vector API endpoint

    CI                       Auto-enables debug mode if set

EXAMPLES:
    $(basename "$0")                    # Run all tests
    $(basename "$0") helm               # Run only Helm tests
    $(basename "$0") integration        # Run only integration tests
    $(basename "$0") check-deps         # Check dependencies only
    $(basename "$0") check-deployment   # Check deployment status only
    $(basename "$0") all --debug        # Run all tests with debug output
    $(basename "$0") integration --debug # Run integration tests with enhanced logging
    $(basename "$0") --help             # Show this help

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            helm|integration|all|check-deps|check-deployment)
                COMMAND="$1"; shift ;;
            --debug)
                DEBUG_MODE=true; shift ;;
            --help|-h)
                show_help; exit 0 ;;
            *)
                log_error "Unknown option: $1"
                show_help; exit 1 ;;
        esac
    done

    # Default to 'all' if no command specified
    if [ -z "$COMMAND" ]; then
        COMMAND="all"
    fi
}

# Command exists function is now in common.sh

# Check dependencies for helm tests
check_helm_dependencies() {
    preflight_test "helm" || exit 1

    # Install unittest plugin if needed
    if ! helm plugin list | grep -q unittest; then
        log_info "Installing helm unittest plugin..."
        helm plugin install https://github.com/helm-unittest/helm-unittest
    fi
}

# Check dependencies for integration tests
check_integration_dependencies() {
    preflight_test "integration" || exit 1
}

# Install Python test dependencies
install_test_deps() {
    log_info "Installing Python test dependencies..."

    local python_cmd="python"
    if command_exists python3; then
        python_cmd="python3"
    fi

    if ! $python_cmd -m pip install --quiet pytest httpx psycopg2-binary >/dev/null 2>&1; then
        log_error "Failed to install test dependencies (pytest, httpx, psycopg2-binary)"
        log_error "Please install manually: pip install pytest httpx psycopg2-binary"
        exit 1
    fi

    log_info "Test dependencies installed."
}

# Run Helm tests
run_helm_tests() {
    log_info "=== Running Helm Tests ==="

    local failed_charts=()

    # Run tests for each chart
    for chart in charts/*/; do
        if [ -f "$chart/Chart.yaml" ]; then
            chart_name=$(basename "$chart")
            log_info "Testing chart: $chart_name"

            # 1. Helm lint with dependencies
            log_info "  → Linting $chart_name..."
            if ! helm lint "$chart" --strict; then
                log_error "Linting failed for $chart_name"
                failed_charts+=("$chart_name")
                continue
            fi

            # 2. Helm unit tests (if test files exist)
            if find "$chart" -name "*.yaml" -path "*/tests/*" | grep -q .; then
                log_info "  → Running unit tests for $chart_name..."
                if ! helm unittest "$chart" -f "tests/*.yaml"; then
                    log_error "Unit tests failed for $chart_name"
                    failed_charts+=("$chart_name")
                    continue
                fi
            fi

            # 3. Template validation
            log_info "  → Validating templates for $chart_name..."
            if ! helm template test-release "$chart" --dry-run > /dev/null; then
                log_error "Template validation failed for $chart_name"
                failed_charts+=("$chart_name")
                continue
            fi

            # 4. K8s manifest validation (if kubeval available)
            if command_exists kubeval; then
                log_info "  → Validating K8s manifests for $chart_name..."
                if ! helm template test-release "$chart" | kubeval; then
                    log_error "K8s manifest validation failed for $chart_name"
                    failed_charts+=("$chart_name")
                    continue
                fi
            fi

            log_info "  ✅ $chart_name tests passed"
        fi
    done

    if [ ${#failed_charts[@]} -ne 0 ]; then
        log_error "Helm tests failed for charts: ${failed_charts[*]}"
        exit 1
    fi

    log_info "✅ All Helm tests passed"
}

# Check cluster connectivity
check_cluster() {
    validate_cluster || exit 1
}

# Detect release name and namespace from existing deployment
detect_deployment() {
    # Use environment variable if provided
    if [ -n "${RELEASE_NAME:-}" ]; then
        log_info "Using release name from environment: $RELEASE_NAME"
    else
        RELEASE_NAME=$(detect_release_name)
        log_info "Detected release name: $RELEASE_NAME"
        export RELEASE_NAME
    fi

    # Detect namespace
    if [ -z "$NAMESPACE" ]; then
        NAMESPACE=$(detect_namespace)
        log_info "Detected namespace: $NAMESPACE"
        export NAMESPACE
    else
        log_info "Using namespace from environment: $NAMESPACE"
    fi
}

# Show debug information
show_debug_info() {
    log_info "=== Enhanced Debug Information ==="

    log_info "=== Current Pod Status ==="
    kubectl get pods -n "$NAMESPACE" -o wide || true

    log_info "=== Pod Phase Summary ==="
    kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $3}' | sort | uniq -c || true

    log_info "=== Services Status ==="
    kubectl get services -n "$NAMESPACE" || true

    log_info "=== Ingress Status ==="
    kubectl get ingress -n "$NAMESPACE" || true

    log_info "=== Jobs Status ==="
    kubectl get jobs -n "$NAMESPACE" -o wide || true

    log_info "=== PostgreSQL Status ==="
    kubectl get postgrescluster -o wide || true
    kubectl get pods -l postgres-operator.crunchydata.com/cluster -o wide || true

    log_info "=== Recent Events ==="
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -30 || true
}

# Check if eoapi is deployed
check_eoapi_deployment() {
    if ! validate_eoapi_deployment "$NAMESPACE" "$RELEASE_NAME"; then
        if [ "$DEBUG_MODE" = true ]; then
            show_debug_info
        else
            log_info "You can deploy eoAPI using: make deploy or ./scripts/deploy.sh"
        fi
        exit 1
    fi
}

# Wait for services to be ready
wait_for_services() {
    log_info "Waiting for services to be ready..."

    # Function to wait for service with fallback label patterns
    wait_for_service() {
        local SERVICE=$1
        log_info "Waiting for $SERVICE service to be ready..."

        # Try multiple label patterns in order of preference
        local PATTERNS=(
            "app.kubernetes.io/instance=$RELEASE_NAME,app.kubernetes.io/name=$SERVICE"
            "app=$RELEASE_NAME-$SERVICE"
            "app.kubernetes.io/name=$SERVICE"
        )

        local FOUND_PODS=""
        for PATTERN in "${PATTERNS[@]}"; do
            FOUND_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$PATTERN" -o name 2>/dev/null)
            if [ -n "$FOUND_PODS" ]; then
                log_debug "Found $SERVICE pods using pattern: $PATTERN"
                kubectl get pods -n "$NAMESPACE" -l "$PATTERN" -o wide
                if kubectl wait --for=condition=Ready pod -l "$PATTERN" -n "$NAMESPACE" --timeout=180s 2>/dev/null; then
                    return 0
                else
                    log_warn "$SERVICE pods found but failed readiness check"
                    kubectl describe pods -n "$NAMESPACE" -l "$PATTERN" 2>/dev/null || true
                    return 1
                fi
            fi
        done

        # Fallback: find by pod name pattern
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" -o name | grep "$RELEASE_NAME-$SERVICE" | head -1)
        if [ -n "$POD_NAME" ]; then
            log_debug "Found $SERVICE pod by name pattern: $POD_NAME"
            kubectl get "$POD_NAME" -n "$NAMESPACE" -o wide
            if kubectl wait --for=condition=Ready "$POD_NAME" -n "$NAMESPACE" --timeout=180s 2>/dev/null; then
                return 0
            else
                log_warn "$SERVICE pod found but failed readiness check"
                kubectl describe "$POD_NAME" -n "$NAMESPACE" 2>/dev/null || true
                return 1
            fi
        fi

        log_error "No $SERVICE pods found with any pattern"
        return 1
    }

    # Wait for each service
    local failed_services=()
    for service in raster vector stac; do
        if ! wait_for_service "$service"; then
            failed_services+=("$service")
        fi
    done

    if [ ${#failed_services[@]} -ne 0 ]; then
        log_error "Failed to start services: ${failed_services[*]}"

        # Show debugging info
        log_info "=== Debugging service startup failures ==="
        kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || true
        kubectl get jobs -n "$NAMESPACE" -o wide 2>/dev/null || true
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true

        exit 1
    fi

    log_info "All services are ready!"
}

# Setup port forwarding for localhost access
setup_port_forwarding() {
    local release_name="$1"

    log_info "Setting up port forwarding for localhost access..."

    # Kill any existing port forwards to avoid conflicts
    pkill -f "kubectl port-forward.*$release_name" 2>/dev/null || true

    # Wait a moment for processes to clean up
    sleep 2

    # Set up port forwarding in background
    kubectl port-forward svc/"$release_name"-stac 8080:8080 -n "$NAMESPACE" >/dev/null 2>&1 &
    local stac_pid=$!

    kubectl port-forward svc/"$release_name"-raster 8081:8080 -n "$NAMESPACE" >/dev/null 2>&1 &
    local raster_pid=$!

    kubectl port-forward svc/"$release_name"-vector 8082:8080 -n "$NAMESPACE" >/dev/null 2>&1 &
    local vector_pid=$!

    # Give port forwards time to establish
    sleep 3

    # Check if port forwards are working
    local failed_services=()

    if ! netstat -ln 2>/dev/null | grep -q ":8080 "; then
        failed_services+=("stac")
        kill $stac_pid 2>/dev/null || true
    fi

    if ! netstat -ln 2>/dev/null | grep -q ":8081 "; then
        failed_services+=("raster")
        kill $raster_pid 2>/dev/null || true
    fi

    if ! netstat -ln 2>/dev/null | grep -q ":8082 "; then
        failed_services+=("vector")
        kill $vector_pid 2>/dev/null || true
    fi

    if [ ${#failed_services[@]} -eq 0 ]; then
        log_info "Port forwarding established successfully"
        # Update endpoints to use forwarded ports
        export STAC_ENDPOINT="http://127.0.0.1:8080/stac"
        export RASTER_ENDPOINT="http://127.0.0.1:8081/raster"
        export VECTOR_ENDPOINT="http://127.0.0.1:8082/vector"

        # Store PIDs for cleanup
        echo "$stac_pid $raster_pid $vector_pid" > /tmp/eoapi-port-forward-pids

        return 0
    else
        log_warn "Port forwarding failed for: ${failed_services[*]}"
        return 1
    fi
}

# Setup test environment
setup_test_environment() {
    # Use environment variables if already provided
    if [ -n "${STAC_ENDPOINT:-}" ] && [ -n "${RASTER_ENDPOINT:-}" ] && [ -n "${VECTOR_ENDPOINT:-}" ]; then
        log_info "Using endpoints from environment variables:"
        log_info "  STAC: $STAC_ENDPOINT"
        log_info "  Raster: $RASTER_ENDPOINT"
        log_info "  Vector: $VECTOR_ENDPOINT"
        return 0
    fi

    log_info "Setting up test environment..."

    # Try to get the Traefik service IP (K3s pattern)
    local publicip_value
    publicip_value=$(kubectl -n kube-system get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    # Fallback to other ingress controllers
    if [ -z "$publicip_value" ]; then
        publicip_value=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi

    # Try to get IP from ingress resources directly (works with minikube/nginx-ingress)
    if [ -z "$publicip_value" ] && [ -n "$NAMESPACE" ]; then
        publicip_value=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi

    # Fallback to check ingress in all namespaces
    if [ -z "$publicip_value" ]; then
        publicip_value=$(kubectl get ingress --all-namespaces -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi

    # Try to get external IP from ingress controller service (works in many cloud CI environments)
    if [ -z "$publicip_value" ]; then
        publicip_value=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    fi

    # Check for kind cluster (common in CI)
    if [ -z "$publicip_value" ] && command_exists kind; then
        if kind get clusters 2>/dev/null | grep -q .; then
            # Kind typically uses localhost with port mapping
            publicip_value="127.0.0.1"
        fi
    fi

    # Try to get Docker Desktop IP (common in local development)
    if [ -z "$publicip_value" ] && command_exists docker; then
        if docker info 2>/dev/null | grep -q "Docker Desktop"; then
            publicip_value="127.0.0.1"
        fi
    fi

    # Try to get node external IP for bare metal clusters
    if [ -z "$publicip_value" ]; then
        publicip_value=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
    fi

    # Fallback to node internal IP for bare metal/CI clusters
    if [ -z "$publicip_value" ]; then
        publicip_value=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
    fi

    # Try to get minikube IP if available
    if [ -z "$publicip_value" ] && command_exists minikube; then
        publicip_value=$(minikube ip 2>/dev/null || echo "")
    fi

    # Check for common CI environments and use localhost
    if [ -z "$publicip_value" ] && [ -n "$CI" ]; then
        # In many CI environments, services are accessible via localhost with port forwarding
        publicip_value="127.0.0.1"
    fi

    # Try to get ingress host
    local ingress_host=""
    if [ -n "$NAMESPACE" ]; then
        ingress_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    fi
    if [ -z "$ingress_host" ]; then
        ingress_host=$(kubectl get ingress -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    fi

    if [ "$DEBUG_MODE" = true ]; then
        log_info "=== Debug Mode: Enhanced endpoint detection ==="
        log_info "Ingress IP: $publicip_value"
        log_info "Ingress Host: $ingress_host"
    fi

    # Set up endpoints
    if [ -n "$publicip_value" ] && [ -n "$ingress_host" ]; then
        log_info "Found ingress IP: $publicip_value, host: $ingress_host"

        # Add to /etc/hosts if not already there
        if ! grep -q "$ingress_host" /etc/hosts 2>/dev/null; then
            if [ -w /etc/hosts ]; then
                echo "$publicip_value $ingress_host" >> /etc/hosts
                log_info "Added $ingress_host to /etc/hosts"
            elif command_exists sudo; then
                echo "$publicip_value $ingress_host" | sudo tee -a /etc/hosts >/dev/null
                log_info "Added $ingress_host to /etc/hosts (with sudo)"
            else
                log_warn "Cannot write to /etc/hosts - you may need to add '$publicip_value $ingress_host' manually"
            fi
        fi

        # Set endpoint environment variables
        export VECTOR_ENDPOINT="http://$ingress_host/vector"
        export STAC_ENDPOINT="http://$ingress_host/stac"
        export RASTER_ENDPOINT="http://$ingress_host/raster"

    elif [ -n "$publicip_value" ]; then
        log_info "Found ingress IP: $publicip_value"
        export VECTOR_ENDPOINT="http://$publicip_value/vector"
        export STAC_ENDPOINT="http://$publicip_value/stac"
        export RASTER_ENDPOINT="http://$publicip_value/raster"

    else
        log_warn "No external ingress found, attempting to use localhost with port forwarding"

        # Try to set up automatic port forwarding
        if setup_port_forwarding "$RELEASE_NAME"; then
            log_info "Successfully configured localhost access via port forwarding"
        else
            log_warn "Automatic port forwarding failed, using direct endpoints"
            log_warn "You may need to manually set up port forwarding:"
            log_warn "kubectl port-forward svc/$RELEASE_NAME-stac 8080:8080 -n $NAMESPACE &"
            log_warn "kubectl port-forward svc/$RELEASE_NAME-raster 8081:8080 -n $NAMESPACE &"
            log_warn "kubectl port-forward svc/$RELEASE_NAME-vector 8082:8080 -n $NAMESPACE &"

            # Fallback to direct endpoints (may not work)
            export VECTOR_ENDPOINT="http://127.0.0.1/vector"
            export STAC_ENDPOINT="http://127.0.0.1/stac"
            export RASTER_ENDPOINT="http://127.0.0.1/raster"
        fi
    fi

    log_info "Service endpoints configured:"
    log_info "  STAC: $STAC_ENDPOINT"
    log_info "  Raster: $RASTER_ENDPOINT"
    log_info "  Vector: $VECTOR_ENDPOINT"
}



# Run integration tests
run_integration_tests() {
    log_info "=== Running Integration Tests ==="

    local python_cmd="python"
    if command_exists python3; then
        python_cmd="python3"
    fi

    local test_dir=".github/workflows/tests"
    if [ ! -d "$test_dir" ]; then
        log_error "Test directory not found: $test_dir"
        exit 1
    fi

    log_info "Test environment:"
    log_info "  STAC_ENDPOINT=${STAC_ENDPOINT:-[not set]}"
    log_info "  RASTER_ENDPOINT=${RASTER_ENDPOINT:-[not set]}"
    log_info "  VECTOR_ENDPOINT=${VECTOR_ENDPOINT:-[not set]}"

    # Run tests individually with error handling
    local failed_tests=()

    # Vector tests
    log_info "=== Running vector tests ==="
    if ! $python_cmd -m pytest "$test_dir/test_vector.py" -v; then
        log_error "Vector tests failed"
        failed_tests+=("vector")

        # Show service logs on failure
        log_info "=== Vector service logs ==="
        kubectl logs svc/"$RELEASE_NAME"-vector -n "$NAMESPACE" --tail=50 2>/dev/null || \
        kubectl logs deployment/"$RELEASE_NAME"-vector -n "$NAMESPACE" --tail=50 2>/dev/null || \
        log_warn "Could not get vector service logs"
    else
        log_info "Vector tests passed"
    fi

    # STAC tests
    log_info "=== Running STAC tests ==="
    if ! $python_cmd -m pytest "$test_dir/test_stac.py" -v; then
        log_error "STAC tests failed"
        failed_tests+=("stac")

        # Show service logs on failure
        log_info "=== STAC service logs ==="
        kubectl logs svc/"$RELEASE_NAME"-stac -n "$NAMESPACE" --tail=50 2>/dev/null || \
        kubectl logs deployment/"$RELEASE_NAME"-stac -n "$NAMESPACE" --tail=50 2>/dev/null || \
        log_warn "Could not get STAC service logs"
    else
        log_info "STAC tests passed"
    fi

    # Raster tests
    log_info "=== Running raster tests ==="
    if ! $python_cmd -m pytest "$test_dir/test_raster.py" -v; then
        log_warn "Raster tests failed (known to be flaky)"
        failed_tests+=("raster")

        # Show service logs on failure
        log_info "=== Raster service logs ==="
        kubectl logs svc/"$RELEASE_NAME"-raster -n "$NAMESPACE" --tail=50 2>/dev/null || \
        kubectl logs deployment/"$RELEASE_NAME"-raster -n "$NAMESPACE" --tail=50 2>/dev/null || \
        log_warn "Could not get raster service logs"
    else
        log_info "Raster tests passed"
    fi

    # Notification system tests
    log_info "=== Running notification system tests ==="

    # Deploy CloudEvents sink for notification tests
    if kubectl apply -f "$SCRIPT_DIR/../charts/eoapi/samples/cloudevents-sink.yaml" >/dev/null 2>&1; then
        log_debug "CloudEvents sink deployed for notification tests"
        # Wait for the service to be ready
        kubectl wait --for=condition=Ready ksvc/eoapi-cloudevents-sink -n "$NAMESPACE" --timeout=60s >/dev/null 2>&1 || true
    else
        log_debug "CloudEvents sink already exists or failed to deploy"
    fi

    # Get database credentials for end-to-end tests
    local db_name db_user db_password port_forward_pid
    if db_name=$(kubectl get secret -n "$NAMESPACE" "${RELEASE_NAME}-pguser-eoapi" -o jsonpath='{.data.dbname}' 2>/dev/null | base64 -d 2>/dev/null) && \
       db_user=$(kubectl get secret -n "$NAMESPACE" "${RELEASE_NAME}-pguser-eoapi" -o jsonpath='{.data.user}' 2>/dev/null | base64 -d 2>/dev/null) && \
       db_password=$(kubectl get secret -n "$NAMESPACE" "${RELEASE_NAME}-pguser-eoapi" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null); then

        log_debug "Setting up database connection for end-to-end notification tests..."
        kubectl port-forward -n "$NAMESPACE" "svc/${RELEASE_NAME}-pgbouncer" 5433:5432 >/dev/null 2>&1 &
        port_forward_pid=$!
        sleep 3

        # Run tests with database connection
        local notification_test_env
        notification_test_env=$(cat << EOF
PGHOST=localhost
PGPORT=5433
PGDATABASE=$db_name
PGUSER=$db_user
PGPASSWORD=$db_password
NAMESPACE=$NAMESPACE
RELEASE_NAME=$RELEASE_NAME
EOF
        )

        if env "$notification_test_env" $python_cmd -m pytest "$test_dir/test_notifications.py" -v; then
            log_info "Notification system tests passed"
        else
            log_warn "Notification system tests failed"
            failed_tests+=("notifications")

            # Show eoapi-notifier logs on failure
            log_info "=== eoapi-notifier service logs ==="
            kubectl logs -l app.kubernetes.io/name=eoapi-notifier -n "$NAMESPACE" --tail=50 2>/dev/null || \
            log_warn "Could not get eoapi-notifier service logs"

            # Show CloudEvents sink logs on failure
            log_info "=== CloudEvents sink logs ==="
            kubectl logs -l serving.knative.dev/service -n "$NAMESPACE" --tail=50 2>/dev/null || \
            log_warn "Could not get Knative CloudEvents sink logs"
        fi

        # Clean up port forwarding
        if [ -n "$port_forward_pid" ]; then
            kill "$port_forward_pid" 2>/dev/null || true
            wait "$port_forward_pid" 2>/dev/null || true
        fi
    else
        log_warn "Could not retrieve database credentials, running basic notification tests only"
        if ! $python_cmd -m pytest "$test_dir/test_notifications.py" -v -k "not end_to_end"; then
            log_warn "Basic notification system tests failed"
            failed_tests+=("notifications")
        else
            log_info "Basic notification system tests passed"
        fi
    fi

    # PgSTAC notification tests
    log_info "=== Running PgSTAC notification tests ==="

    # Get database credentials from secret
    local db_name db_user db_password
    if db_name=$(kubectl get secret -n "$NAMESPACE" "${RELEASE_NAME}-pguser-eoapi" -o jsonpath='{.data.dbname}' 2>/dev/null | base64 -d 2>/dev/null) && \
       db_user=$(kubectl get secret -n "$NAMESPACE" "${RELEASE_NAME}-pguser-eoapi" -o jsonpath='{.data.user}' 2>/dev/null | base64 -d 2>/dev/null) && \
       db_password=$(kubectl get secret -n "$NAMESPACE" "${RELEASE_NAME}-pguser-eoapi" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null); then

        log_debug "Database credentials retrieved for pgstac notifications test"

        # Set up port forwarding to database
        log_debug "Setting up port forwarding to database..."
        kubectl port-forward -n "$NAMESPACE" "svc/${RELEASE_NAME}-pgbouncer" 5433:5432 >/dev/null 2>&1 &
        local port_forward_pid=$!

        # Give port forwarding time to establish
        sleep 3

        # Run the test with proper environment variables
        export PGHOST=localhost
        export PGPORT=5433
        export PGDATABASE=$db_name
        export PGUSER=$db_user
        export PGPASSWORD=$db_password

        if $python_cmd -m pytest "$test_dir/test_pgstac_notifications.py" -v; then
            log_info "PgSTAC notification tests passed"
        else
            log_warn "PgSTAC notification tests failed"
            failed_tests+=("pgstac-notifications")
        fi

        # Also run end-to-end notification test with same DB connection
        log_info "Running end-to-end notification flow test..."
        if NAMESPACE="$NAMESPACE" RELEASE_NAME="$RELEASE_NAME" $python_cmd -m pytest "$test_dir/test_notifications.py::test_end_to_end_notification_flow" -v; then
            log_info "End-to-end notification test passed"
        else
            log_warn "End-to-end notification test failed"
            failed_tests+=("e2e-notifications")
        fi

        # Clean up port forwarding
        if [ -n "$port_forward_pid" ]; then
            kill "$port_forward_pid" 2>/dev/null || true
            wait "$port_forward_pid" 2>/dev/null || true
        fi

    else
        log_warn "Could not retrieve database credentials for PgSTAC notification tests"
        failed_tests+=("pgstac-notifications")
    fi


    # Report results
    if [ ${#failed_tests[@]} -eq 0 ]; then
        log_info "✅ All integration tests completed successfully!"
    else
        log_error "Some tests failed: ${failed_tests[*]}"

        # Comprehensive debugging
        log_info "=== Final Deployment Status ==="
        kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || true
        kubectl get services -n "$NAMESPACE" 2>/dev/null || true
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true

        # Only fail if critical tests (vector/stac) failed
        if [[ " ${failed_tests[*]} " =~ " vector " ]] || [[ " ${failed_tests[*]} " =~ " stac " ]]; then
            exit 1
        else
            log_warn "Only raster tests failed (known issue), continuing..."
        fi
    fi
}

# Main function
main() {
    parse_args "$@"

    if [ "$DEBUG_MODE" = true ]; then
        log_info "Starting eoAPI test suite (DEBUG MODE) - Command: $COMMAND"
    else
        log_info "Starting eoAPI test suite - Command: $COMMAND"
    fi

    # Run tests based on command
    case $COMMAND in
        helm)
            check_helm_dependencies
            run_helm_tests
            ;;
        check-deps)
            log_info "Checking all dependencies..."
            check_helm_dependencies
            check_integration_dependencies
            check_cluster
            install_test_deps
            log_info "✅ All dependencies checked and ready"
            ;;
        check-deployment)
            log_info "Checking deployment status..."
            check_integration_dependencies
            check_cluster
            detect_deployment
            check_eoapi_deployment
            log_info "✅ Deployment check complete"
            ;;
        integration)
            check_integration_dependencies
            check_cluster
            install_test_deps
            detect_deployment

            # Show enhanced debugging in debug mode
            if [ "$DEBUG_MODE" = true ]; then
                show_debug_info
            fi

            check_eoapi_deployment

            wait_for_services
            setup_test_environment

            run_integration_tests
            ;;
        all)
            log_info "Running comprehensive test suite (Helm + Integration tests)"

            # Run Helm tests first
            log_info "=== Phase 1: Helm Tests ==="
            check_helm_dependencies
            run_helm_tests

            # Run Integration tests second
            log_info "=== Phase 2: Integration Tests ==="
            check_integration_dependencies
            check_cluster
            install_test_deps
            detect_deployment

            # Show enhanced debugging in debug mode
            if [ "$DEBUG_MODE" = true ]; then
                show_debug_info
            fi

            check_eoapi_deployment

            wait_for_services
            setup_test_environment

            run_integration_tests
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac

    # Clean up port forwarding if it was set up
    if [ -f /tmp/eoapi-port-forward-pids ]; then
        log_info "Cleaning up port forwarding..."
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < /tmp/eoapi-port-forward-pids
        rm -f /tmp/eoapi-port-forward-pids
    fi

    if [ "$DEBUG_MODE" = true ]; then
        log_info "eoAPI test suite complete (DEBUG MODE)!"
    else
        log_info "eoAPI test suite complete!"
    fi
}

# Run main function
main "$@"
