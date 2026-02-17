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

## How It Works

### Path Routing

All services use `pathType: Prefix` and handle their own path prefixes internally via the `--root-path` flag:

- **STAC**: `--root-path=/stac` (or `/` for root)
- **Raster**: `--root-path=/raster`
- **Vector**: `--root-path=/vector`
- **Multidim**: `--root-path=/multidim`
- **Browser**: Configured via environment variable

### Ingress Controller Support

The unified ingress works with **any** Kubernetes ingress controller:

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
2. The system will automatically use the appropriate settings for your chosen controller
3. For NGINX users, regex path matching is now enabled by default
4. For Traefik users, strip-prefix middleware is automatically configured

## Path Structure

Default service paths are:
- `/stac` - STAC API
- `/raster` - Raster API
- `/vector` - Vector API
- `/multidim` - Multi-dimensional API
- `/browser` - STAC Browser (separate ingress)
- `/` - Documentation server (when enabled)

These paths are automatically configured with the appropriate rewrites for each controller.
