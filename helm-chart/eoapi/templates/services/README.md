# Service-Specific Templates

This directory contains service-specific templates organized to improve readability, maintainability, and flexibility.

## Directory Structure

```
services/
├── _common.tpl            # Limited common helper functions
├── ingress.yaml           # Single shared ingress for all services
├── raster/                # Raster service templates
│   ├── deployment.yaml    # Deployment definition
│   ├── service.yaml       # Service definition
│   ├── configmap.yaml     # ConfigMap definition
│   └── hpa.yaml           # HorizontalPodAutoscaler definition
├── stac/                  # STAC service templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── hpa.yaml
├── vector/                # Vector service templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── hpa.yaml
└── multidim/             # Multidimensional service templates
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml
    └── hpa.yaml
```

## Common Helpers

The `_common.tpl` file provides limited helper functions for truly common elements:

- `eoapi.mountServiceSecrets`: For mounting service secrets
- `eoapi.commonEnvVars`: For common environment variables like SERVICE_NAME, RELEASE_NAME, GIT_SHA
- `eoapi.pgstacInitContainers`: For init containers that wait for pgstac jobs

For database environment variables, we leverage the existing `eoapi.postgresqlEnv` helper from the main `_helpers.tpl` file.

## Usage

No changes to `values.yaml` structure were required. The chart maintains full backward compatibility with existing deployments.
