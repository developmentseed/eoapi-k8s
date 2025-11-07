# Scripts

Automation scripts for eoAPI Kubernetes deployment and testing.

## Core Scripts

| Script | Purpose | Commands |
|--------|---------|----------|
| **`deploy.sh`** | Deploy/setup/cleanup eoAPI | `deploy`, `setup`, `cleanup`, `status`, `info` |
| **`test.sh`** | Run Helm and integration tests | `helm`, `integration`, `all` |
| **`local-cluster.sh`** | Manage local clusters (minikube/k3s) | `create`, `start`, `stop`, `delete`, `status`, `deploy` |
| **`ingest.sh`** | Ingest STAC data | (legacy) |

## Quick Usage

```bash
# Deploy to current cluster
./scripts/deploy.sh deploy

# Local development
make local-deploy                # create cluster and deploy
make local ACTION=create CLUSTER_TYPE=k3s  # or use k3s
make test                        # run all tests

# Individual operations
./scripts/deploy.sh setup       # setup only
./scripts/local-cluster.sh create --type minikube
./scripts/test.sh integration
```

## Prerequisites

- `kubectl`, `helm` (v3.15+), `python3`, `jq`
- **Local clusters**: `minikube` or `k3d` (for k3s)

## Configuration

All scripts support `--help` for detailed options. Common patterns:

```bash
# Use custom namespace/release
./scripts/deploy.sh deploy --namespace prod --release myapp

# Local cluster with k3s
make local-deploy CLUSTER_TYPE=k3s

# Debug mode
./scripts/deploy.sh deploy --debug
```

All settings have sensible defaults and most are auto-detected.
