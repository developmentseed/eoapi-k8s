# eoapi-k8s

<p align="center">
    <img height=200 src="https://raw.githubusercontent.com/developmentseed/eoapi-k8s/refs/heads/main/docs/eoapi-k8s.svg" alt="eoapi-k8s">
</p>
<p>
  <a href="https://github.com/developmentseed/eoapi-k8s/actions?query=workflow%3ACI" target="_blank">
      <img src="https://github.com/developmentseed/eoapi-k8s/actions/workflows/helm-tests.yml/badge.svg?branch=main" alt="Test">
  </a>
  <a href="https://github.com/developmentseed/eoapi-k8s/blob/main/LICENSE" target="_blank">
      <img src="https://img.shields.io/github/license/developmentseed/titiler.svg" alt="Downloads">
  </a>
</p>

## What is eoAPI?

[https://eoapi.dev/](https://eoapi.dev/)

## Getting Started

Make sure you have [helm](https://helm.sh/docs/intro/install/) installed on your machine.
Additionally, you will need a cluster to deploy the eoAPI helm chart. This can be on a cloud provider, like AWS, GCP, or any other that supports Kubernetes. You can also run a local cluster using minikube.

### Local

For a local installation you can use a preinstalled [Minikube](https://minikube.sigs.k8s.io/), and simply execute the following command:

```bash
$ make minikube
```

Once the deployment is done, the url to access eoAPI will be printed to your terminal.

### Cloud

If you don't have a k8s cluster set up on AWS or GCP then follow an IaC guide below that is relevant to you

> &#9432; The helm chart in this repo assumes your cluster has a few third-party add-ons and controllers installed. So
> it's in your best interest to read through the IaC guides to understand what those defaults are

* [AWS EKS Cluster Setup](./docs/aws-eks.md)
* [GCP GKE Cluster Setup](./docs/gcp-gke.md)

Make sure you have your `kubectl` configured to point to the cluster you want to deploy eoAPI to. Then simply execute the following command:

```bash
$ make deploy
```

### Manual step-by-step installation

Instead of using the `make` commands above you can also [manually `helm install` eoAPI](./docs/helm-install.md).


## More information

* Read about [Default Configuration](./docs/configuration.md#default-configuration) and
other [Configuration Options](./docs/configuration.md#additional-options)
* Learn about [Autoscaling / Monitoring / Observability](./docs/autoscaling.md)
