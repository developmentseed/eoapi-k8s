---
title: "Unified Ingress Configuration"
description: "NGINX and Traefik ingress setup with TLS and cert-manager integration"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Traefik Documentation"
    url: "https://doc.traefik.io/traefik/"
  - name: "Migrate from Ingress NGINX to Traefik"
    url: "https://doc.traefik.io/traefik/migrate/nginx-to-traefik/"
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

**Note:** The main ingress is created when at least one API service or doc server is enabled. The browser has its own rewrite-free ingress when `ingress.enabled` is true, browser is enabled, and `browser.ingress` is not disabled (omitting `browser.ingress` still enables it).

## Configuration

The ingress configuration in `values.yaml`:

```yaml
ingress:
  enabled: true
  className: "nginx"  # or "traefik", or any ingress controller
  rootPath: ""        # Root path for doc server
  host: ""            # Single host (or use hosts array)
  hosts: []           # Multiple hosts (takes precedence over host)
  annotations: {}     # Custom annotations (chart owns rewrite-target/use-regex/router.middlewares)
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

All services use `pathType: Prefix` and handle their own path prefixes internally via the `--root-path` flag:

- **STAC**: `--root-path=/stac` (or `/` for root)
- **Raster**: `--root-path=/raster`
- **Vector**: `--root-path=/vector`
- **Multidim**: `--root-path=/multidim`
- **Browser**: Served from a separate rewrite-free ingress; the pod receives `SB_pathPrefix` from `browser.ingress.path`

### Ingress Controller Support

The unified ingress works with **any** Kubernetes ingress controller. We recommend Traefik: the community [ingress-nginx](https://github.com/kubernetes/ingress-nginx) controller was retired in March 2026 and its repository is archived.

#### Traefik Ingress Controller

Install Traefik with [`traefik-values.yaml`](https://github.com/developmentseed/eoapi-k8s/blob/main/docs/traefik-values.yaml). It keeps the behaviour ingress-nginx had by default: it redirects HTTP to HTTPS, sends HSTS, drops request headers whose name aliases another one (`X_Forwarded_For`) and answers 400 to an encoded NUL (`%00`) in the path.

```sh
curl -fsSLO https://raw.githubusercontent.com/developmentseed/eoapi-k8s/main/docs/traefik-values.yaml
helm upgrade --install traefik traefik \
  --repo https://traefik.github.io/charts --version 42.4.1 \
  --namespace traefik --create-namespace \
  -f traefik-values.yaml
```

Then set the class in your eoAPI values:

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
because user annotations are rendered after the chart defaults. The NGINX path-rewrite annotations
are chart-owned: `nginx.ingress.kubernetes.io/rewrite-target` and
`nginx.ingress.kubernetes.io/use-regex` in `ingress.annotations` have no effect.
`traefik.ingress.kubernetes.io/router.middlewares` is merged instead: the chart appends its
strip-prefix middleware to yours, so your middlewares run first.

Coming from ingress-nginx, note that:

- Every HTTP request is redirected to HTTPS, not only those for Ingresses with TLS, so set `ingress.host` and `ingress.tls` ([cert-manager](#setting-up-tls-with-cert-manager) can issue the certificate).
- The Traefik chart makes `traefik` the default IngressClass, and Traefik also serves Ingresses that set no class. On clusters with other ingress controllers, review the chart's `ingressClass.isDefaultClass` and `providers.kubernetesIngress.ingressClass` values.
- `nginx.ingress.kubernetes.io/*` annotations have no effect.
- ingress-nginx's default 1 MiB request body limit is gone. Traefik's [buffering middleware](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/buffering/) can set one.
- Compression (`use-gzip` in ingress-nginx) needs Traefik's [compress middleware](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/compress/).
- Request-rate autoscaling reads ingress-nginx metrics: use `type: "cpu"` (see [Autoscaling](autoscaling.md)).

#### Existing ingress-nginx clusters

With `className: "nginx"` the chart rewrites paths through `nginx.ingress.kubernetes.io/*` annotations. Serve them with Traefik's [Ingress NGINX provider](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-ingress-nginx/) rather than ingress-nginx: it reads [most of these annotations](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress-nginx/), so existing clusters keep their class and their own `ingress.annotations`. F5's NGINX Ingress Controller ignores these annotations, so the chart's path rewriting does not work with it.

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://app.example.com"
```

`enable-cors` behaves differently under Traefik: without `cors-allow-origin`, Traefik answers with the request's `Origin` and `Access-Control-Allow-Credentials: true`, where ingress-nginx answered `*`. Set `cors-allow-origin` to the origins you expect, as above.

The provider serves Ingresses whose IngressClass has `controller: k8s.io/ingress-nginx`. The ingress-nginx chart creates the `nginx` IngressClass; the Traefik chart does not. To move a cluster from ingress-nginx to Traefik without an outage:

1. Keep the `nginx` IngressClass when ingress-nginx is uninstalled. Helm reads this policy from its release, so `kubectl annotate` does not work. Keep your installed chart version (`helm list -n ingress-nginx`):

   ```sh
   helm upgrade ingress-nginx ingress-nginx \
     --repo https://kubernetes.github.io/ingress-nginx \
     --namespace ingress-nginx --reuse-values \
     --version <installed chart version> \
     --set-json 'controller.ingressClassResource.annotations={"helm.sh/resource-policy": "keep"}'
   ```

   Then check that `kubectl describe ingressclass nginx` shows the annotation. If ingress-nginx was not installed with Helm, leave this IngressClass out of what you delete in step 4. You can re-create it with:

   ```sh
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: IngressClass
   metadata:
     name: nginx
   spec:
     controller: k8s.io/ingress-nginx
   EOF
   ```

2. Install Traefik next to ingress-nginx with the provider enabled. While both run, Traefik must not write the Ingress status, or the two controllers keep overwriting each other's address:

   ```sh
   helm upgrade --install traefik traefik \
     --repo https://traefik.github.io/charts --version 42.4.1 \
     --namespace traefik --create-namespace \
     -f traefik-values.yaml \
     --set providers.kubernetesIngressNGINX.enabled=true \
     --set providers.kubernetesIngressNGINX.publishService.enabled=false
   ```

   Check eoAPI through Traefik's load balancer before moving traffic, for example with `curl --connect-to <host>:443:<traefik-address>:443 https://<host>/stac`. Traefik redirects every HTTP request to HTTPS, including Ingresses without TLS that ingress-nginx served over plain HTTP.

3. Set autoscaling to `type: "cpu"` (see [Autoscaling](autoscaling.md)), then point your DNS records at Traefik's load balancer (`kubectl -n traefik get svc traefik`). Keep ingress-nginx running until clients stop using its address.

   If external-dns manages these records, it reads them from the Ingress status, which still shows ingress-nginx's address. Make ingress-nginx publish Traefik's address instead:

   ```sh
   helm upgrade ingress-nginx ingress-nginx \
     --repo https://kubernetes.github.io/ingress-nginx \
     --namespace ingress-nginx --reuse-values \
     --version <installed chart version> \
     --set controller.publishService.pathOverride=traefik/traefik
   ```

4. Uninstall ingress-nginx, then let Traefik write the Ingress status, which external-dns and Argo CD read:

   ```sh
   helm uninstall ingress-nginx --namespace ingress-nginx
   helm upgrade traefik traefik \
     --repo https://traefik.github.io/charts --version 42.4.1 \
     --namespace traefik --reuse-values \
     --set providers.kubernetesIngressNGINX.publishService.enabled=true
   ```

Traefik's [migration guide](https://doc.traefik.io/traefik/migrate/nginx-to-traefik/) covers these steps in more detail. You can switch to `className: "traefik"` later, once your own `nginx.ingress.kubernetes.io/*` annotations have Traefik equivalents. Switch your cert-manager issuer to `ingressClassName: traefik` at the same time, or certificate renewals fail.

### Path Handling Details

Services run at root internally, ingress strips prefixes:

```
Client: GET /raster/tiles/123
  ↓
Ingress strips /raster
  ↓
Service receives: GET /tiles/123
```

**Exception:** STAC with `stac-auth-proxy.enabled: true` receives full path `/stac/...`. On NGINX this is served from a separate rewrite-free ingress; Traefik keeps auth-proxy on the main ingress and omits `/stac` from strip-prefix.

## STAC Browser Configuration

The STAC browser uses its own ingress so path rewriting does not strip the browser prefix. The pod receives `SB_pathPrefix` from `browser.ingress.path`.

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
          ingressClassName: traefik  # the ingress.className of your eoAPI release
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
          ingressClassName: traefik  # the ingress.className of your eoAPI release
```

4. Configure your eoAPI ingress to use cert-manager:
```yaml
ingress:
  enabled: true
  className: "traefik"
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
