# eoAPI Helm Chart

![Version: 0.7.5](https://img.shields.io/badge/Version-0.7.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 5.0.2](https://img.shields.io/badge/AppVersion-5.0.2-informational?style=flat-square)

A Helm chart for deploying Earth Observation APIs with integrated STAC, raster, vector, and multidimensional services.

## Features

- STAC API for metadata discovery and search
- Raster tile services (TiTiler)
- Vector tile services (TIPG)
- Multidimensional data support
- Built-in STAC Browser interface
- Flexible database configuration
- Unified ingress system

## TL;DR

```bash
# Add the eoAPI repository
helm repo add eoapi https://devseed.com/eoapi-k8s/

# Install the PostgreSQL operator (required)
helm install --set disable_check_for_upgrades=true pgo \
  oci://registry.developers.crunchydata.com/crunchydata/pgo \
  --version 5.7.4

# Install eoAPI
helm install eoapi eoapi/eoapi
```

## Prerequisites

- Kubernetes 1.23+
- Helm 3.0+
- PV provisioner support
- PostgreSQL operator

## Quick Start Configuration

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

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.type` | Database deployment type | `postgrescluster` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress controller class | `nginx` |
| `browser.enabled` | Enable STAC Browser interface | `true` |
| `pgstacBootstrap.enabled` | Enable database initialization | `true` |

Refer to the [values.schema.json](./values.schema.json) for the complete list of configurable parameters.

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

## License

[MIT License](https://github.com/developmentseed/eoapi-k8s/blob/main/LICENSE)
