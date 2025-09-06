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

## Prerequisites

- Kubernetes cluster (1.21+)
- Helm 3.x
- `kubectl` configured for cluster access

## Documentation

### Get started

* [Quick start guide](./docs/installation/quick-start.md)

### `eoAPI-k8s` documentation

* [Overview of docs](./docs/index.md)

### General eoAPI documentation
* [eoapi.dev](https://eoapi.dev) website.

## Contributing

* **We would :heart: to hear from you!** Please [join the discussion](https://github.com/developmentseed/eoAPI/discussions/209) and let us know how you're using eoAPI! This helps us improve the project for you and others. If you prefer to remain anonymous, you can email us at eoapi@developmentseed.org, and we'll be happy to post a summary on your behalf.

* **We welcome contributions** from the community! Feel free to open an issue or submit a pull request.

## License

This project is licensed under the [MIT License](./LICENSE).
