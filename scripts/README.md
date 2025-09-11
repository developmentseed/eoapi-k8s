# eoAPI Kubernetes Scripts

Automation scripts for deploying, testing, and managing eoAPI on Kubernetes.

## Scripts Overview

| Script | Purpose | Usage |
|--------|---------|-------|
| **`deploy.sh`** | Deploy eoAPI to Kubernetes | `./deploy.sh [deploy\|setup\|cleanup] [--ci]` |
| **`ingest.sh`** | Ingest STAC data into deployed eoAPI | `./ingest.sh [collections.json] [items.json]` |
| **`test.sh`** | Run Helm and integration tests | `./test.sh [helm\|integration\|all] [--debug]` |
| **`lib/`** | Shared utility functions | See [lib/README.md](lib/README.md) |

## Quick Start

```bash
# Deploy eoAPI
./scripts/deploy.sh

# Ingest sample data
./scripts/ingest.sh collections.json items.json

# Run tests
./scripts/test.sh
```

## Prerequisites

- **kubectl** - Kubernetes CLI configured for your cluster
- **helm** - Helm package manager v3+
- **python3** - For data ingestion and testing
- **jq** - JSON processor (for advanced features)

## Environment Variables (Optional)

Most settings are auto-detected. Override only when needed:

```bash
# Deployment customization
export PGO_VERSION=5.7.4           # PostgreSQL operator version
export TIMEOUT=15m                  # Deployment timeout

# Override auto-detection (usually not needed)
export NAMESPACE=my-eoapi           # Target namespace  
export RELEASE_NAME=my-release      # Helm release name

# Testing endpoints (auto-detected by test.sh)
export STAC_ENDPOINT=http://...     # Override STAC API endpoint
export RASTER_ENDPOINT=http://...   # Override Raster API endpoint  
export VECTOR_ENDPOINT=http://...   # Override Vector API endpoint
```

## Common Examples

**Deploy with custom namespace:**
```bash
NAMESPACE=my-eoapi ./scripts/deploy.sh
```

**Setup dependencies only:**
```bash
./scripts/deploy.sh setup
```

**Run tests with debug output:**
```bash
./scripts/test.sh all --debug
```

**Cleanup deployment:**
```bash
./scripts/deploy.sh cleanup
```

**CI mode deployment:**
```bash
./scripts/deploy.sh --ci
```
