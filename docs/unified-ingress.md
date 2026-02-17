---
title: "Unified Ingress Configuration"
description: "NGINX and Traefik ingress setup with TLS and cert-manager integration"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "NGINX Ingress Controller"
    url: "https://kubernetes.github.io/ingress-nginx/"
  - name: "Traefik Documentation"
    url: "https://doc.traefik.io/traefik/"
  - name: "cert-manager"
    url: "https://cert-manager.io/"
---

# Unified Ingress Configuration

This document describes the unified ingress approach implemented in the eoAPI Helm chart.

## Overview

eoAPI includes a single streamlined ingress configuration with smart defaults that routes to all enabled services. Services handle their own path routing via `--root-path` configuration, working with any ingress controller.

**Why one ingress?**
- One TLS certificate to manage
- One DNS entry
- Simple operations
- Works for 99% of deployments

**Why per-service paths?**
- Services can opt out: `stac.ingress.enabled: false`
- Custom paths: `raster.ingress.path: "/tiles"`
- Internal-only services stay off ingress

**Note:** Ingress is only created when at least one service is enabled.

## Configuration

The ingress configuration in `values.yaml`:

```yaml
ingress:
  enabled: true
  className: "nginx"  # or "traefik", or any ingress controller
  rootPath: ""        # Root path for doc server
  host: ""            # Single host (or use hosts array)
  hosts: []           # Multiple hosts (takes precedence over host)
  annotations: {}     # Custom annotations
  tls:
    enabled: false
    secretName: eoapi-tls
```

Each service can configure its ingress path:

```yaml
stac:
  enabled: true
  ingress:
    enabled: true
    path: "/stac"  # or "/" for root path

raster:
  enabled: true
  ingress:
    enabled: true
    path: "/raster"

browser:
  enabled: true
  ingress:
    enabled: true
    path: "/browser"
```

**Result:** Single Ingress → `https://api.example.com/stac`, `https://api.example.com/raster`

**Limitations:**
- Cannot use different ingress classes per service
- Cannot use different domains per service
- Cannot use different TLS certificates per service

For these cases, deploy multiple helm releases with different configurations.

## How It Works

### Path Routing

All services handle their own path routing internally:

- **STAC**: `--root-path=/stac` (or `/` for root)
  - Can be overridden with `stac.overrideRootPath` for custom deployments
- **Raster**: `--root-path=/raster`
- **Vector**: `--root-path=/vector`
- **Multidim**: `--root-path=/multidim`
- **Browser**: Built with `pathPrefix=/browser/`, nginx configured to serve at that path
  - ⚠️ **Important**: Browser path is fixed at build time. Do not change `browser.ingress.path` unless using a custom browser image built with matching `pathPrefix`

### Ingress Controller Support

The unified ingress works with **any** Kubernetes ingress controller.

All services use the same simple routing pattern:

#### NGINX Ingress Controller

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
```

#### Traefik Ingress Controller

```yaml
ingress:
  enabled: true
  className: "traefik"
  # When using TLS, setting host is required
  host: "example.domain.com"
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
```

### Path Handling Details

All services receive full paths and handle routing internally:

**Backend APIs:**
```
Client: GET /raster/tiles/123
  ↓
Ingress routes with Prefix pathType
  ↓
Service receives: GET /raster/tiles/123
Service configured: --root-path=/raster
```

**Frontend SPA (browser):**
```
Client: GET /browser/catalog/xyz
  ↓
Ingress routes with Prefix pathType
  ↓
Container receives: GET /browser/catalog/xyz
Nginx in container: location /browser { ... }
Vue Router: base /browser/
```

**Browser Path Constraint:**

The browser container is built with a fixed `pathPrefix` that must match `browser.ingress.path`. The default is `/browser`. If you need a different path:

1. Build a custom browser image with your desired `pathPrefix`
2. Configure Helm to use your custom image and matching path:
```yaml
browser:
  image: your-registry/custom-browser:tag
  ingress:
    path: "/your-custom-path"
```

See [Path Handling](path-handling.md) for detailed architecture.

## STAC Browser Configuration

The STAC browser now uses a separate ingress configuration to handle its unique requirements:
- Fixed `/browser` path prefix
- Special rewrite rules for browser-specific routes
- Maintains compatibility with both NGINX and Traefik

The browser-specific ingress is automatically configured when browser is enabled:
```yaml
browser:
  enabled: true
  ingress:
    enabled: true  # Can be disabled independently
```

### Custom Ingress Solutions

When using custom ingress solutions (e.g., APISIX, custom routes) where the Helm chart's ingress is disabled (`ingress.enabled: false`), you can explicitly override the STAC catalog URL for the browser:

```yaml
ingress:
  enabled: false  # Using custom ingress solution

browser:
  enabled: true
  catalogUrl: "https://earth-search.aws.element84.com/v1"  # Explicit catalog URL
  ingress:
    enabled: false  # Disable browser's built-in ingress
```

If `browser.catalogUrl` is not set, the URL will be automatically constructed from `ingress.host` and `stac.ingress.path`. This may result in invalid URLs (e.g., `http:///stac`) when `ingress.host` is empty.

## Setting up TLS with cert-manager

[cert-manager](https://cert-manager.io) can be used to automatically obtain and manage TLS certificates. Here's how to set it up with Let's Encrypt:

1. First, install cert-manager in your cluster:
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

2. Create a ClusterIssuer for Let's Encrypt (staging first for testing):
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    # Use Let's Encrypt staging environment first
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx  # or traefik, depending on your setup
```

3. After testing with staging, create the production issuer:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx  # or traefik, depending on your setup
```

4. Configure your eoAPI ingress to use cert-manager:
```yaml
ingress:
  enabled: true
  className: "nginx"  # or "traefik"
  host: "eoapi.example.com"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    enabled: true
    secretName: eoapi-tls  # cert-manager will create this secret
```

## Migration from 0.7.0

If you're upgrading from version 0.7.0:

1. Remove any `pathType` and `pathSuffix` configurations from your values
2. All services now use simple `Prefix` pathType routing
3. No path stripping or rewriting at ingress level
4. Each service handles its own path routing internally
5. If using custom browser paths, ensure browser image is built with matching `pathPrefix`

## Path Structure

Default service paths are:

- `/stac` - STAC API
- `/raster` - Raster API
- `/vector` - Vector API
- `/multidim` - Multi-dimensional API
- `/browser` - STAC Browser
- `/` - Documentation server (when enabled)

All paths are configurable via `service.ingress.path` in values.yaml.
