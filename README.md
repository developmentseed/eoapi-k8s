# eoapi-k8s

<p align="center">
    <img height=200 src="https://raw.githubusercontent.com/developmentseed/eoapi-k8s/refs/heads/main/docs/images/eoapi-k8s.svg" alt="eoapi-k8s">
</p>

[eoAPI](https://eoapi.dev/) is a progressive platform for hosting Earth Observation data. It offers a suite of APIs (OGC and STAC-based) for data access and analysis. This repository includes a production-ready Kubernetes deployment with flexible database options, unified ingress configuration, and built-in monitoring.

<p>
  <a href="https://github.com/developmentseed/eoapi-k8s/actions?query=workflow%3ACI" target="_blank">
      <img src="https://github.com/developmentseed/eoapi-k8s/actions/workflows/ci.yml/badge.svg?branch=main" alt="Test">
  </a>
  <a href="https://github.com/developmentseed/eoapi-k8s/blob/main/LICENSE" target="_blank">
      <img src="https://img.shields.io/github/license/developmentseed/titiler.svg" alt="License">
  </a>
  <a href="https://artifacthub.io/packages/search?repo=eoapi" target="_blank">
      <img src="https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/eoapi" alt="Artifact Hub">
  </a>
</p>

## Prerequisites

- Kubernetes cluster (1.21+)
- Helm 3.x
- `kubectl` configured for cluster access

## Documentation

### Get started

* [General eoAPI documentation](https://eoapi.dev).
* [eoAPI-k8s documentation](https://eoapi.dev/deployment/kubernetes)

## Contributing

We welcome contributions! See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development workflow, testing, and PR guidelines.

**We'd :heart: to hear from you!** Please [join the discussion](https://github.com/developmentseed/eoAPI/discussions/209) to share how you're using eoAPI, or email eoapi@developmentseed.org.

## License

This project is licensed under the [MIT License](./LICENSE).
