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

eoAPI includes database initialization jobs that must complete before application services start. ArgoCD's sync waves and hooks provide fine-grained control over resource deployment order.

## Quick Start

For most ArgoCD deployments, add these annotations to ensure proper sync order:

```yaml
pgstacBootstrap:
  jobAnnotations:
    argocd.argoproj.io/hook: "PreSync"
    argocd.argoproj.io/sync-wave: "-1"
    argocd.argoproj.io/hook-delete-policy: "HookSucceeded"
```

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
pgstacBootstrap:
  jobAnnotations:
    argocd.argoproj.io/hook: "PreSync"
```

#### Why PreSync?

- **Database First**: Schema must exist before application services start
- **Prevents Race Conditions**: Services won't start until database is ready
- **Follows Best Practices**: Standard pattern for database migrations
- **Dependency Management**: Explicit ordering prevents startup failures

### Sync Waves

Control execution order within phases using sync waves:

```yaml
pgstacBootstrap:
  jobAnnotations:
    argocd.argoproj.io/sync-wave: "-1"  # Run before wave 0 (default)
```

#### Wave Strategy

| Wave | Resources | Purpose |
|:-----|:----------|:--------|
| `-2` | Secrets, ConfigMaps | Prerequisites |
| `-1` | Database jobs | Schema initialization |
| `0` | Applications (default) | Main services |
| `1` | Ingress, monitoring | Post-deployment |

### Cleanup Policies

Configure job cleanup after successful execution:

```yaml
pgstacBootstrap:
  jobAnnotations:
    argocd.argoproj.io/hook-delete-policy: "HookSucceeded"
```

#### Available Policies

| Policy | Behavior |
|:-------|:---------|
| `HookSucceeded` | Delete after successful completion |
| `HookFailed` | Delete after failure |
| `BeforeHookCreation` | Delete before creating new hook |

## Complete Configuration Example

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
    targetRevision: "0.8.1"
    helm:
      values: |
        # Required values
        gitSha: "abc123def456"
        
        # Database initialization with ArgoCD integration
        pgstacBootstrap:
          enabled: true
          jobAnnotations:
            argocd.argoproj.io/hook: "PreSync"
            argocd.argoproj.io/sync-wave: "-1"
            argocd.argoproj.io/hook-delete-policy: "HookSucceeded"
          
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