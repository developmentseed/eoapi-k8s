---
title: "eoAPI Kubernetes"
description: "Production-ready Kubernetes deployment"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
---

# eoAPI Kubernetes

Production-ready Kubernetes deployment for eoAPI.

The source code is maintained in the [eoapi-k8s repository](https://github.com/developmentseed/eoapi-k8s). Contributions are welcome!

## Kubernetes Architecture

This deployment provides:

- Path-based ingress routing (`/stac`, `/raster`, `/vector`, `/browser`, ..)
- A PostgreSQL cluster (via PostgreSQL Operator)
- TLS termination and certificate management
- Persistent storage with dynamic volume provisioning
- Horizontal pod autoscaling with custom metrics
- Built-in health checks and monitoring at `/stac/_mgmt/ping`, `/raster/healthz`, `/vector/healthz`

## Getting Started

Ready to deploy? Start with our [Quick Start guide](./quick-start.md) for fast installation, or explore the full documentation below for production deployments.
