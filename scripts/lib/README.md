# eoAPI Scripts - Shared Utilities

Shared utility functions for eoAPI deployment, testing, and ingestion scripts.

## Usage

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
```

## Functions

### Argument Parsing

`parse_standard_options "$@"` - Parses standard options and sets:
- `DEBUG_MODE` - Debug output enabled (-d/--debug)
- `NAMESPACE` - Kubernetes namespace (-n/--namespace)
- `REMAINING_ARGS` - Array of non-option arguments

### Logging

- `log_info` - Information messages (blue)
- `log_success` - Success messages (green)
- `log_warn` - Warning messages (yellow)
- `log_error` - Error messages (red, stderr)
- `log_debug` - Debug messages (shown when DEBUG_MODE=true or in CI)

### Validation

- `check_requirements tool1 tool2...` - Verify required tools are installed
- `validate_cluster` - Check kubectl connectivity
- `validate_namespace "namespace"` - Verify namespace exists
- `validate_eoapi_deployment "namespace" "release"` - Validate deployment health

### Detection

- `is_ci` - Returns true if running in CI environment
- `detect_release_name ["namespace"]` - Auto-detect eoAPI release name
- `detect_namespace` - Auto-detect eoAPI namespace from deployed resources

### Pre-flight Checks

- `preflight_deploy` - Validate deployment prerequisites
- `preflight_ingest "namespace" "collections" "items"` - Validate ingestion inputs
- `preflight_test "helm|integration"` - Validate test prerequisites

### Utilities

- `wait_for_pods "namespace" "selector" ["timeout"]` - Wait for pod readiness
- `command_exists "cmd"` - Check if command is available

## Error Handling

Scripts use `set -euo pipefail` and trap EXIT for cleanup. CI environments automatically enable debug mode.
