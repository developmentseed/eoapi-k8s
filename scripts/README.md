# Scripts

Automation scripts for eoAPI Kubernetes deployment and testing.

## Core Scripts

| Script | Purpose |
|--------|---------|
| **`deploy.sh`** | Deploy/setup/cleanup eoAPI |
| **`test.sh`** | Run Helm and integration tests |
| **`local-cluster.sh`** | Manage local clusters (minikube/k3s) |
| **`ingest.sh`** | Ingest STAC data |

## Quick Usage

```bash
# Deploy to current cluster
./scripts/deploy.sh

# Local development
make local                       # uses minikube by default
make local CLUSTER_TYPE=k3s      # or use k3s
make test-local                  # uses minikube by default
make test-local CLUSTER_TYPE=k3s # or use k3s

# Run tests
./scripts/test.sh integration
```

## Prerequisites

- `kubectl`, `helm` (v3.15+), `python3`, `jq`
- **Local testing**: `k3d` or `minikube`

## Environment Variables

Most settings auto-detected. Override when needed:

```bash
NAMESPACE=custom ./scripts/deploy.sh
CLUSTER_TYPE=k3s make local      # override to use k3s
```

See individual script `--help` for details.
