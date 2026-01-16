---
title: "STAC Auth Proxy"
description: "Service-specific ingress control for authenticated STAC access"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "STAC Auth Proxy"
    url: "https://github.com/developmentseed/stac-auth-proxy"
---

# STAC Auth Proxy

## Overview

STAC Auth Proxy integration allows the STAC service to be accessible only through an authenticated proxy while other eoAPI services remain externally available.

## Deployment

### 1. Configure eoAPI-K8S

Disable external STAC ingress and configure root path:

```yaml
# values.yaml for eoapi-k8s
stac:
  enabled: true
  overrideRootPath: ""  # No --root-path argument (proxy handles prefix)
  ingress:
    enabled: false  # Required: prevents unauthenticated direct access

# Other services remain externally accessible
raster:
  enabled: true
vector:
  enabled: true
```

### 2. Deploy STAC Auth Proxy

Configure stac-auth-proxy subchart to point to the STAC service:

```yaml
# values.yaml
stac-auth-proxy:
  enabled: true
  env:
    UPSTREAM_URL: "http://eoapi-stac:8080"  # Replace 'eoapi' with your release name
    OIDC_DISCOVERY_URL: "https://your-auth-provider.com/.well-known/openid-configuration"
    ALLOWED_JWT_AUDIENCES: "https://your-api-audience.com"  # Recommended: should match the audience configured in your identity provider for this API.
    ROOT_PATH: "/stac"
```

For complete configuration options, see the [stac-auth-proxy configuration documentation](https://developmentseed.org/stac-auth-proxy/user-guide/configuration).

### 3. Authentication Policy

Control which endpoints require authentication:

```yaml
stac-auth-proxy:
  env:
    # Set a default policy: read operations (GET) are public, write operations (POST, PUT, PATCH, DELETE) require authentication
    DEFAULT_PUBLIC: "true" # This is "false" if not specified

    # Alternatively, you may set your custom policies (JSON objects)
    PRIVATE_ENDPOINTS: |
      {
        "^/collections$": ["POST"],
        "^/collections/([^/]+)$": ["PUT", "PATCH", "DELETE"],
        "^/collections/([^/]+)/items$": ["POST"],
        "^/collections/([^/]+)/items/([^/]+)$": ["PUT", "PATCH", "DELETE"]
      }

    PUBLIC_ENDPOINTS: |
      {
        "^/$": ["GET"],
        "^/conformance$": ["GET"],
        "^/healthz": ["GET"]
      }
```

 Or, you can also create more complex custom filters (see [upstream documentation](https://developmentseed.org/stac-auth-proxy/user-guide/record-level-auth/#custom-filter-factories)). For this you will need to add the extra file and configure **all three** requirements:

```yaml
stac-auth-proxy:
  # 1. Set filter class environment variables
  env:
    COLLECTIONS_FILTER_CLS: stac_auth_proxy.custom_filters:CollectionsFilter
    ITEMS_FILTER_CLS: stac_auth_proxy.custom_filters:ItemsFilter

  # 2. Specify custom filters file path
  customFiltersFile: "data/stac-auth-proxy/custom_filters.py"

  # 3. Configure volume mount
  extraVolumes:
    - name: filters
      configMap:
        name: stac-auth-proxy-filters
  extraVolumeMounts:
    - name: filters
      mountPath: /app/src/stac_auth_proxy/custom_filters.py
      subPath: custom_filters.py
      readOnly: true
```

**Note**: All three components are required. `customFiltersFile` creates the ConfigMap, `extraVolumes` references it, `extraVolumeMounts` loads it into the container.

## Root Path Behavior

### Why `overrideRootPath: ""`

stac-auth-proxy manages the `/stac` prefix and forwards requests without it to the STAC service. Setting `overrideRootPath: ""` removes the `--root-path` argument so FastAPI responds as if running at root `/`.

**Request flow**:
```
Client: /stac/collections → Proxy: /collections → STAC service receives: /collections
```
