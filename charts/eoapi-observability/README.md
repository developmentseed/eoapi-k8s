# eoAPI Observability

Observability and dashboarding tools for eoAPI monitoring.

This chart provides Grafana dashboards and observability tools for monitoring eoAPI deployments. It connects to the Prometheus instance deployed by the main `eoapi` chart.

## Documentation

Refer to the docs for full documentation about setup and configuration:

- [Observability tooling](../../docs/observability.md)
- [Autoscaling](../../docs/autoscaling.md)

## Prerequisites

The main `eoapi` chart must be deployed with monitoring enabled:

```yaml
monitoring:
  prometheus:
    enabled: true
```

## Installation

```bash
# Install main eoapi chart first (if not already installed)
helm install eoapi eoapi/eoapi \
  --set monitoring.prometheus.enabled=true \
  --namespace eoapi --create-namespace

# Then install observability tools
helm install eoapi-obs eoapi/eoapi-observability --namespace eoapi
```

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana.enabled` | Enable Grafana deployment | `true` |
| `prometheusUrl` | Prometheus server URL | Auto-detected |
| `grafana.service.type` | Grafana service type | `LoadBalancer` |
| `grafana.persistence.enabled` | Enable data persistence | `false` |


### Enable Additional Features

```yaml
prometheus:
  enabled: true
  alertmanager:
    enabled: true
  prometheus-pushgateway:
    enabled: true
```

## Dashboards

Pre-built dashboards include:
- eoAPI service metrics (request rates, response times, errors)
- Container resources (CPU, memory, throttling)
- Infrastructure monitoring (nodes, pods)
- PostgreSQL metrics (when enabled)

## Access Grafana

```bash
# Get service endpoint
kubectl get svc eoapi-obs-grafana -n eoapi

# Get admin password
kubectl get secret eoapi-obs-grafana -n eoapi \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

Default credentials: `admin` / `admin` (change on first login)
