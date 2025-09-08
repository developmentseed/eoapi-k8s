# Autoscaling

Horizontal Pod Autoscaler (HPA) configuration for eoAPI services. Autoscaling requires monitoring components to be enabled in the main chart.

## Prerequisites

Enable monitoring in your main eoapi installation:

```yaml
monitoring:
  prometheus:
    enabled: true
  prometheusAdapter:
    enabled: true  # Required for request-rate scaling
  metricsServer:
    enabled: true   # Required for CPU scaling
```

## Configuration

### Basic Autoscaling

```yaml
stac:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 20
    type: "requestRate"  # Options: "cpu", "requestRate", "both"
    targets:
      requestRate: 50000m  # 50 requests/second
```

### Scaling Policies

```yaml
stac:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 20
    type: "both"
    behaviour:
      scaleDown:
        stabilizationWindowSeconds: 300  # 5min cooldown
        policies:
        - type: Percent
          value: 50      # Max 50% pods removed per period
          periodSeconds: 300
      scaleUp:
        stabilizationWindowSeconds: 60   # 1min cooldown
        policies:
        - type: Percent
          value: 100     # Max 100% pods added per period
          periodSeconds: 60
    targets:
      cpu: 70
      requestRate: 50000m
```

## Metrics Types

### CPU-based Scaling
```yaml
type: "cpu"
targets:
  cpu: 75  # Scale when average CPU > 75%
```

### Request Rate Scaling
```yaml
type: "requestRate"
targets:
  requestRate: 50000m  # Scale when average > 50 requests/second
```
*Note: Uses nginx ingress controller metrics. Requires specific hostname (not wildcard) in ingress configuration.*

### Combined Scaling
```yaml
type: "both"
targets:
  cpu: 70
  requestRate: 100000m  # Scales on either metric
```

## Custom Metrics Configuration

When `monitoring.prometheusAdapter.enabled=true`, these custom metrics are auto-configured:

- `nginx_ingress_controller_requests_rate_stac_eoapi`
- `nginx_ingress_controller_requests_rate_raster_eoapi`
- `nginx_ingress_controller_requests_rate_vector_eoapi`
- `nginx_ingress_controller_requests_rate_multidim_eoapi`

**Requirements**:
- nginx ingress controller must be deployed
- Ingress must have specific hostname (not wildcard) for proper metric labeling
- Prometheus must be scraping nginx controller metrics

**Configuration**:
```yaml
# Ingress with specific hostname (required)
ingress:
  host: "eoapi.example.com"  # Not "*.example.com"

# Enable prometheus-adapter for custom metrics API
monitoring:
  prometheusAdapter:
    enabled: true
    resources:
      limits:
        cpu: 250m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi
```

## Service-Specific Examples

### STAC (High throughput)
```yaml
stac:
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 30
    type: "requestRate"
    targets:
      requestRate: 40000m
```

### Raster (Resource intensive)
```yaml
raster:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 15
    type: "cpu"
    behaviour:
      scaleDown:
        stabilizationWindowSeconds: 900  # Slower scale-down
    targets:
      cpu: 60  # Lower threshold due to processing intensity
```

### Vector (Balanced)
```yaml
vector:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 12
    type: "both"
    targets:
      cpu: 75
      requestRate: 75000m
```

## Configuration Examples

- **Basic autoscaling**: [examples/values-autoscaling.yaml](examples/values-autoscaling.yaml)
- **Production setup**: [examples/values-full-observability.yaml](examples/values-full-observability.yaml)

## Resource Requirements

### Autoscaling Components
```yaml
# Core components for autoscaling functionality
metrics-server:      # 100m CPU, 200Mi memory
prometheus-adapter:  # 100m CPU, 128Mi memory (if enabled)
prometheus-server:   # 500m CPU, 1Gi memory (for custom metrics)

# Total autoscaling overhead: ~700m CPU, ~1.3Gi memory
```

## Verification

### Check HPA Status
```bash
# List all HPAs
kubectl get hpa -n eoapi

# Watch scaling events in real-time
kubectl get hpa -n eoapi -w

# Detailed HPA information
kubectl describe hpa stac-hpa -n eoapi
```

### Verify Custom Metrics API
```bash
# Check custom metrics API is available
kubectl get apiservice v1beta1.custom.metrics.k8s.io

# List all available custom metrics
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq '.resources[].name'

# Test specific service metric
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/eoapi/services/stac/nginx_ingress_controller_requests_rate_stac_eoapi"
```

### Check Prometheus Adapter
```bash
# Check prometheus-adapter logs
kubectl logs -l app.kubernetes.io/name=prometheus-adapter -n eoapi

# Verify adapter configuration
kubectl get configmap prometheus-adapter -n eoapi -o yaml
```

## Load Testing

For request-rate scaling to work, your ingress needs a specific hostname:

```yaml
ingress:
  host: "eoapi.example.com"  # Not "*.example.com"
```

Simple load test:
```bash
# Generate load to trigger scaling
kubectl run load-test --rm -i --tty --image=busybox --restart=Never -- \
  /bin/sh -c 'while true; do wget -q -O- http://eoapi.example.com/stac; done'
```

## Troubleshooting

### HPA Shows "Unknown" Metrics
1. Check prometheus-adapter status:
   ```bash
   kubectl logs -l app.kubernetes.io/name=prometheus-adapter -n eoapi
   kubectl get apiservice v1beta1.custom.metrics.k8s.io
   ```

2. Verify Prometheus is collecting the required metrics:
   ```bash
   kubectl port-forward svc/eoapi-prometheus-server 9090:80 -n eoapi
   # Visit http://localhost:9090 and query: nginx_ingress_controller_requests
   ```

3. Check ingress configuration:
   ```bash
   kubectl get ingress -n eoapi -o yaml | grep -A5 -B5 "host:"
   # Must show specific hostname, not wildcard
   ```

### No Scaling Activity
1. Verify target metrics are available and have values:
   ```bash
   kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/eoapi/services/stac/nginx_ingress_controller_requests_rate_stac_eoapi"
   ```

2. Check current vs target values in HPA status:
   ```bash
   kubectl describe hpa stac-hpa -n eoapi
   # Look for "current: <unknown>" or values below/above targets
   ```

3. Verify pod resource requests are set (required for CPU-based scaling):
   ```bash
   kubectl get pods -n eoapi -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources.requests}{"\n"}{end}'
   ```

4. Check scaling policies and stabilization windows:
   ```bash
   kubectl get hpa stac-hpa -n eoapi -o jsonpath='{.spec.behavior}'
   ```

### Custom Metrics Not Working
1. Ensure nginx ingress controller is deployed and configured:
   ```bash
   kubectl get pods -n ingress-nginx
   kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
   ```

2. Verify Prometheus is scraping nginx metrics:
   ```bash
   # Port-forward to Prometheus and check targets
   kubectl port-forward svc/eoapi-prometheus-server 9090:80 -n eoapi
   # Visit http://localhost:9090/targets - look for nginx-ingress targets
   ```

3. Check ingress hostname configuration - must be specific, not wildcard

### Scaling Too Aggressive/Slow
Adjust `behaviour.scaleUp/scaleDown` policies and `stabilizationWindowSeconds` values based on your traffic patterns.

## Best Practices

- **Start conservative**: Low `maxReplicas`, longer `stabilizationWindowSeconds`
- **Monitor resource usage**: Adjust CPU/memory requests based on actual usage
- **Test scaling policies**: Use load testing to validate scaling behavior
- **Set appropriate minimums**: Ensure `minReplicas` provides sufficient baseline capacity
- **Consider service dependencies**: Database connections, external API limits

For monitoring and observability setup, see [observability.md](observability.md).
