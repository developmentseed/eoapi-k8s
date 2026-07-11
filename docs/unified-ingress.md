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

eoAPI includes a single streamlined ingress configuration with smart defaults that routes to all enabled services. Services handle their own path routing via `--root-path` configuration behind NGINX or Traefik path rewriting.

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
  className: "nginx"  # or "traefik"
  rootPath: ""        # Root path for doc server
  host: ""            # Single host (or use hosts array)
  hosts: []           # Multiple hosts (takes precedence over host)
  annotations: {}     # Custom annotations for the main ingress
  preservePrefixAnnotations: {}  # NGINX: preserve-prefix ingress
  browserAnnotations: {}       # NGINX: browser ingress resources
  stacAuthAnnotations: {}      # NGINX: stac-auth ingress
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

API services run at root internally while ingress strips configured prefixes. Path matching differs by controller:

- **NGINX** uses regex paths with `ImplementationSpecific` path type and rewrite annotations for prefixed API routes
- **Traefik** uses `Prefix` paths with strip-prefix middleware
- **Root paths** (`stac.ingress.path: "/"`) keep `Prefix` path type and do not use rewrite or strip-prefix middleware. On **Traefik**, they stay on the main ingress. On **NGINX**, root-path API services and the doc server always render on `{release}-preserve-prefix-ingress` so `rewrite-target` never applies to `/`

Services configure their expected external prefix via the `--root-path` flag:

- **STAC**: `--root-path=/stac` (or `/` for root)
- **Raster**: `--root-path=/raster`
- **Vector**: `--root-path=/vector`
- **Multidim**: `--root-path=/multidim`
- **Browser**: Served at `/browser`. Unlike API services, the browser path prefix is preserved at the pod because the bundled image is built with `pathPrefix=/browser/`. Both controllers redirect bare `/browser` to `/browser/` (NGINX: 301, Traefik: 308). On **NGINX**, browser routes live on separate `{release}-browser-ingress` and `{release}-browser-redirect` resources without `rewrite-target`; API paths stay on `{release}-ingress`.

### Ingress Controller Support

The unified ingress supports **NGINX** and **Traefik** ingress controllers. Other controllers are not supported because the chart relies on controller-specific path rewrite behavior.

#### NGINX Ingress Controller

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
```

NGINX renders up to five ingress resources depending on which services are enabled:

- `{release}-ingress` — prefixed API services, with regex rewrite when any strip-prefix route is present
- `{release}-preserve-prefix-ingress` — root-path API services and the doc server (`Prefix` paths, no rewrite)
- `{release}-stac-auth-ingress` — STAC auth proxy when enabled (`Prefix` path, no rewrite)
- `{release}-browser-ingress` — browser (`Prefix` path `/browser/`, no rewrite)
- `{release}-browser-redirect` — bare `/browser` path (`Exact` path with `permanent-redirect`)

`ingress.annotations` apply to the main ingress. For separate NGINX ingress resources, use the dedicated annotation maps (`preservePrefixAnnotations`, `browserAnnotations`, `stacAuthAnnotations`). Each map is merged over a compatibility-filtered subset of `ingress.annotations` that omits rewrite, redirect, and snippet annotations unsafe on prefix-preserving routes.

#### Traefik Ingress Controller

```yaml
ingress:
  enabled: true
  className: "traefik"
  # When using TLS, setting host is required
  host: "example.domain.com"
  # Optional: pin the Traefik router to specific entrypoints. Omit (default) to
  # attach to all entrypoints, which is Traefik's own default. Note that "web" is
  # conventionally the HTTP entrypoint, so set "websecure" (or "web,websecure")
  # to serve HTTPS.
  entrypoints: "websecure"
```

If you set the same annotation via `ingress.annotations`, it overrides `ingress.entrypoints`
because user annotations are rendered after the chart defaults.

### Path Handling Details

Services run at root internally, ingress strips prefixes:

```
Client: GET /raster/tiles/123
  ↓
Ingress strips /raster
  ↓
Service receives: GET /tiles/123
```

**Exception:** STAC with `stac-auth-proxy.enabled: true` receives full path `/stac/...`

## STAC Browser Configuration

The STAC browser is routed through the unified ingress on Traefik, and via dedicated `{release}-browser-ingress` and `{release}-browser-redirect` resources on NGINX. Unlike API services, the browser keeps its path prefix at the pod because the bundled image is built with `pathPrefix=/browser/`. Both controllers add a bare-path redirect so `/browser` resolves to `/browser/`. The bundled image therefore supports only `/browser` (with an optional trailing slash) as `browser.ingress.path`.

```yaml
browser:
  enabled: true
  ingress:
    enabled: true  # Can be disabled independently
    path: "/browser"
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
2. The system will automatically use the appropriate settings for your chosen controller
3. For NGINX users, regex path matching is now enabled by default
4. For Traefik users, strip-prefix middleware is automatically configured

## Path Structure

Default service paths are:

- `/stac` - STAC API
- `/raster` - Raster API
- `/vector` - Vector API
- `/multidim` - Multi-dimensional API
- `/browser` - STAC Browser
- `/` - Documentation server (when enabled)

All paths are configurable via `service.ingress.path` in values.yaml.
