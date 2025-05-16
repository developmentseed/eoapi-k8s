# Unified Ingress Configuration

This document describes the unified ingress approach implemented in the eoAPI Helm chart.

## Overview

As of version 0.7.0, eoAPI uses an even more streamlined ingress configuration with smart defaults for different controllers. This approach:

- Eliminates manual pathType and suffix configurations
- Uses controller-specific optimizations for NGINX and Traefik
- Provides separate configuration for STAC browser
- Maintains backward compatibility while improving usability

## Configuration

The ingress configuration has been simplified in the `values.yaml` file:

```yaml
ingress:
  # Unified ingress configuration for both nginx and traefik
  enabled: true
  # ingressClassName: "nginx" or "traefik"
  className: "nginx"
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

## Controller-Specific Behavior

### NGINX Ingress Controller

For NGINX, the system automatically:
- Uses `ImplementationSpecific` pathType
- Adds regex-based path matching
- Sets up proper rewrite rules

Basic NGINX configuration:
```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    # Additional custom annotations if needed
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/enable-access-log: "true"
```

### Traefik Ingress Controller

For Traefik, the system:
- Uses `Prefix` pathType by default
- Automatically configures strip-prefix middleware
- Handles path-based routing appropriately

Basic Traefik configuration:
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
