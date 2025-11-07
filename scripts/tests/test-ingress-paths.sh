#!/bin/bash

# Test script to validate ROOT_PATH behavior with ingress

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=${NAMESPACE:-"eoapi"}
RELEASE_NAME=${RELEASE_NAME:-"eoapi"}
INGRESS_URL=${INGRESS_URL:-""}
DEBUG=${DEBUG:-"false"}

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

debug_log() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "[DEBUG] $1"
    fi
}

# Get ingress URL if not provided
get_ingress_url() {
    if [ -z "$INGRESS_URL" ]; then
        log_info "Detecting ingress URL..."

        # Try to get ingress IP
        local ingress_ip
        ingress_ip=$(kubectl get ingress "${RELEASE_NAME}-ingress" -n "$NAMESPACE" \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

        if [ -z "$ingress_ip" ]; then
            # Try hostname if IP not found
            ingress_ip=$(kubectl get ingress "${RELEASE_NAME}-ingress" -n "$NAMESPACE" \
                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
        fi

        if [ -z "$ingress_ip" ]; then
            log_error "Could not determine ingress URL. Please set INGRESS_URL environment variable."
            exit 1
        fi

        INGRESS_URL="http://$ingress_ip"
        log_info "Using ingress URL: $INGRESS_URL"
    fi
}

# Check if service has ROOT_PATH set
check_root_path_env() {
    local service=$1
    local expected_path=$2

    log_info "Checking ROOT_PATH for $service service..."

    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app=${RELEASE_NAME}-${service}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [ -z "$pod_name" ]; then
        log_warn "No pod found for $service service"
        return 1
    fi

    local root_path
    root_path=$(kubectl exec -n "$NAMESPACE" "$pod_name" -- env | grep "^ROOT_PATH=" | cut -d= -f2 || true)

    if [ "$root_path" = "$expected_path" ]; then
        log_info "✅ ROOT_PATH correctly set to '$expected_path' for $service"
        return 0
    else
        log_error "❌ ROOT_PATH mismatch for $service. Expected: '$expected_path', Got: '$root_path'"
        return 1
    fi
}

# Test API endpoint with path prefix
test_api_endpoint() {
    local service=$1
    local path=$2
    local endpoint=$3

    local url="${INGRESS_URL}${path}${endpoint}"
    log_info "Testing $service API at: $url"

    local response
    local status_code

    # Make request and capture status code
    response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null || true)
    status_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | head -n-1)

    debug_log "Response status: $status_code"
    debug_log "Response body (first 200 chars): ${response:0:200}"

    if [ "$status_code" = "200" ] || [ "$status_code" = "204" ]; then
        log_info "✅ $service endpoint responded successfully"
        return 0
    else
        log_error "❌ $service endpoint failed with status $status_code"
        return 1
    fi
}

# Test pagination links include path prefix
test_pagination_links() {
    local service=$1
    local path=$2
    local list_endpoint=$3

    local url="${INGRESS_URL}${path}${list_endpoint}"
    log_info "Testing pagination links at: $url"

    local response
    response=$(curl -s "$url" 2>/dev/null || true)

    debug_log "Pagination response (first 500 chars): ${response:0:500}"

    # Check if links contain the path prefix
    if echo "$response" | grep -q "\"href\".*\"${INGRESS_URL}${path}"; then
        log_info "✅ Pagination links correctly include path prefix '$path'"
        return 0
    elif echo "$response" | grep -q "\"href\".*\"${path}"; then
        log_info "✅ Pagination links include relative path prefix '$path'"
        return 0
    else
        log_warn "⚠️ Could not verify pagination links include path prefix"
        debug_log "Full response: $response"
        return 1
    fi
}

# Main test execution
main() {
    log_info "=== ROOT_PATH Ingress Test Suite ==="
    log_info "Namespace: $NAMESPACE"
    log_info "Release: $RELEASE_NAME"

    # Get ingress URL
    get_ingress_url

    local failed=0

    # Check if ingress is enabled
    if ! kubectl get ingress "${RELEASE_NAME}-ingress" -n "$NAMESPACE" &>/dev/null; then
        log_error "Ingress not found. Is ingress.enabled=true?"
        exit 1
    fi

    # Test STAC service
    if kubectl get deployment "${RELEASE_NAME}-stac" -n "$NAMESPACE" &>/dev/null; then
        log_info "--- Testing STAC Service ---"
        check_root_path_env "stac" "/stac" || ((failed++))
        test_api_endpoint "stac" "/stac" "/_mgmt/ping" || ((failed++))
        test_api_endpoint "stac" "/stac" "/" || ((failed++))

        # Test STAC collections pagination
        if test_api_endpoint "stac" "/stac" "/collections" > /dev/null 2>&1; then
            test_pagination_links "stac" "/stac" "/collections?limit=1" || ((failed++))
        fi
    fi

    # Test Raster service
    if kubectl get deployment "${RELEASE_NAME}-raster" -n "$NAMESPACE" &>/dev/null; then
        log_info "--- Testing Raster Service ---"
        check_root_path_env "raster" "/raster" || ((failed++))
        test_api_endpoint "raster" "/raster" "/healthz" || ((failed++))
        test_api_endpoint "raster" "/raster" "/" || ((failed++))

        # Test raster searches pagination (if searches exist)
        if curl -s "${INGRESS_URL}/raster/searches/list" 2>/dev/null | grep -q "searches"; then
            test_pagination_links "raster" "/raster" "/searches/list?limit=1" || ((failed++))
        fi
    fi

    # Test Vector service
    if kubectl get deployment "${RELEASE_NAME}-vector" -n "$NAMESPACE" &>/dev/null; then
        log_info "--- Testing Vector Service ---"
        check_root_path_env "vector" "/vector" || ((failed++))
        test_api_endpoint "vector" "/vector" "/healthz" || ((failed++))
        test_api_endpoint "vector" "/vector" "/" || ((failed++))
    fi

    # Summary
    echo ""
    if [ $failed -eq 0 ]; then
        log_info "=== ✅ All ROOT_PATH tests passed ==="
        exit 0
    else
        log_error "=== ❌ $failed tests failed ==="
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --ingress-url)
            INGRESS_URL="$2"
            shift 2
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        --help)
            cat << EOF
Usage: $(basename "$0") [OPTIONS]

Test ROOT_PATH configuration with ingress

OPTIONS:
    --namespace NAME     Kubernetes namespace (default: eoapi)
    --release NAME       Helm release name (default: eoapi)
    --ingress-url URL    Ingress URL (auto-detected if not set)
    --debug              Enable debug output
    --help               Show this help message

EXAMPLES:
    $(basename "$0")
    $(basename "$0") --namespace myns --release myrelease
    $(basename "$0") --ingress-url http://localhost:8080
    $(basename "$0") --debug

EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main
