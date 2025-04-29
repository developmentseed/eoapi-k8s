# Helm Chart Structure Refactoring

This directory contains the refactored Helm chart templates for the EOAPI services.

## Overview

The templates have been refactored from a loop-based approach to a service-specific approach where each service has its own dedicated template files. This improves readability, maintainability, and flexibility.

## Directory Structure

```
services/
├── _common.tpl                # Limited common helper functions
├── ingress.yaml               # Single ingress for all services
├── traefik-middleware.yaml    # Traefik middleware for path stripping
├── raster/                    # One directory per service
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── hpa.yaml
├── stac/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── hpa.yaml
├── vector/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── hpa.yaml
└── multidim/
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml
    └── hpa.yaml
```

## Key Improvements

1. **Enhanced Readability**: Each service's configuration is explicitly defined in its own files, making it easier to understand.
2. **Improved Debugging**: Errors are isolated to specific service files, making troubleshooting simpler.
3. **Lower Risk Changes**: Changes intended for one service are contained within its files, reducing the risk of affecting other services.
4. **True Flexibility**: Each service can evolve independently, and new services can be added by copying and modifying existing patterns.
5. **Limited Helper Functions**: Common logic is extracted into the `_common.tpl` file but only for the most mechanical, repetitive parts.

## How to Use

The chart maintains the same values.yaml structure but templates are now organized by service. The original looping templates have been preserved with `.old` extensions for reference.

For adding a new service:
1. Create a new directory with the service name
2. Copy and adapt the deployment, service, configmap, and hpa templates
3. Add an entry to ingress.yaml and traefik-middleware.yaml if needed
4. Update values.yaml with the new service configuration
