# eoAPI Helm Chart Profiles

This directory contains pre-configured values profiles for common eoAPI deployment scenarios. These profiles simplify deployment by providing sensible defaults for different use cases.

## Overview

Profiles are pre-configured values files that override the default `values.yaml` settings. They help you quickly deploy eoAPI for different scenarios without manually configuring dozens of parameters.

## Available Profiles

### Core Profile (`core.yaml`)
**Use Case:** Minimal production deployment with stable services only.

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
- Autoscaling

**Resources:** Production-optimized with higher resource allocations.

### Production Profile (`production.yaml`)
**Use Case:** Full production deployment with autoscaling and observability.

**Includes:**
- All core services
- High availability PostgreSQL (2 replicas)
- Autoscaling for all API services
- Complete monitoring stack (Prometheus)
- Grafana dashboards for observability
- STAC Browser UI
- Custom metrics for request-rate scaling

**Configuration:**
- Autoscaling enabled (CPU and request-rate based)
- Persistent storage for metrics (30 days retention)
- Production-optimized resource allocations
- TLS enabled by default

**Resources:** High resource allocations optimized for production workloads.

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
# Minimal production deployment
helm install eoapi ./charts/eoapi -f profiles/core.yaml

# Full production with autoscaling and observability
helm install eoapi ./charts/eoapi -f profiles/production.yaml

# Development deployment with all experimental features
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
