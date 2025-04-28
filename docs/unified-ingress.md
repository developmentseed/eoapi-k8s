# Unified Ingress Configuration

This document describes the unified ingress approach implemented in the eoAPI Helm chart.

## Overview

eoAPI now uses a consolidated, controller-agnostic ingress configuration. This approach:

- Eliminates code duplication between different ingress controller implementations
- Provides consistent behavior across controllers
- Simplifies testing and maintainability
- Removes artificial restrictions on using certain ingress controllers in specific environments
- Makes it easier to add support for additional ingress controllers in the future

## Configuration

The ingress configuration has been streamlined and generalized in the `values.yaml` file:

```yaml
ingress:
  # Unified ingress configuration for both nginx and traefik
  enabled: true
  # ingressClassName: "nginx" or "traefik"
  className: "nginx"
  # Path configuration
  pathType: "Prefix"  # Can be "Prefix" or "ImplementationSpecific" based on controller
  pathSuffix: ""      # Add a suffix to service paths (e.g. "(/|$)(.*)" for nginx regex)
  rootPath: ""        # Root path for doc server
  # Host configuration
  host: ""
  # Custom annotations to add to the ingress
  annotations: {}
  # TLS configuration
  tls:
    enabled: false
    secretName: eoapi-tls
    certManager: false
    certManagerIssuer: letsencrypt-prod
    certManagerEmail: ""
```

## Controller-Specific Configurations

### NGINX Ingress Controller

For NGINX, use the following configuration:

```yaml
ingress:
  enabled: true
  className: "nginx"
  pathType: "ImplementationSpecific"
  pathSuffix: "(/|$)(.*)"  # Required for NGINX path rewriting
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/enable-access-log: "true"
```

### Traefik Ingress Controller

For Traefik, use the following configuration:

```yaml
ingress:
  enabled: true
  className: "traefik"
  pathType: "Prefix"
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.pathtransform.regex: "^/([^/]+)(.*)"
    traefik.ingress.kubernetes.io/router.pathtransform.replacement: "/$1$2"
```

## Migration

If you're migrating from a previous version, follow these guidelines:

1. Update your values to use the new unified configuration
2. Ensure your ingress controller-specific annotations are set correctly
3. Set the appropriate `pathType` and `pathSuffix` for your controller
4. Test the configuration before deploying to production

## Note for Traefik Users

Traefik is now fully supported in all environments, including production. The previous restriction limiting Traefik to testing environments has been removed.

## Document Server

The document server implementation has also been unified. It now works with both NGINX and Traefik controllers using the same configuration.
