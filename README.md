# eoapi-k8s

<p align="center">
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

2. or `helm install` from https://devseed.com/eoapi-k8s/:

    ```python
      # add the eoapi helm repo locally
      $ helm repo add eoapi https://devseed.com/eoapi-k8s/
    
      # list out the eoapi chart versions
      $ helm search repo eoapi 
      NAME            CHART VERSION   APP VERSION     DESCRIPTION                                       
      eoapi/eoapi     0.1.1           0.1.0           Create a full Earth Observation API with Metada...
      eoapi/eoapi     0.1.2           0.1.0           Create a full Earth Observation API with Metada...
   
      # add the required secret overrides to an arbitrarily named `.yaml` file (`config.yaml` below)
      $ cat config.yaml 
      db:
        settings:
          secrets:
            PGUSER: "username"
            POSTGRES_USER: "username"
            PGPASSWORD: "password"
            POSTGRES_PASSWORD: "password"
    
      # then run `helm install` with those overrides 
      # NOTE: nginx in the default ingress so if you are using that make sure your nginx controller 
      # is in the same namespace beforehand or services won't be exposed
      # https://github.com/developmentseed/eoapi-k8s/blob/main/docs/aws-eks.md#nginx-ingress
      $ helm install -n eoapi --create-namespace eoapi eoapi/eoapi --version 0.1.2 -f config.yaml
    ```


