#!/bin/bash

# eoAPI Data Ingestion Script

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"

DEFAULT_COLLECTIONS_FILE="./collections.json"
DEFAULT_ITEMS_FILE="./items.json"

if [ "$#" -eq 2 ]; then
    EOAPI_COLLECTIONS_FILE="$1"
    EOAPI_ITEMS_FILE="$2"
else
    EOAPI_COLLECTIONS_FILE="$DEFAULT_COLLECTIONS_FILE"
    EOAPI_ITEMS_FILE="$DEFAULT_ITEMS_FILE"
    log_info "No specific files provided. Using defaults:"
    log_info "  Collections file: $EOAPI_COLLECTIONS_FILE"
    log_info "  Items file: $EOAPI_ITEMS_FILE"
fi

# Run pre-flight checks
if ! preflight_ingest "$(detect_namespace)" "$EOAPI_COLLECTIONS_FILE" "$EOAPI_ITEMS_FILE"; then
    exit 1
fi

# Detect namespace and raster pod
FOUND_NAMESPACE=$(detect_namespace)
log_info "Using namespace: $FOUND_NAMESPACE"

# Find raster pod using multiple patterns
EOAPI_POD_RASTER=""
PATTERNS=(
    "app=raster-eoapi"
    "app.kubernetes.io/name=raster"
    "app.kubernetes.io/component=raster"
)

for pattern in "${PATTERNS[@]}"; do
    EOAPI_POD_RASTER=$(kubectl get pods -n "$FOUND_NAMESPACE" -l "$pattern" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")
    if [ -n "$EOAPI_POD_RASTER" ]; then
        log_info "Found raster pod: $EOAPI_POD_RASTER (pattern: $pattern)"
        break
    fi
done

# Check if the pod was found
if [ -z "$EOAPI_POD_RASTER" ]; then
    log_error "Could not find raster pod in namespace: $FOUND_NAMESPACE"
    log_error "Available pods:"
    kubectl get pods -n "$FOUND_NAMESPACE" -o name 2>/dev/null || true
    exit 1
fi

# Validate pod is ready
log_info "Validating pod readiness..."
if ! kubectl wait --for=condition=Ready pod "$EOAPI_POD_RASTER" -n "$FOUND_NAMESPACE" --timeout=30s; then
    log_error "Pod $EOAPI_POD_RASTER is not ready"
    kubectl describe pod "$EOAPI_POD_RASTER" -n "$FOUND_NAMESPACE"
    exit 1
fi

# Check if pypgstac is already available (avoid unnecessary installations)
log_info "Checking for pypgstac in pod..."
if kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- python3 -c "import pypgstac" >/dev/null 2>&1; then
    log_info "pypgstac already available"
else
    log_info "Installing pypgstac in pod $EOAPI_POD_RASTER..."
    if ! kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- bash -c 'pip install pypgstac[psycopg]'; then
        log_error "Failed to install pypgstac"
        exit 1
    fi
fi

# Copy files to pod
log_info "Copying files to pod..."
log_info "  Collections: $EOAPI_COLLECTIONS_FILE"
log_info "  Items: $EOAPI_ITEMS_FILE"

if ! kubectl cp "$EOAPI_COLLECTIONS_FILE" "$FOUND_NAMESPACE/$EOAPI_POD_RASTER":/tmp/collections.json; then
    log_error "Failed to copy collections file"
    exit 1
fi

if ! kubectl cp "$EOAPI_ITEMS_FILE" "$FOUND_NAMESPACE/$EOAPI_POD_RASTER":/tmp/items.json; then
    log_error "Failed to copy items file"
    exit 1
fi

# Load collections and items
log_info "Loading collections..."
if ! kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- bash -c "pypgstac load collections /tmp/collections.json --dsn \"\$PGADMIN_URI\" --method insert_ignore"; then
    log_error "Failed to load collections"
    exit 1
fi
log_info "Collections loaded successfully"

log_info "Loading items..."
if ! kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- bash -c "pypgstac load items /tmp/items.json --dsn \"\$PGADMIN_URI\" --method insert_ignore"; then
    log_error "Failed to load items"
    exit 1
fi
log_info "Items loaded successfully"

# Clean temporary files
log_info "Cleaning temporary files..."
kubectl exec -n "$FOUND_NAMESPACE" "$EOAPI_POD_RASTER" -- bash -c 'rm -f /tmp/collections.json /tmp/items.json' || log_warn "Failed to clean temporary files"

log_info "✅ Ingestion completed successfully"
