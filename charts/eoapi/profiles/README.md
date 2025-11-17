# eoAPI Helm Chart Profiles

This directory contains pre-configured values profiles for common eoAPI deployment scenarios. These profiles simplify deployment by providing sensible defaults for different use cases.

## Overview

Profiles are pre-configured values files that override the default `values.yaml` settings. They help you quickly deploy eoAPI for different scenarios without manually configuring dozens of parameters.

## Available Profiles

### Core Profile (`core.yaml`)
**Use Case:** Production deployments with stable, well-tested services only.

**Includes:**
- PostgreSQL with PgSTAC
- STAC API
- Raster service (TiTiler)
- Vector service (TiPG)
- Documentation server

**Excludes:**
- Experimental features
- Development tools
- Monitoring stack
- STAC Browser UI

**Resources:** Production-optimized with higher resource allocations.

### Experimental Profile (`experimental.yaml`)
**Use Case:** Development, testing, and evaluation of all eoAPI features.

**Includes:**
- All core services
- Multidimensional service
- STAC Browser UI
- Notification system (eoapi-notifier)
- Knative integration for CloudEvents
- Complete monitoring stack (Prometheus, Grafana)
- Sample data loading
- Debug modes enabled

**Resources:** Balanced for development environments.

### Local Profiles

#### k3s Profile (`local/k3s.yaml`)
**Use Case:** Local development on k3s clusters.

**Requirements:** Must be used together with `experimental.yaml`

**Overrides:**
- Traefik ingress configuration
- Reduced PostgreSQL resources (1Gi storage, minimal CPU/memory)
- Disabled metrics-server (k3s provides built-in)

#### Minikube Profile (`local/minikube.yaml`)
**Use Case:** Local development on Minikube.

**Requirements:** Must be used together with `experimental.yaml`

**Overrides:**
- Nginx ingress configuration with regex support
- Reduced PostgreSQL resources (1Gi storage, minimal CPU/memory)
- Enabled metrics-server

## Usage

### Basic Usage

Deploy with a single profile:
```bash
# Production deployment with core services only
helm install eoapi ./charts/eoapi -f profiles/core.yaml

# Development deployment with all features
helm install eoapi ./charts/eoapi -f profiles/experimental.yaml
```

### Layered Profiles

Combine profiles for specific environments:
```bash
# k3s local development
helm install eoapi ./charts/eoapi \
  -f profiles/experimental.yaml \
  -f profiles/local/k3s.yaml

# Minikube local development
helm install eoapi ./charts/eoapi \
  -f profiles/experimental.yaml \
  -f profiles/local/minikube.yaml
```

### Custom Overrides

Add your own overrides on top of profiles:
```bash
# Use core profile with custom domain
helm install eoapi ./charts/eoapi \
  -f profiles/core.yaml \
  --set ingress.host=api.example.com

# Use experimental profile with external database
helm install eoapi ./charts/eoapi \
  -f profiles/experimental.yaml \
  -f my-custom-values.yaml
```
