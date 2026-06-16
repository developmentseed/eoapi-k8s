---
title: "Autoscaling"
description: "Horizontal Pod Autoscaler (HPA) configuration for eoAPI services."
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Kubernetes HPA Documentation"
    url: "https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/"
---

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

The following instructions assume you've gone through the [AWS](./aws-eks.md) or [GCP](./gcp-gke.md) cluster set up
and installed the `eoapi` chart.

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

## Concurrency settings

Each main eoAPI service has `WEB_CONCURRENCY` and database pool settings that should be adjusted based on your scaling strategy:

### Without autoscaling (default)

Higher concurrency per pod to handle some considerate load:

```yaml
stac:
  settings:
    envVars:
      WEB_CONCURRENCY: "10"  # More workers per pod
      DB_MIN_CONN_SIZE: "1"
      DB_MAX_CONN_SIZE: "5"  # Total: 10-50 connections per pod
```

### With autoscaling enabled

Lower concurrency for predictable resource usage:

```yaml
stac:
  autoscaling:
    enabled: true
  settings:
    envVars:
      WEB_CONCURRENCY: "4"   # Fewer workers, let HPA scale pods
      DB_MIN_CONN_SIZE: "1"
      DB_MAX_CONN_SIZE: "3"  # Total: 4-12 connections per pod
```

### Service-specific recommentations

| Service | WEB_CONCURRENCY (no autoscaling) | WEB_CONCURRENCY (with autoscaling) | Rationale |
|---------|----------------------------------|-------------------------------------|-----------|
| STAC    | 10                               | 4-6                                 | High request volume, DB intensive |
| Raster  | 4                                | 2-3                                 | CPU intensive image operations |
| Vector  | 8                                | 4-5                                 | Complex spatial queries |

> These numbers assume each eoAPI deployment owns its database (the default
> `postgrescluster.enabled: true` mode). They are **not** safe defaults when several services share a
> single external PostgreSQL — read [External / shared PostgreSQL](#external--shared-postgresql)
> before enabling autoscaling against a shared database.

## External / shared PostgreSQL

With `postgrescluster.enabled: false` and an external database (`postgresql.type: external-plaintext`
or `external-secret`), the chart no longer provisions or sizes the database. That database is often
shared — by several eoAPI services and by other services that use the same PostgreSQL — and they all
compete for one fixed `max_connections`.

Autoscaling sharpens this: with HPA the connection count is bounded by `maxReplicas`, not by your
steady-state replica count, so a traffic spike can scale every service to its ceiling and exhaust
`max_connections` at once.

> **Warning:** On a shared external database with HPA enabled you **must** set explicit
> `WEB_CONCURRENCY` and `DB_MAX_CONN_SIZE` caps for every autoscaled service. The chart defaults are
> tuned for a dedicated, chart-managed database and can open hundreds of connections at the ceiling.

### Connection arithmetic

Each service runs `WEB_CONCURRENCY` uvicorn workers per pod, and each worker opens a pool of up to
`DB_MAX_CONN_SIZE` connections. The worst-case connections one service can open is:

```
max_connections(service) = maxReplicas × WEB_CONCURRENCY × pools × DB_MAX_CONN_SIZE
```

- `pools` is `1` for `raster`, `vector`, and `multidim`.
- `pools` is `2` for STAC when `ENABLE_TRANSACTIONS_EXTENSIONS: "true"`: `stac-fastapi-pgstac` opens a
  separate read pool (`POSTGRES_HOST_READER`) and write pool (`POSTGRES_HOST_WRITER`). This is easy to
  miss and a common cause of connection exhaustion. With transactions disabled STAC uses one pool.

**Example** — `maxReplicas: 5`, STAC transactions enabled (`pools = 2`):

| Settings | STAC ceiling |
|----------|--------------|
| `WEB_CONCURRENCY=4`, `DB_MAX_CONN_SIZE=3` | `5 × 4 × 2 × 3` = **120 connections** |
| `WEB_CONCURRENCY=2`, `DB_MAX_CONN_SIZE=1` | `5 × 2 × 2 × 1` = **20 connections** |

A default PostgreSQL allows `max_connections = 100`. The first row exhausts it from STAC alone, before
`raster`, `vector`, or anything else gets a connection.

### Budgeting connections

1. Start from the database's `max_connections`, minus reserved superuser slots.
2. Subtract everything else that uses the database — other services sharing it, ingest tooling,
   ad-hoc clients — and the chart's own clients (below).
3. Divide the remainder across the autoscaled services with the formula above (`pools = 2` for STAC
   with transactions). Leave headroom; never budget to 100%.

If a connection pooler (e.g. PgBouncer in transaction mode) fronts the database, size against the
pooler's server-side pool instead of the per-client numbers.

The chart opens connections beyond the API services. Allow for these too — they fire during deploys
and on schedules, often when the APIs are also busy:

| Component | When it connects | Demand |
|-----------|------------------|--------|
| pgSTAC bootstrap + migrate jobs (`pgstacBootstrap`) | Every install/upgrade | A few, short-lived |
| pgSTAC post-install/upgrade hooks | Every install/upgrade | A few, short-lived |
| `queueProcessor` CronJob | When `pgstacSettings.use_queue: "true"` | A few, on schedule |
| `extentUpdater` CronJob | When `pgstacSettings.update_collection_extent: "false"` | A few, on schedule |
| `eoapi-notifier` | When enabled | 1+ persistent (`LISTEN`) |

Also reserve rolling-update headroom: during a Deployment rollout Kubernetes starts new pods before
terminating old ones, so a service can briefly run at roughly `2 × replicas`.

### Reduce demand or raise `max_connections`?

Bring the total within budget by either **reducing demand** (lower `DB_MAX_CONN_SIZE`,
`WEB_CONCURRENCY`, or `maxReplicas`) or **raising supply** (`max_connections` on the database). Prefer
capping client pools when the database is shared or its hardware is fixed — it keeps demand
predictable. Raising `max_connections` is only safe if you control the database and can back each
connection with memory (`shared_buffers` + `work_mem × concurrency` + per-connection overhead must fit
RAM), otherwise you trade connection errors for OOM kills. `max_connections` and `work_mem` live on
the database, not in this chart.

### Example configuration

External database plus autoscaling with conservative pool caps (recompute against your
`max_connections` before production):

```yaml
postgrescluster:
  enabled: false

postgresql:
  type: "external-secret"
  external:
    host: "your-host"
    port: "5432"
    database: "eoapi"
    existingSecret:
      name: "your-db-secret"
      keys:
        username: "username"
        password: "password"

stac:
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    type: "requestRate"
    targets:
      requestRate: 50000m
  settings:
    envVars:
      WEB_CONCURRENCY: "4"
      DB_MIN_CONN_SIZE: "1"
      DB_MAX_CONN_SIZE: "1"  # pools=2 if ENABLE_TRANSACTIONS_EXTENSIONS=true

raster:
  autoscaling:
    enabled: true
    maxReplicas: 5
  settings:
    envVars:
      WEB_CONCURRENCY: "2"
      DB_MAX_CONN_SIZE: "1"

vector:
  autoscaling:
    enabled: true
    maxReplicas: 5
  settings:
    envVars:
      WEB_CONCURRENCY: "2"
      DB_MAX_CONN_SIZE: "1"
```

See [Configuration — External Database](configuration.md#external-database) for credential options.

### Scaling Policies

1. Go to the [releases section](https://github.com/developmentseed/eoapi-k8s/releases) of this repository and find the latest
`eoapi-support-<version>` version to install, or use the following command to get the latest version:

   ```bash
   # Get latest eoapi-support chart version
   export SUPPORT_VERSION=$(helm search repo eoapi/eoapi-support --versions | head -2 | tail -1 | awk '{print $2}')
   ```

```yaml
stac:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 20
    type: "both"
    behavior:
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
  cpu: 70
```

### Request Rate Scaling
```yaml
type: "requestRate"
targets:
  requestRate: 50000m  # 50 requests/second
```


### Combined Scaling
```yaml
type: "both"
targets:
  cpu: 70
  requestRate: 100000m  # 100 requests/second
```

## Custom Metrics Configuration

When using request rate scaling, the prometheus-adapter needs to be configured to expose custom metrics. This is handled automatically when you enable monitoring in the main chart:

```yaml
# In your main eoapi values file
ingress:
  host: your-domain.com

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
    maxReplicas: 20
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
    maxReplicas: 8
    type: "cpu"
    behavior:
      scaleDown:
        stabilizationWindowSeconds: 300
    targets:
      cpu: 75
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
      cpu: 70
      requestRate: 75000m
```

## STAC Auth Proxy

When [STAC Auth Proxy](./stac-auth-proxy.md) is enabled, ingress routes STAC traffic through the proxy. Under load, the proxy can become the bottleneck while `stac` CPU utilization stays low—enable proxy autoscaling in addition to (or instead of) relying on STAC HPA alone.

Autoscaling is provided by the **stac-auth-proxy subchart**. Configure it under `stac-auth-proxy.autoscaling` (CPU only; request-rate/`both` types apply to main eoAPI services with nginx ingress metrics).

```yaml
stac-auth-proxy:
  enabled: true
  resources:
    requests:
      cpu: 500m
    limits:
      cpu: 2000m
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 75
```

When `autoscaling.enabled` is true, `replicaCount` is ignored and the HPA manages replica count. Requires [metrics-server](#prerequisites) (or your cluster's equivalent) for CPU metrics.

The HPA resource name is `{{ .Release.Name }}-stac-auth-proxy` (subchart fullname). Check status with:

```bash
kubectl get hpa -n <namespace> | grep stac-auth-proxy
```

## Configuration Examples

For complete configuration examples, see the [production profile](../charts/eoapi/profiles/production.yaml).

## Resource Requirements

### Autoscaling Components
- **metrics-server**: ~100m CPU, ~300Mi memory per node
- **prometheus-adapter**: ~250m CPU, ~256Mi memory
- **prometheus-server**: ~500m CPU, ~512Mi memory (varies with retention)

## Verification

### Check HPA Status

```bash
# Check HPA status for all services
kubectl get hpa -n eoapi

# Get detailed HPA information
kubectl describe hpa eoapi-stac -n eoapi
```

### Verify Custom Metrics API

```bash
# Check if custom metrics API is available
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq .

# Check specific request rate metrics
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/eoapi/ingresses/*/requests_per_second" | jq .
```

### Check Prometheus Adapter

```bash
# Check prometheus-adapter logs
kubectl logs -l app.kubernetes.io/name=prometheus-adapter -n eoapi
```

## Load Testing

For load testing your autoscaling setup:

```yaml
ingress:
  host: your-test-domain.com
```

3. Check ingress configuration:
   ```bash
   kubectl get ingress -n eoapi
   ```

## Troubleshooting

### HPA Shows "Unknown" Metrics

If HPA shows "unknown" for custom metrics:

1. Verify prometheus-adapter is running:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=prometheus-adapter -n eoapi
   ```

2. Check prometheus-adapter logs:
   ```bash
   kubectl logs -l app.kubernetes.io/name=prometheus-adapter -n eoapi
   ```

3. Verify metrics are available in Prometheus:
   ```bash
   # Port forward to access Prometheus
   kubectl port-forward service/eoapi-prometheus-server 9090:80 -n eoapi
   # Then check metrics at http://localhost:9090
   ```

### Default Configuration

Default autoscaling configuration:

```yaml
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 5
  # Type can be "cpu", "requestRate", or "both"
  type: "cpu"
  # Custom scaling behavior (optional)
  behavior: {}
  # Scaling targets
  targets:
    # CPU target percentage (when type is "cpu" or "both")
    cpu: 80
    # Request rate target in millirequests per second (when type is "requestRate" or "both")
    requestRate: 30000m
```

### No Scaling Activity

If pods aren't scaling:

1. Check HPA events:
   ```bash
   kubectl describe hpa eoapi-stac -n eoapi
   ```

2. Verify metrics are being collected:
   ```bash
   kubectl top pods -n eoapi
   ```

3. Check resource requests are set:
   ```bash
   kubectl describe pod eoapi-stac-xxx -n eoapi | grep -A 10 "Requests"
   ```


### Install or Upgrade Autoscaling Changes to `eoapi` Chart

When enabling autoscaling, ensure monitoring is also enabled:

```yaml
# Enable monitoring first
monitoring:
  prometheus:
    enabled: true
  prometheusAdapter:
    enabled: true

# Then enable autoscaling
stac:
  autoscaling:
    enabled: true
    type: "requestRate"
    targets:
      requestRate: 50000m

# Configure resources for proper scaling metrics
stac:
  settings:
    resources:
      limits:
        cpu: 1000m
        memory: 512Mi
      requests:
        cpu: 100m
        memory: 128Mi
```

### Custom Metrics Not Working

If request rate metrics aren't working:

1. Verify nginx ingress controller has metrics enabled
2. Check prometheus is scraping ingress metrics
3. Confirm prometheus-adapter configuration
4. Validate ingress annotations for metrics

### Scaling Too Aggressive/Slow

Adjust scaling behavior:

```yaml
autoscaling:
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60    # Faster scaling up
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300   # Slower scaling down
      policies:
      - type: Percent
        value: 25                       # More conservative scale down
        periodSeconds: 300
```

## Best Practices

1. **Set appropriate resource requests**: HPA needs resource requests to calculate CPU utilization
2. **Use stabilization windows**: Prevent thrashing with appropriate cooldown periods
3. **Monitor costs**: Autoscaling can increase costs rapidly
4. **Test thoroughly**: Validate scaling behavior under realistic load
5. **Set reasonable limits**: Use `maxReplicas` to prevent runaway scaling
6. **Use multiple metrics**: Combine CPU and request rate for better scaling decisions

Example ingress configuration for load testing:

```yaml
# For AWS ALB
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: eoapi-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  ingressClassName: nginx
  rules:
  - host: your-domain.com
    http:
      paths: [...]

# For nginx ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: eoapi-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: abc5929f88f8c45c38f6cbab2faad43c-776419634.us-west-2.elb.amazonaws.com
    http:
      paths: [...]
```

## Load Testing

#### Load Testing with `hey`

The `hey` tool is a simple HTTP load testing tool.

### Install and Run Load Tests

1. Install hey:
   ```bash
   # macOS
   brew install hey

   # Linux
   go install github.com/rakyll/hey@latest

   # Or download from releases
   wget https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64
   chmod +x hey_linux_amd64
   sudo mv hey_linux_amd64 /usr/local/bin/hey
   ```

2. Run basic load test:
   ```bash
   # Test STAC endpoint
   hey -z 5m -c 10 https://your-domain.com/stac/collections

   # Test with higher concurrency
   hey -z 10m -c 50 https://your-domain.com/stac/search
   ```

3. Monitor during load test:
   ```bash
   # Watch HPA scaling
   watch kubectl get hpa -n eoapi

   # Monitor pods
   watch kubectl get pods -n eoapi
   ```


### Load Testing Best Practices

1. **Start small**: Begin with low concurrency and short duration
2. **Monitor resources**: Watch CPU, memory, and network usage
3. **Test realistic scenarios**: Use actual API endpoints and payloads
4. **Gradual increase**: Slowly increase load to find breaking points
5. **Test different endpoints**: Each service may have different characteristics

### Troubleshooting Load Tests

- **High response times**: May indicate need for more replicas or resources
- **Error rates**: Could suggest database bottlenecks or resource limits
- **No scaling**: Check HPA metrics and thresholds

### Advanced Load Testing

For more comprehensive testing, consider:
- **[Artillery](https://artillery.io/)** - Feature-rich load testing toolkit
- **[k6](https://k6.io/)** - Developer-centric performance testing
- **[Locust](https://locust.io/)** - Python-based distributed load testing

For monitoring and observability setup, see [observability.md](observability.md).
