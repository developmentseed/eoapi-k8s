# eoAPI Scripts

This directory contains the implementation scripts for the eoAPI CLI.

## Structure

```
scripts/
├── lib/
│   ├── common.sh    # Shared utilities (logging, validation)
│   └── k8s.sh       # Kubernetes helper functions
├── cluster.sh       # Cluster management (start, stop, clean, status, inspect)
├── deployment.sh    # Deployment operations (run, debug)
├── test.sh          # Test suites (schema, lint, unit, integration)
├── ingest.sh        # Data ingestion
└── docs.sh          # Documentation (generate, serve)
```

## Usage

All scripts are accessed through the main CLI:

```bash
./eoapi-cli <command> <subcommand> [options]

# Examples
./eoapi-cli cluster start
./eoapi-cli deployment run
./eoapi-cli test all
./eoapi-cli ingest collections.json items.json
./eoapi-cli docs serve
```

## CLI Reference

The eoAPI CLI provides a unified interface for all operations:

### Cluster Management
```bash
# Start local k3s cluster
./eoapi-cli cluster start

# Check cluster status
./eoapi-cli cluster status

# Stop cluster (preserves data)
./eoapi-cli cluster stop

# Clean up cluster and temporary files
./eoapi-cli cluster clean

# Detailed cluster diagnostics
./eoapi-cli cluster inspect
```

### Deployment Operations
```bash
# Deploy eoAPI
./eoapi-cli deployment run

# Debug deployment
./eoapi-cli deployment debug
```

### Testing
```bash
# Run all tests
./eoapi-cli test all

# Run specific test suites
./eoapi-cli test schema      # Validate Helm chart schema
./eoapi-cli test lint        # Run Helm lint
./eoapi-cli test unit        # Run Helm unit tests
./eoapi-cli test integration # Run integration tests
```

### Data Ingestion
```bash
# Ingest sample data
./eoapi-cli ingest <collections-file> <items-file>
```

### Documentation
```bash
# Generate documentation
./eoapi-cli docs generate

# Serve documentation locally
./eoapi-cli docs serve

# Check documentation
./eoapi-cli docs check
```

### Getting Help
```bash
# Show main help
./eoapi-cli --help

# Show command-specific help
./eoapi-cli cluster --help
./eoapi-cli deployment --help
./eoapi-cli test --help
```

## Integration testing

### With k3d (recommended)
```bash
# Complete workflow with k3d-managed cluster
./eoapi-cli cluster start           # Creates k3d cluster
./eoapi-cli deployment run          # Deploy eoAPI
./eoapi-cli test integration        # Run integration tests
./eoapi-cli cluster clean           # Cleanup
```

### With existing k3s/k8s cluster
```bash
# Ensure kubectl is configured for your cluster
./eoapi-cli deployment run          # Deploy eoAPI
./eoapi-cli test integration        # Run tests
```

Test options:
- `test all` - Run all test suites
- `test integration --pytest-args="-v"` - Pass pytest arguments

## Environment variables

- `NAMESPACE` - Kubernetes namespace (default: eoapi)
- `RELEASE_NAME` - Helm release name (default: eoapi)
- `DEBUG_MODE` - Enable debug output (set to true)
- `CLUSTER_NAME` - K3s cluster name (default: eoapi-local)

The scripts auto-detect CI environments through common environment variables (CI, GITHUB_ACTIONS, etc).
