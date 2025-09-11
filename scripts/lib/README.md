# eoAPI Scripts - Shared Utilities

This directory contains shared utility functions used across eoAPI deployment, testing, and ingestion scripts.

## Usage

Source the common utilities in your scripts:

```bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/lib/common.sh"
```

## Available Functions

### Logging
- `log_info "message"` - Info messages (green)
- `log_warn "message"` - Warning messages (yellow)
- `log_error "message"` - Error messages (red)
- `log_debug "message"` - Debug messages (blue)

### Validation
- `command_exists "tool"` - Check if command is available
- `validate_tools tool1 tool2 ...` - Validate required tools exist
- `validate_cluster` - Check Kubernetes cluster connectivity
- `validate_namespace "namespace"` - Check if namespace exists
- `validate_eoapi_deployment "namespace" "release"` - Validate eoAPI deployment

### Detection
- `is_ci_environment` - Returns true if running in CI
- `detect_release_name ["namespace"]` - Auto-detect eoAPI release name
- `detect_namespace` - Auto-detect eoAPI namespace

### Utilities
- `wait_for_pods "namespace" "selector" ["timeout"]` - Wait for pods to be ready

### Pre-flight Checks
- `preflight_deploy` - Validate deployment prerequisites
- `preflight_ingest "namespace" "collections_file" "items_file"` - Validate ingestion prerequisites
- `preflight_test "helm|integration"` - Validate test prerequisites

## Error Handling

All functions use proper error handling with `set -euo pipefail`. Scripts automatically exit on errors with descriptive messages.

## Example

```bash
#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

# Validate prerequisites
preflight_deploy || exit 1

# Use utilities
NAMESPACE=$(detect_namespace)
RELEASE=$(detect_release_name "$NAMESPACE")

log_info "Deploying $RELEASE to $NAMESPACE"
validate_eoapi_deployment "$NAMESPACE" "$RELEASE"
```
