# eoAPI Kubernetes Documentation

Technical documentation for deploying and operating eoAPI on Kubernetes clusters.

## Architecture

When deployed with default settings, eoAPI provides:
- High-availability PostgreSQL cluster (via PostgreSQL Operator)
- Load balancer with path-based routing:
  - `/stac` → STAC API
  - `/raster` → TiTiler raster API
  - `/vector` → TiPG vector API
  - `/browser` → STAC Browser
  - `/` → Documentation server
- Horizontal pod autoscaling based on CPU or request rate metrics
- Persistent storage with dynamic volume provisioning
- TLS termination and certificate management
- Health checks at `/stac/_mgmt/ping`, `/raster/healthz`, `/vector/healthz`

## Quick Start

Please refer to our [quick start guide](./installation/quick-start.md)

## Installation

1. Set up a Kubernetes cluster using one of the cloud provider guides
2. Install the PostgreSQL Operator dependency
3. Configure your deployment using the [Configuration Options](./installation/configuration.md)
4. Deploy using [Helm Installation](./installation/helm-install.md) instructions
5. Set up monitoring with [Autoscaling & Monitoring](./operations/autoscaling.md)

## Detailed documenation

### Cloud Provider Guides
- **[AWS EKS Setup](./installation/providers/aws-eks.md)** - Complete EKS cluster setup with OIDC, node autoscaling, EBS CSI, and NGINX ingress
- **[GCP GKE Setup](./installation/providers/gcp-gke.md)** - GKE cluster creation with CSI driver, NGINX ingress, and cert-manager
- **[Azure AKS Setup](./installation/providers/azure.md)** - Azure configuration with managed PostgreSQL, Key Vault integration, and Workload Identity

## Installation & Configuration

- **[Configuration Options](./installation/configuration.md)** - Complete reference for Helm values, database types, ingress setup, and service configuration
- **[Manual Helm Installation](./installation/helm-install.md)** - Step-by-step Helm deployment process with custom configurations
- **[Unified Ingress Configuration](./installation/unified-ingress.md)** - NGINX and Traefik ingress setup with TLS and cert-manager integration

## Database Management

- **[Data Management](./operations/manage-data.md)** - Loading STAC collections and items into PostgreSQL using pypgstac

## Operations & Monitoring

- **[Autoscaling & Monitoring](./operations/autoscaling.md)** - HPA setup with custom metrics, Grafana dashboards, Prometheus configuration, and load testing

## Advanced Features

- **[STAC Auth Proxy Integration](./advanced/stac-auth-proxy.md)** - Service-specific ingress control for authenticated STAC access

## Development & Release

- **[Release Workflow](./advanced/release.md)** - Chart versioning, GitHub releases, and Helm repository publishing process
