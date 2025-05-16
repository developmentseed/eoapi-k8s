# eoapi-k8s

<p align="center">
    <img height=200 src="https://raw.githubusercontent.com/developmentseed/eoapi-k8s/refs/heads/main/docs/eoapi-k8s.svg" alt="eoapi-k8s">
</p>
<p>
  <a href="https://github.com/developmentseed/eoapi-k8s/actions?query=workflow%3ACI" target="_blank">
      <img src="https://github.com/developmentseed/eoapi-k8s/actions/workflows/helm-tests.yml/badge.svg?branch=main" alt="Test">
  </a>
  <a href="https://github.com/developmentseed/eoapi-k8s/blob/main/LICENSE" target="_blank">
      <img src="https://img.shields.io/github/license/developmentseed/titiler.svg" alt="License">
  </a>
  <a href="https://artifacthub.io/packages/search?repo=eoapi" target="_blank">
      <img src="https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/eoapi" alt="Artifact Hub">
  </a>
</p>

## What is eoAPI?

[eoAPI](https://eoapi.dev/) is a collection of REST APIs for Earth Observation data access and analysis. This repository provides a production-ready Kubernetes deployment solution with flexible database options, unified ingress configuration, and built-in monitoring.

## Quick Start

### Prerequisites

- [helm](https://helm.sh/docs/intro/install/)
- A Kubernetes cluster (local or cloud-based)
- `kubectl` configured for your cluster

### Option 1: One-Command Installation

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

### Option 2: Step-by-Step Installation

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

1. Enable ingress (for Minikube):
```bash
minikube addons enable ingress
```

2. Optional: Load sample data:
```bash
make ingest
```

## Cloud Provider Setup

For cloud-based deployments, refer to our detailed setup guides:
* [AWS EKS Cluster Setup](./docs/aws-eks.md)
* [GCP GKE Cluster Setup](./docs/gcp-gke.md)
* [Azure Setup](./docs/azure.md)

## Documentation

* [Configuration Guide](./docs/configuration.md)
* [Data Management](./docs/manage-data.md)
* [Autoscaling and Monitoring](./docs/autoscaling.md)
* [Health Checks](./docs/health.md)
* [Unified Ingress Configuration](./docs/unified-ingress.md)
* [Upgrade Guide](./docs/upgrade.md)

> **Important Notice**: If you're upgrading from a version prior to 0.7.0, please read the [upgrade guide](./docs/upgrade.md) for important database permission changes.

## Contributing

We welcome contributions! See our [contributing guide](./CONTRIBUTING.md) for details.

## License

This project is licensed under the [MIT License](./LICENSE).
