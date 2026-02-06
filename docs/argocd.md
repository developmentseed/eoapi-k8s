---
title: "ArgoCD Integration"
description: "Guide for deploying eoAPI with ArgoCD, including sync waves, hooks, and best practices"
external_links:
  - name: "ArgoCD Sync Phases and Waves"
    url: "https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/"
  - name: "ArgoCD Resource Hooks"
    url: "https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/"
---

# ArgoCD Integration

This guide covers deploying eoAPI with ArgoCD, focusing on sync order management, database initialization, and troubleshooting common issues.

## Overview

eoAPI uses database setup jobs that must finish before the API services start. ArgoCD sync hooks and sync waves let you control the order in which resources are applied.

## Database Bootstrap Jobs

eoAPI includes several database initialization jobs:

| Job | Purpose | Dependencies |
|:----|:--------|:-------------|
| `pgstac-migrate` | Database schema migration | PostgreSQL ready |
| `pgstac-load-samples` | Load sample data | Schema migrated |
| `pgstac-load-queryables` | Configure queryables | Schema migrated |

### Job Execution Order

The jobs use Helm hook weights to ensure proper ordering:

1. **pgstac-migrate** (weight: `-5`) - Creates database schema
2. **pgstac-load-samples** (weight: `-4`) - Loads sample collections/items
3. **pgstac-load-queryables** (weight: `-3`) - Configures search queryables

## ArgoCD Sync Configuration

### Sync Phases

Use **PreSync** for database initialization jobs to ensure they complete before application deployment:

```yaml
annotations:
  argocd.argoproj.io/hook: "PreSync"
```

#### Why use PreSync?

- **Database First**: Schema must exist before application services start
- **Prevents Race Conditions**: Services won't start until database is ready
- **Follows Best Practices**: Standard pattern for database migrations
- **Dependency Management**: Explicit ordering prevents startup failures

### Sync Waves

Control execution order within phases using sync waves:

```yaml
annotations:
  argocd.argoproj.io/sync-wave: "0"
```

#### Wave Strategy

| Wave | Resources | Purpose |
|:-----|:----------|:--------|
| `-2` | Secrets, ConfigMaps | Prerequisites |
| `-1` | Database jobs | Schema initialization |
| `0` | Applications (default) | Main services |
| `1` | Ingress, monitoring | Post-deployment |

### PreSync executions

### Phase `-7`

All required resources are created or updated:

- `PostgresCluster` (Required by all jobs)
- Config: `-pgstac-settings-config`
- Config: `-initdb-sql-config`
- Config: `-initdb-json-config`
- Config: `-pgstac-queryables-config`
- Config: `-initdb`

### Phase `-6`

Database users are created:

- Job: `-pgstac-superuser-init-db`
  - Depends on: Config `-initdb`

### Phase `-5`

Database schema and settings are applied:

- Job: `-pgstac-migrate`
  - Depends on: Config: `-pgstac-settings-config`

### Phase `-4`

Sample data is loaded:

- Job: `-pgstac-load-samples`
  - Depends on:
    - Config: `-initdb-sql-config`
    - Config: `-initdb-json-config`
    - Job: `-pgstac-migrate`

### Phase `-3`

Queryables are loaded:

- Job: `-pgstac-load-queryables`
    - Depends on
        - Config: Custom Queryable ConfigsMap
        - Job: `-pgstac-migrate`
        - Job: `-pgstac-load-samples` (Optional)

> NOTE:
> Queryables are user-defined. Make sure their ConfigMap uses a PreSync hook and runs before phase `-3`.
>
> Example:
>
> ```yaml
> apiVersion: v1
> kind: ConfigMap
> metadata:
>   name: montandon-eoapi-stac-queryables
>   annotations:
>     argocd.argoproj.io/hook: "PreSync"
>     argocd.argoproj.io/sync-wave: "-7"
>     argocd.argoproj.io/hook-delete-policy: "BeforeHookCreation"
> data:
>   ...
> ```

## Complete Configuration Example

Using pre-defined [values/argocd.yaml](charts/eoapi/values/argocd.yaml)
> [!CAUTION]
> This configuration might be outdated and may not work as expected. Feel free to contribute fixes or improvements.

```yaml
# Application values for ArgoCD deployment
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: eoapi
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://devseed.com/eoapi-k8s/
    chart: eoapi
    targetRevision: "latest"
    helm:
      valueFiles:
        - values/argocd.yaml
      values: |
        # Required values
        gitSha: "abc123def456"

        # Database initialization with ArgoCD integration
        pgstacBootstrap:
          enabled: true

        # Service configuration
        apiServices: ["stac", "raster", "vector"]

        # Ingress setup
        ingress:
          enabled: true
          className: "nginx"
          host: "eoapi.example.com"

  destination:
    server: https://kubernetes.default.svc
    namespace: eoapi

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - "CreateNamespace=true"
      - "RespectIgnoreAnnotations=true"
```

## Further Reading

- [ArgoCD Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ArgoCD Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
- [Helm Install Process](../helm-install.md)
- [Configuration Options](../configuration.md)
