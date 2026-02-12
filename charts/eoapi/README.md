# eoAPI Helm Chart

A Helm chart for deploying Earth Observation APIs with integrated STAC, raster, vector, and multidimensional services.

## Features

- STAC API for metadata discovery and search
- STAC Auth Proxy for authentication/authorization (optional)
- Raster tile services (TiTiler)
- Vector tile services (TIPG)
- Multidimensional data support
- Built-in STAC Browser interface
- Flexible database configuration
- Real-time PostgreSQL notifications for STAC item changes
- Unified ingress system
- Autoscaling
- Integrated observability (Prometheus & Grafana)

## TL;DR

```bash
# Add the eoAPI repository
helm repo add eoapi https://devseed.com/eoapi-k8s/

# Install the PostgreSQL operator (required)
helm install --set disable_check_for_upgrades=true pgo \
  oci://registry.developers.crunchydata.com/crunchydata/pgo \
  --version 5.8.6

# Install eoAPI with core profile (stable services only)
helm install eoapi eoapi/eoapi -f profiles/core.yaml

# Or install with all features for development
helm install eoapi eoapi/eoapi -f profiles/experimental.yaml
```

## Prerequisites

- Kubernetes 1.23+
- Helm 3.0+
- PV provisioner support
- PostgreSQL operator

## STAC Auth Proxy (Optional)

The chart includes support for [stac-auth-proxy](https://github.com/developmentseed/stac-auth-proxy) to add authentication and authorization to your STAC API. This feature is disabled by default and can be enabled, and will need a valid OIDC discovery URL.

### Configuration

```yaml
stac-auth-proxy:
  enabled: true
  env:
    OIDC_DISCOVERY_URL: "https://your-auth-server/.well-known/openid-configuration"
```

When enabled, the ingress will automatically route STAC API requests through the auth proxy instead of directly to the STAC service.

## Quick Start with Profiles

Use pre-configured profiles for common deployment scenarios:

```bash
# Production deployment with stable services only
helm install eoapi eoapi/eoapi -f profiles/core.yaml

# Development with all features enabled
helm install eoapi eoapi/eoapi -f profiles/experimental.yaml

# Local k3s development
helm install eoapi eoapi/eoapi \
  -f profiles/experimental.yaml \
  -f profiles/local/k3s.yaml

# Local minikube development
helm install eoapi eoapi/eoapi \
  -f profiles/experimental.yaml \
  -f profiles/local/minikube.yaml
```

See [profiles/README.md](./profiles/README.md) for detailed profile documentation.

## Manual Configuration

For custom deployments, configure values directly:

```yaml
# Enable desired services
apiServices:
  - raster
  - stac
  - vector
  - stac-browser
  # - multidim  # Optional

# Configure ingress
ingress:
  enabled: true
  className: "nginx"  # or "traefik"
  host: "your-domain.com"  # Optional

# Database options
postgresql:
  type: "postgrescluster"  # or "external-plaintext" or "external-secret"

# Load sample data
pgstacBootstrap:
  enabled: true
  settings:
    loadSamples: true
```

## Configuration Options

### Service Profile Presets

| Profile | Use Case | Services | Features |
|---------|----------|----------|----------|
| `profiles/core.yaml` | Production | STAC, Raster, Vector | Stable, optimized resources |
| `profiles/experimental.yaml` | Development/Testing | All services | Includes experimental features, monitoring |
| `profiles/local/k3s.yaml` | Local k3s | Inherits from experimental | k3s-specific settings |
| `profiles/local/minikube.yaml` | Local minikube | Inherits from experimental | Minikube-specific settings |

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.type` | Database deployment type | `postgrescluster` |
| `postgrescluster.enabled` | Enable PostgreSQL cluster. Must be set to `false` when using external databases | `true` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress controller class | `nginx` |
| `browser.enabled` | Enable STAC Browser interface | `true` |
| `pgstacBootstrap.enabled` | Enable database initialization | `true` |
| `notifications.sources.pgstac` | Enable PostgreSQL notification triggers for STAC item changes | `false` |

### Resource Configuration

This chart does not specify default resource limits/requests. Set resources based on your infrastructure and workload:

```yaml
# Example resource configuration in your values override
stac:
  settings:
    resources:
      requests:
        cpu: "1"
        memory: "2Gi"
      limits:
        cpu: "2"
        memory: "4Gi"

raster:
  settings:
    resources:
      requests:
        cpu: "2"
        memory: "4Gi"
      limits:
        cpu: "4"
        memory: "8Gi"
```

### Database Options

1. Integrated PostgreSQL Operator:
```yaml
postgresql:
  type: "postgrescluster"
```

2. External Database:
```yaml
postgresql:
  type: "external-plaintext"
  external:
    host: "your-db-host"
    port: "5432"
    database: "eoapi"
    credentials:
      username: "your-user"
      password: "your-password"
```

3. External Database with Secrets:
```yaml
postgresql:
  type: "external-secret"
  external:
    existingSecret:
      name: "your-secret"
```

## Documentation

For detailed configuration and usage:

- [Configuration Guide](https://github.com/developmentseed/eoapi-k8s/blob/main/docs/configuration.md)
- [Data Management](https://github.com/developmentseed/eoapi-k8s/blob/main/docs/manage-data.md)
- [Autoscaling Guide](https://github.com/developmentseed/eoapi-k8s/blob/main/docs/autoscaling.md)

## Template Structure

The Helm templates are organized into logical modules:

```
templates/
├── core/           # ServiceAccount, RBAC, Knative resources
├── database/       # PostgreSQL and pgstac bootstrap
├── networking/     # Ingress and middleware
├── monitoring/     # Prometheus and Grafana
├── services/       # API deployments (stac, raster, vector, multidim)
└── _helpers/       # Reusable template functions
```

Helper functions are organized by domain in `_helpers/`:
- `core.tpl` - Naming, labels, service account
- `database.tpl` - PostgreSQL configuration
- `services.tpl` - Service helpers and init containers
- `validation.tpl` - Chart validation
- `_resources.tpl` - Resource presets

## License

[MIT License](https://github.com/developmentseed/eoapi-k8s/blob/main/LICENSE)
