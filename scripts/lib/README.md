# eoAPI Scripts - Modular Libraries

## Core Modules

- **`common.sh`** - Logging, utilities, detection functions
- **`validation.sh`** - Tool and environment validation
- **`args.sh`** - Standardized argument parsing
- **`deploy-core.sh`** - Deployment operations
- **`cleanup.sh`** - Resource cleanup
- **`cluster-minikube.sh`** - Minikube cluster management
- **`cluster-k3s.sh`** - k3s cluster management

## Usage

Libraries auto-source dependencies. Main scripts simply source what they need:

```bash
source "$SCRIPT_DIR/lib/args.sh"        # includes common.sh
source "$SCRIPT_DIR/lib/deploy-core.sh" # includes validation.sh
```

## Key Functions

**Common**: `log_*`, `command_exists`, `detect_namespace`, `detect_release_name`
**Validation**: `validate_deploy_tools`, `validate_cluster_connection`
**Args**: `parse_common_args`, `parse_cluster_args`
**Deploy**: `deploy_eoapi`, `setup_namespace`, `install_pgo`
**Cleanup**: `cleanup_deployment`, `cleanup_helm_release`

All functions include error handling and debug logging. Use `--help` on any script for full details.
