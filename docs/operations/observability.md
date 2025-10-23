 # Observability & Monitoring

This guide covers metrics collection, monitoring, and visualization for eoAPI deployments. All monitoring components are optional and disabled by default.

## Overview

eoAPI observability is implemented through conditional dependencies in the main `eoapi` chart:

### Core Monitoring
Essential metrics collection infrastructure including Prometheus server, metrics-server, kube-state-metrics, node-exporter, and prometheus-adapter.

### Integrated Observability
Grafana dashboards and visualization tools are available as conditional dependencies within the main chart, eliminating the need for separate deployments.

## Configuration

**Prerequisites**: Kubernetes cluster with Helm 3 installed.

### Quick Deployment

```bash
# Deploy with monitoring and observability enabled
helm install eoapi eoapi/eoapi \
  --set monitoring.prometheus.enabled=true \
  --set observability.grafana.enabled=true

# Access Grafana (get password)
kubectl get secret eoapi-grafana -n eoapi \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

### Using Configuration Files

For production deployments, use configuration files instead of command-line flags:

```bash
# Deploy with integrated monitoring and observability
helm install eoapi eoapi/eoapi -f values-full-observability.yaml
```

**For a complete example**: See [examples/values-full-observability.yaml](../examples/values-full-observability.yaml)

## Architecture & Components

**Component Responsibilities:**

- **Prometheus Server**: Central metrics storage and querying engine
- **metrics-server**: Provides resource metrics for `kubectl top` and HPA
- **kube-state-metrics**: Exposes Kubernetes object state as metrics
- **prometheus-node-exporter**: Collects hardware and OS metrics from nodes
- **prometheus-adapter**: Enables custom metrics for Horizontal Pod Autoscaler
- **Grafana**: Dashboards and visualization of collected metrics

**Data Flow**: Exporters expose metrics → Prometheus scrapes and stores → Grafana/kubectl query via PromQL → Dashboards visualize data

### Detailed Configuration

#### Basic Monitoring Setup

```yaml
# values.yaml - Enable core monitoring in main eoapi chart
monitoring:
  metricsServer:
    enabled: true
  prometheus:
    enabled: true
    server:
      persistentVolume:
        enabled: true
        size: 50Gi
      retention: "30d"
    kube-state-metrics:
      enabled: true
    prometheus-node-exporter:
      enabled: true
```

#### Observability Chart Configuration

```yaml
# Basic Grafana setup
grafana:
  enabled: true
  service:
    type: LoadBalancer

# Connect to external Prometheus (if not using eoapi's Prometheus)
prometheusUrl: "http://prometheus.monitoring.svc.cluster.local"

# Production Grafana configuration
grafana:
  persistence:
    enabled: true
    size: 10Gi
  resources:
    limits:
      cpu: 200m
      memory: 400Mi
    requests:
      cpu: 50m
      memory: 200Mi
```

#### PostgreSQL Monitoring

Enable PostgreSQL metrics collection:

```yaml
postgrescluster:
  monitoring: true  # Enables postgres_exporter sidecar
```

## Available Metrics

### Core Infrastructure Metrics
- **Container resources**: CPU, memory, network usage
- **Kubernetes state**: Pods, services, deployments status
- **Node metrics**: Hardware utilization, filesystem usage
- **PostgreSQL**: Database connections, query performance (when enabled)

### Custom Application Metrics

When prometheus-adapter and nginx ingress are both enabled, these custom metrics become available:
- `nginx_ingress_controller_requests_rate_stac_eoapi`
- `nginx_ingress_controller_requests_rate_raster_eoapi`
- `nginx_ingress_controller_requests_rate_vector_eoapi`
- `nginx_ingress_controller_requests_rate_multidim_eoapi`

**Requirements**:
- nginx ingress controller with prometheus metrics enabled
- Ingress must use specific hostnames (not wildcard patterns)
- prometheus-adapter must be configured to expose these metrics

## Pre-built Dashboards

The `eoapi-observability` chart provides ready-to-use dashboards:

### eoAPI Services Dashboard
- Request rates per service
- Response times and error rates
- Traffic patterns by endpoint

### Infrastructure Dashboard
- CPU usage rate by pod
- CPU throttling metrics
- Memory usage and limits
- Pod count tracking

### Container Resources Dashboard
- Resource consumption by container
- Resource quotas and limits
- Performance bottlenecks

### PostgreSQL Dashboard (when enabled)
- Database connections
- Query performance
- Storage utilization

#### Production Configuration

```yaml
monitoring:
  prometheus:
    server:
      # Persistent storage
      persistentVolume:
        enabled: true
        size: 100Gi
        storageClass: "gp3"
      # Retention policy
      retention: "30d"
      # Resource allocation
      resources:
        limits:
          cpu: "2000m"
          memory: "4096Mi"
        requests:
          cpu: "1000m"
          memory: "2048Mi"
      # Security - internal access only
      service:
        type: ClusterIP
```

### Resource Requirements

#### Core Monitoring Components

Minimum resource requirements (actual usage varies by cluster size and metrics volume):

| Component | CPU | Memory | Purpose |
|-----------|-----|---------|----------|
| prometheus-server | 500m | 1Gi | Metrics storage |
| metrics-server | 100m | 200Mi | Resource metrics |
| kube-state-metrics | 50m | 150Mi | K8s state |
| prometheus-node-exporter | 50m | 50Mi | Node metrics |
| prometheus-adapter | 100m | 128Mi | Custom metrics API |
| **Total** | **~800m** | **~1.5Gi** | |

#### Observability Components

| Component | CPU | Memory | Purpose |
|-----------|-----|---------|----------|
| grafana | 100m | 200Mi | Visualization |

## Operations

### Verification Commands

```bash
# Check Prometheus is running
kubectl get pods -n eoapi -l app.kubernetes.io/name=prometheus

# Verify metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io

# List available custom metrics
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq '.resources[].name'

# Test metrics collection
kubectl port-forward svc/eoapi-prometheus-server 9090:80 -n eoapi
# Visit http://localhost:9090/targets
```

### Monitoring Health

```bash
# Check Prometheus targets
curl -X GET 'http://localhost:9090/api/v1/query?query=up'

# Verify Grafana datasource connectivity
kubectl exec -it deployment/eoapi-obs-grafana -n eoapi -- \
  wget -O- http://eoapi-prometheus-server/api/v1/label/__name__/values
```

## Advanced Features

### Alerting Setup

Enable alertmanager for alert management:

```yaml
prometheus:
  enabled: true
  alertmanager:
    enabled: true
    config:
      global:
        # Configure with your SMTP server details
        smtp_smarthost: 'your-smtp-server:587'
        smtp_from: 'alertmanager@yourdomain.com'
      route:
        receiver: 'default-receiver'
      receivers:
      - name: 'default-receiver'
        webhook_configs:
        - url: 'http://your-webhook-endpoint:5001/'
```

**Note**: Replace example values with your actual SMTP server and webhook endpoints.

### Batch Job Metrics

Enable pushgateway for batch job metrics:

```yaml
prometheus:
  enabled: true
  prometheus-pushgateway:
    enabled: true  # For batch job metrics collection
```

### Custom Dashboards

Add custom dashboards by creating ConfigMaps with the appropriate label:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-dashboard
  namespace: eoapi
  labels:
    eoapi_dashboard: "1"
data:
  custom.json: |
    {
      "dashboard": {
        "id": null,
        "title": "Custom eoAPI Dashboard",
        "tags": ["eoapi"],
        "panels": []
      }
    }
```

The ConfigMap must be in the same namespace as the Grafana deployment and include the `eoapi_dashboard: "1"` label.

## Troubleshooting

### Common Issues

**Missing Metrics**
1. Check Prometheus service discovery:
   ```bash
   kubectl port-forward svc/eoapi-prometheus-server 9090:80 -n eoapi
   # Visit http://localhost:9090/service-discovery
   ```

2. Verify target endpoints:
   ```bash
   kubectl get endpoints -n eoapi
   ```

**Grafana Connection Issues**
1. Check datasource connectivity in Grafana UI → Configuration → Data Sources
2. Verify Prometheus URL accessibility from Grafana pod

**Resource Issues**
- Monitor current usage: `kubectl top pods -n eoapi`
- Check for OOMKilled containers: `kubectl describe pods -n eoapi | grep -A 5 "Last State"`
- Verify resource limits are appropriate for your workload size
- Consider increasing Prometheus retention settings if storage is full

## Security Considerations

- **Network Security**: Use `ClusterIP` services for Prometheus in production
- **Access Control**: Configure network policies to restrict metrics access
- **Authentication**: Enable authentication for Grafana (LDAP, OAuth, etc.)
- **Data Privacy**: Consider metrics data sensitivity and retention policies

## Related Documentation

- For autoscaling configuration using these metrics: [autoscaling.md](autoscaling.md)
