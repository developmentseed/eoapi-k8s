---
title: "Quick Start"
description: "Fast installation guide for eoAPI Kubernetes deployment"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Helm Documentation"
    url: "https://helm.sh/docs/"
---

# Quick Start

## Prerequisites

- [helm](https://helm.sh/docs/intro/install/)
- A Kubernetes cluster (local or cloud-based)
- `kubectl` configured for your cluster (ensure `KUBECONFIG` environment variable is set to point to your cluster configuration file, or use `kubectl config use-context <your-context>` to set the active cluster)
- [helm unittest](https://github.com/helm-unittest/helm-unittest?tab=readme-ov-file#install) if contributing to the repository and running `make tests`

## Option 1: One-Command Installation

The fastest way to get started is using our Makefile commands:

For local development with Minikube:
```bash
make minikube
```

For cloud deployment:
```bash
make deploy
```

This will automatically:
1. Install the PostgreSQL operator
2. Add the eoAPI helm repository
3. Install the eoAPI helm chart
4. Set up necessary namespaces and configurations

> [!WARNING]
> Some images do not provide a `linux/arm64` compatible download (You may see image pull failures) which causes failures on M1 etc Macs, to get around this, you can pre-pull the image with:
> ```
> docker pull --platform=linux/amd64 <image>
> minikube image load <image>
> ```
> You can then re-deploy the service and it will now use the local image.

## Option 2: Step-by-Step Installation

If you prefer more control over the installation process:

1. Install the PostgreSQL operator:
```bash
helm upgrade --install \
  --set disable_check_for_upgrades=true pgo \
  oci://registry.developers.crunchydata.com/crunchydata/pgo \
  --version 5.7.4
```

2. Add the eoAPI helm repository:
```bash
helm repo add eoapi https://devseed.com/eoapi-k8s/
```

3. Get your current git SHA:
```bash
export GITSHA=$(git rev-parse HEAD | cut -c1-10)
```

4. Install eoAPI:
```bash
helm upgrade --install \
  --namespace eoapi \
  --create-namespace \
  --set gitSha=$GITSHA \
  eoapi devseed/eoapi
```

### Post-Installation

1. Enable ingress (for Minikube only - k3s has Traefik built-in):
```bash
minikube addons enable ingress
```

2. Optional: Load sample data:
```bash
make ingest
```
