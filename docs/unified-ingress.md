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
  pathType: "Prefix"
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/enable-access-log: "true"
```

### Traefik Ingress Controller

When using Traefik, the system automatically includes the Traefik middleware to strip prefixes (e.g., `/stac`, `/raster`) from requests before forwarding them to services. This is handled by the `traefik-middleware.yaml` template.

For basic Traefik configuration:

```yaml
ingress:
  enabled: true
  className: "traefik"
  pathType: "Prefix"
  # When using TLS, setting host is required to avoid "No domain found" warnings
  host: "example.domain.com"  # Required to work properly with TLS
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
```

For Traefik with TLS:

```yaml
ingress:
  enabled: true
  className: "traefik"
  pathType: "Prefix"
  # Host is required when using TLS with Traefik
  host: "example.domain.com"
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
  tls:
    enabled: true
    secretName: eoapi-tls
```

## Migration

If you're migrating from a previous version, follow these guidelines:

1. Update your values to use the new unified configuration
2. Ensure your ingress controller-specific annotations are set correctly
3. Set the appropriate `pathType` for your controller
4. Test the configuration before deploying to production

## Note for Traefik Users

Traefik is now fully supported in all environments, including production. The previous restriction limiting Traefik to testing environments has been removed.

## Document Server

The document server implementation has also been unified. It now works with both NGINX and Traefik controllers using the same configuration.
