# k8s-eoapi

<p align="center">
  <a href="https://github.com/developmentseed/k8s-eoapi/actions?query=workflow%3ACI" target="_blank">
      <img src="https://github.com/developmentseed/k8s-eoapi/actions/workflows/helm-tests.yml/badge.svg" alt="Test">
  </a>
  <a href="https://github.com/developmentseed/k8s-eoapi/blob/main/LICENSE" target="_blank">
      <img src="https://img.shields.io/github/license/developmentseed/titiler.svg" alt="Downloads">
  </a>
</p>

## What is eoAPI?

[https://eoapi.dev/](https://eoapi.dev/)

## Getting Started

If you don't have a k8s cluster set up on AWS or GCP then follow an IAC guide below that is relevant to you

> &#9432; The helm chart in this repo assumes your cluster has a few third-party add-ons and controllers installed. So
> it's in your best interest to read through the IAC guides to understand what those defaults are

* [AWS EKS Cluster Setup](./docs/aws-eks.md)

* [TBD: GCP GKE Cluster Setup](./docs/gcp-gke.md)
 
## Helm Installation 

Once you have a k8s cluster set up you can `helm install` eoAPI as follows

1. `helm install` from this repo's `helm-chart/` folder:

    ```python
      ######################################################
      # create os environment variables for required secrets
      ######################################################
      $ export GITSHA=$(git rev-parse HEAD | cut -c1-10)
      $ export PGUSER=s00pers3cr3t
      $ export POSTGRES_USER=s00pers3cr3t
      $ export POSTGRES_PASSWORD=superuserfoobar
      $ export PGPASSWORD=foobar
   
      $ cd ./helm-chart

      $ helm install \
          --namespace eoapi \
          --create-namespace \
          --set gitSha=$GITSHA \
          --set db.settings.secrets.PGUSER=$PGUSER \
          --set db.settings.secrets.POSTGRES_USER=$POSTGRES_USER \
          --set db.settings.secrets.PGPASSWORD=$PGPASSWORD \
          --set db.settings.secrets.POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
          eoapi \
          ./eoapi
    ```

2. or `helm install` from the https://artifacthub.io:

    ```python
    $ TBD
    ```


