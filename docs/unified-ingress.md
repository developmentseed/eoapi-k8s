---
title: "Unified Ingress Configuration"
description: "Traefik ingress setup with NGINX compatibility, TLS and cert-manager integration"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Traefik Documentation"
    url: "https://doc.traefik.io/traefik/"
  - name: "Traefik NGINX Provider"
    url: "https://doc.traefik.io/traefik/routing/providers/kubernetes-ingress-nginx/"
  - name: "NGINX Ingress Controller"
    url: "https://kubernetes.github.io/ingress-nginx/"
  - name: "cert-manager"
    url: "https://cert-manager.io/"
---

# Unified Ingress Configuration

This document describes the unified ingress approach implemented in the eoAPI Helm chart.

## Overview

eoAPI defaults to **Traefik** as the ingress controller, leveraging Traefik's NGINX provider for seamless compatibility with NGINX ingress annotations. This approach:

- Uses Traefik 3.5+ with NGINX provider support for zero-drama migration from ingress-nginx
- Maintains compatibility with existing NGINX ingress annotations
- Eliminates manual pathType and suffix configurations
- Provides separate configuration for STAC browser
- Maintains backward compatibility with NGINX ingress controller

## Configuration

The ingress configuration defaults to Traefik with NGINX provider support:

```yaml
ingress:
  # Unified ingress configuration for both nginx and traefik
  # Traefik 3.5+ supports nginx annotations via the nginx provider
  # Set --experimental.kubernetesIngressNGINX and --providers.kubernetesIngressNGINX when deploying Traefik
  enabled: true
  # ingressClassName: "traefik" (default) or "nginx"
  className: "traefik"
  # Root path for doc server
  rootPath: ""
  # Host configuration
  host: ""
  # Custom annotations to add to the ingress
  annotations: {}
  # TLS configuration
  tls:
    enabled: false
    secretName: eoapi-tls
```

## Deploying Traefik with NGINX Provider

To use Traefik as a drop-in replacement for ingress-nginx, deploy Traefik with the NGINX provider enabled:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --version ~v37.3.0 \
  --set providers.kubernetesGateway.enabled=true \
  --set 'additionalArguments[0]=--providers.kubernetesIngressNGINX' \
  --set 'additionalArguments[1]=--experimental.kubernetesIngressNGINX=true' \
  --wait
```

This enables Traefik to understand and process NGINX ingress annotations, allowing you to migrate from ingress-nginx with minimal changes.

## Controller-Specific Behavior

### Traefik Ingress Controller (Default)

Traefik is now the default ingress controller. When using Traefik with the NGINX provider:
- Uses `ImplementationSpecific` pathType (same as NGINX)
- Supports NGINX ingress annotations natively
- Handles regex-based path matching via NGINX annotations
- Automatically processes rewrite rules from NGINX annotations

The eoAPI chart automatically applies NGINX annotations when using Traefik, which are understood by Traefik's NGINX provider:

```yaml
ingress:
  enabled: true
  className: "traefik"  # Default
  host: "example.domain.com"
  annotations:
    # NGINX annotations work with Traefik's NGINX provider
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/enable-access-log: "true"
```

### NGINX Ingress Controller (Legacy)

For backward compatibility, NGINX ingress controller is still supported:

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/enable-access-log: "true"
```

**Note:** With ingress-nginx entering maintenance mode (EoL March 2026), migrating to Traefik is recommended.

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
          class: traefik  # or nginx for legacy setups
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
          class: traefik  # or nginx for legacy setups
```

4. Configure your eoAPI ingress to use cert-manager:
```yaml
ingress:
  enabled: true
  className: "traefik"  # Default, or "nginx" for legacy setups
  host: "eoapi.example.com"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    enabled: true
    secretName: eoapi-tls  # cert-manager will create this secret
```

## Migration from ingress-nginx to Traefik

### Why Migrate?

With ingress-nginx entering maintenance mode (EoL March 2026), migrating to Traefik provides:
- **Security**: Traefik's secure-by-design architecture eliminates template injection vulnerabilities
- **Future-proof**: Gateway API leadership and modern cloud-native design
- **Zero-drama migration**: NGINX provider allows using existing annotations without changes
- **Production-ready**: Battle-tested at scale with 3.4+ billion downloads

### Migration Steps

1. **Deploy Traefik with NGINX provider** (see [Deploying Traefik](#deploying-traefik-with-nginx-provider) above)

2. **Update your values.yaml**:
   ```yaml
   ingress:
     className: "traefik"  # Changed from "nginx"
   ```

3. **No annotation changes needed**: Your existing NGINX annotations will work with Traefik's NGINX provider

4. **Verify the migration**:
   ```bash
   kubectl get ingress
   kubectl get pods -n traefik
   ```

5. **Test your endpoints** to ensure everything works as expected

### Migration from 0.7.0

If you're upgrading from version 0.7.0:

1. Remove any `pathType` and `pathSuffix` configurations from your values
2. The system will automatically use the appropriate settings for your chosen controller
3. NGINX annotations work with both NGINX and Traefik (via NGINX provider)
4. Regex path matching is enabled by default for both controllers

## Path Structure

Default service paths are:
- `/stac` - STAC API
- `/raster` - Raster API
- `/vector` - Vector API
- `/multidim` - Multi-dimensional API
- `/browser` - STAC Browser (separate ingress)
- `/` - Documentation server (when enabled)

These paths are automatically configured with the appropriate rewrites for each controller.
