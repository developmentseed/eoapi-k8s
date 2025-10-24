# eoAPI Kubernetes Scripts

Automation scripts for deploying, testing, and managing eoAPI on Kubernetes.

## Scripts Overview

| Script | Purpose | Usage |
|--------|---------|-------|
| **`deploy.sh`** | Deploy eoAPI to Kubernetes | `./deploy.sh [deploy\|setup\|cleanup] [--ci]` |
| **`ingest.sh`** | Ingest STAC data into deployed eoAPI | `./ingest.sh [collections.json] [items.json]` |
| **`test.sh`** | Run Helm, integration, and observability tests | `./test.sh [helm\|integration\|observability\|all] [--debug]` |
| **`lib/common.sh`** | Core utility functions and logging | Shared functions for all scripts |
| **`lib/observability.sh`** | Monitoring and autoscaling utilities | Functions for testing observability stack |

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

## Observability Testing

The test suite includes comprehensive observability validation:

**Monitoring Stack Tests:**
- Prometheus server deployment and metrics collection
- Grafana dashboard accessibility and data source connectivity
- Custom metrics API availability via prometheus-adapter
- HPA (Horizontal Pod Autoscaler) functionality with CPU metrics
- kube-state-metrics and node-exporter deployment

**Autoscaling Tests:**
- HPA configuration validation for STAC, Raster, and Vector services
- CPU-based scaling threshold verification
- Request-rate scaling metrics (when ingress metrics available)
- Scaling behavior and stabilization window testing

**Run observability tests:**
```bash
# Run only observability tests
./scripts/test.sh observability

# Run with enhanced monitoring output
./scripts/test.sh observability --debug

# Run all tests including observability
./scripts/test.sh all
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

**Run only observability tests:**
```bash
./scripts/test.sh observability --debug
```

**Test monitoring stack health:**
```bash
# Source observability functions
source ./scripts/lib/observability.sh

# Check individual components
check_prometheus_health
check_grafana_health
check_hpa_status

# Get comprehensive status
get_monitoring_stack_status
```

**Cleanup deployment:**
```bash
./scripts/deploy.sh cleanup
```

**CI mode deployment:**
```bash
./scripts/deploy.sh --ci
```
