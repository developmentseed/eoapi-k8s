---
title: "Configuration Options"
description: "Complete reference for Helm values, database types, ingress setup, and service configuration"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Helm Values Documentation"
    url: "https://helm.sh/docs/chart_best_practices/values/"
---

# Configuration Options

## Required Values

The required values to pass to `helm install` or `helm template` commands can be found in our schema validation:

```bash
{
  "required": [
    "service",
    "gitSha"
  ]
}
```

Most fields have sensible defaults. Here are the core configuration options:

| **Values Key** | **Description** | **Default** | **Choices** |
|:--------------|:----------------|:------------|:------------|
| `service.port` | Port for all services (vector/raster/stac) | 8080 | any valid port |
| `gitSha` | SHA for deployment tracking | gitshaABC123 | any valid SHA |

## Database Configuration

### PostgreSQL Cluster (Default)

Using Crunchydata's PostgreSQL Operator (`postgresql.type: "postgrescluster"`):

| **Values Key** | **Description** | **Default** | **Choices** |
|:--------------|:----------------|:------------|:------------|
| `postgrescluster.enabled` | Enable PostgreSQL cluster. Must be set to `false` when using external databases | true | true/false |
| `postgrescluster.name` | Cluster name | Release name | any valid k8s name |
| `postgrescluster.postgresVersion` | PostgreSQL version | 16 | supported versions |
| `postgrescluster.postGISVersion` | PostGIS version | "3.4" | supported versions |

### External Database

For external databases, set `postgresql.type` to either `external-plaintext` or `external-secret` and set `postgrescluster.enabled: false`.


1. Using plaintext credentials (`external-plaintext`):
```yaml
postgrescluster:
  enabled: false
postgresql:
  type: "external-plaintext"
  external:
    host: "your-host"
    port: "5432"
    database: "eoapi"
    credentials:
      username: "eoapi"
      password: "your-password"
```

2. Using Kubernetes secrets (`external-secret`):
```yaml
postgresql:
  type: "external-secret"
  external:
    existingSecret:
      name: "your-secret"
      keys:
        username: "username"
        password: "password"
    host: "your-host"  # can also be in secret
    port: "5432"       # can also be in secret
    database: "eoapi"  # can also be in secret
```

## PgSTAC Configuration

Control PgSTAC database behavior and performance tuning:

### Core Settings

Configure via `pgstacBootstrap.settings.pgstacSettings`:

| **Values Key** | **Description** | **Default** | **Format** |
|:--------------|:----------------|:------------|:-----------|
| `queue_timeout` | Timeout for queued queries | "10 minutes" | PostgreSQL interval |
| `use_queue` | Enable query queue mechanism | "false" | boolean string |
| `update_collection_extent` | Auto-update collection extents | "true" | boolean string |

### Context Settings

Control search result count calculations:

| **Values Key** | **Description** | **Default** | **Format** |
|:--------------|:----------------|:------------|:-----------|
| `context` | Context mode | "auto" | "on", "off", "auto" |
| `context_estimated_count` | Row threshold for estimates | "100000" | integer string |
| `context_estimated_cost` | Cost threshold for estimates | "100000" | integer string |
| `context_stats_ttl` | Stats cache duration | "1 day" | PostgreSQL interval |

### Automatic Maintenance Jobs

CronJobs are conditionally created based on PgSTAC settings:

**Queue Processor** (created when `use_queue: "true"`):
- `queueProcessor.schedule`: "0 * * * *" (hourly)
- Processes queries that exceeded timeout

**Extent Updater** (created when `update_collection_extent: "false"`):
- `extentUpdater.schedule`: "0 2 * * *" (daily at 2 AM)
- Updates collection spatial/temporal boundaries

By default, no CronJobs are created (use_queue=false, update_collection_extent=true).

Both schedules are customizable using standard cron format.

Example configuration:

```yaml
pgstacBootstrap:
  settings:
    pgstacSettings:
      # Performance tuning for large datasets
      queue_timeout: "20 minutes"
      use_queue: "true"
      update_collection_extent: "false"

      # Optimize context for performance
      context: "auto"
      context_estimated_count: "50000"
      context_estimated_cost: "75000"
      context_stats_ttl: "12 hours"
```

### Queryables Configuration

Configure custom queryables for STAC API search using `pypgstac load-queryables`. Queryables can be loaded from files in the chart or from external ConfigMaps.

#### Basic Configuration

Each queryable requires a `name` field and either a `file` (from chart) or `configMapRef` (external ConfigMap):

```yaml
pgstacBootstrap:
  settings:
    queryables:
      # File-based queryable from chart
      - name: "common-queryables.json"
        file: "data/initdb/queryables/test-queryables.json"

      # External ConfigMap reference
      - name: "custom-queryables.json"
        configMapRef:
          name: my-custom-queryables-configmap
          key: queryables.json
```

#### Configuration Parameters

| **Parameter** | **Description** | **Required** | **Example** |
|:--------------|:----------------|:-------------|:------------|
| `name` | Name for the queryables file | Yes | "common-queryables.json" |
| `file` | Path to queryables file in chart | No* | "data/initdb/queryables/test-queryables.json" |
| `configMapRef.name` | Name of external ConfigMap | No* | "my-queryables-cm" |
| `configMapRef.key` | Key in the ConfigMap | No* | "queryables.json" |
| `indexFields` | Fields to create indexes for | No | ["platform", "instruments"] |
| `deleteMissing` | Delete queryables not in this file | No | true |
| `collections` | Apply to specific collections | No | ["collection-1", "collection-2"] |

\* Either `file` or `configMapRef` must be provided

#### Advanced Example

Mix file-based and ConfigMap-based queryables with optional parameters:

```yaml
pgstacBootstrap:
  settings:
    queryables:
      # Standard queryables from chart with indexes
      - name: "common-queryables.json"
        file: "data/initdb/queryables/common-queryables.json"
        indexFields: ["platform", "instruments"]
        deleteMissing: true

      # Custom queryables from external ConfigMap
      - name: "sentinel-queryables.json"
        configMapRef:
          name: sentinel-queryables-cm
          key: queryables.json
        indexFields: ["sat:orbit_state", "sar:instrument_mode"]
        collections: ["sentinel-1-grd"]

      # Collection-specific queryables
      - name: "landsat-queryables.json"
        configMapRef:
          name: landsat-queryables-cm
          key: data.json
        collections: ["landsat-c2-l2"]
```

#### External ConfigMap Setup

When using `configMapRef`, create the ConfigMap separately:

```bash
# From a file
kubectl create configmap my-queryables-cm \
  --from-file=queryables.json=./my-queryables.json \
  -n eoapi

# From literal JSON
kubectl create configmap my-queryables-cm \
  --from-literal=queryables.json='{"$schema": "...", "properties": {...}}' \
  -n eoapi
```

The queryables will be automatically loaded during the PgSTAC bootstrap process.

### ArgoCD Integration

For ArgoCD deployments, See the [ArgoCD Integration Guide](argocd.md) for detailed configuration and best practices.

## Cloud Storage Authentication

eoAPI services access COG files in cloud storage buckets. Use cloud-native authentication instead of long-lived credentials:

### AWS (IRSA)

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eoapi-s3-access
```

The raster service automatically uses IRSA credentials via the AWS SDK credential chain.

### Azure (Workload Identity)

```yaml
serviceAccount:
  create: true
  annotations:
    azure.workload.identity/client-id: "your-client-id"
    azure.workload.identity/tenant-id: "your-tenant-id"
```

### GCP (Workload Identity)

```yaml
serviceAccount:
  create: true
  annotations:
    iam.gke.io/gcp-service-account: eoapi-gcs-sa@project.iam.gserviceaccount.com
```

All services using GDAL (raster API with titiler-pgstac) automatically use these credentials through their respective cloud SDKs. No environment variables or hardcoded credentials needed.

## Ingress Configuration

Unified ingress configuration supporting both NGINX and Traefik:

| **Values Key** | **Description** | **Default** | **Choices** |
|:--------------|:----------------|:------------|:------------|
| `ingress.enabled` | Enable ingress | true | true/false |
| `ingress.className` | Ingress controller | "nginx" | "nginx", "traefik" |
| `ingress.host` | Ingress hostname | "" | valid hostname |
| `ingress.rootPath` | Doc server root path | "" | valid path |

See [Unified Ingress Configuration](unified-ingress.md) for detailed setup.

## Service Configuration

Each service (stac, raster, vector, multidim) supports:

| **Values Key** | **Description** | **Default** | **Choices** |
|:--------------|:----------------|:------------|:------------|
| `{service}.enabled` | Enable the service | varies | true/false |
| `{service}.image.name` | Container image | varies | valid image |
| `{service}.image.tag` | Image tag | varies | valid tag |
| `{service}.autoscaling.enabled` | Enable HPA | false | true/false |
| `{service}.autoscaling.type` | Scaling metric | "requestRate" | "cpu", "requestRate", "both" |

Example service configuration:
```yaml
raster:
  enabled: true
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    type: "requestRate"
    targets:
      cpu: 75
      requestRate: "100000m"
```

## STAC Browser

| **Values Key** | **Description** | **Default** | **Choices** |
|:--------------|:----------------|:------------|:------------|
| `browser.enabled` | Enable STAC browser | true | true/false |
| `browser.replicaCount` | Number of replicas | 1 | integer > 0 |
| `browser.ingress.enabled` | Enable browser ingress | true | true/false |
| `browser.catalogUrl` | Override STAC catalog URL for browser. Useful when using custom ingress solutions (e.g., APISIX) with `ingress.enabled=false` | "" (auto-constructed from `ingress.host` and `stac.ingress.path`) | Valid URL string |
| `browser.catalogTitle` | Custom catalog title | "" | string |
| `browser.catalogImage` | Custom catalog logo/image URL | "" | URL string |
| `browser.footerLinks` | Custom footer links | `[]` | Array of `{label, url}` objects |

Example:

```yaml
browser:
  catalogTitle: "My Data Catalog"
  catalogImage: "https://example.com/logo.png"
  footerLinks:
    - label: "Home"
      url: "https://example.com/"
    - label: "Docs"
      url: "https://docs.example.com/"
```

## Deployment Architecture

When using default settings, the deployment looks like this:
![](./images/default_architecture.png)

The deployment includes:
- HA PostgreSQL database (via PostgreSQL Operator)
- Sample data fixtures
- Load balancer with path-based routing:
  - `/stac` → STAC API
  - `/raster` → Titiler
  - `/vector` → TiPG
  - `/browser` → STAC Browser
  - `/` → Documentation

### Health Monitoring

All services include health check endpoints with automatic liveness probes:

| **Service** | **Health Endpoint** | **Response** |
|:------------|:-------------------|:-------------|
| STAC API | `/stac/_mgmt/ping` | HTTP 200, no auth required |
| Raster API | `/raster/healthz` | HTTP 200, no auth required |
| Vector API | `/vector/healthz` | HTTP 200, no auth required |

The Kubernetes deployment templates automatically configure `livenessProbe` settings for regular health checks. See the [deployment template](https://github.com/developmentseed/eoapi-k8s/blob/main/charts/eoapi/templates/services/deployment.yaml) for probe configuration details.

## Advanced Configuration

### Autoscaling Behavior

Fine-tune scaling behavior:

```yaml
autoscaling:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
```

See [Kubernetes HPA documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#configurable-scaling-behavior) for details.

### Resource Requirements

Each service can have custom resource limits:

```yaml
settings:
  resources:
    limits:
      cpu: "768m"
      memory: "1024Mi"
    requests:
      cpu: "256m"
      memory: "512Mi"
```

### Additional Service Settings

Each service also supports:
```yaml
settings:
  labels: {}                # Additional pod labels
  extraEnvFrom: []         # Additional environment variables from references
  extraVolumeMounts: []    # Additional volume mounts
  extraVolumes: []         # Additional volumes
  envVars: {}             # Environment variables
```
