# eoapi-k8s

<p align="center">
  <a href="https://github.com/developmentseed/eoapi-k8s/actions?query=workflow%3ACI" target="_blank">
      <img src="https://github.com/developmentseed/eoapi-k8s/actions/workflows/helm-tests.yml/badge.svg?branch=main" alt="Test">
  </a>
  <a href="https://github.com/developmentseed/eoapi-k8s/blob/main/LICENSE" target="_blank">
      <img src="https://img.shields.io/github/license/developmentseed/titiler.svg" alt="Downloads">
  </a>
</p>

## Table of Contents
* [What is eoAPI](#whatitis)
* [Getting Started](#gettingstarted)
* [Helm Installation](#helminstall)
* [Default Configuration and Options](#options)
* [Autoscaling](./docs/autoscaling.md)

<a name="whatitis"/>

## What is eoAPI?

[https://eoapi.dev/](https://eoapi.dev/)

<a name="gettingstarted"/>

## Getting Started

If you don't have a k8s cluster set up on AWS or GCP then follow an IaC guide below that is relevant to you

> &#9432; The helm chart in this repo assumes your cluster has a few third-party add-ons and controllers installed. So
> it's in your best interest to read through the IaC guides to understand what those defaults are

* [AWS EKS Cluster Setup](./docs/aws-eks.md)

* [GCP GKE Cluster Setup](./docs/gcp-gke.md)
 
<a name="helminstall"/>

## Helm Installation

Once you have a k8s cluster set up you can `helm install` eoAPI with the following steps:

0. `eoapi-k8s` depends on the [Crunchydata Postgresql Operator](https://access.crunchydata.com/documentation/postgres-operator/latest/installation/helm). Install that first:

   ```python
   $ helm install --set disable_check_for_upgrades=true pgo oci://registry.developers.crunchydata.com/crunchydata/pgo --version 5.5.2
   ```


1. Add the eoapi repo from https://devseed.com/eoapi-k8s/:

    ```python
      $ helm repo add eoapi https://devseed.com/eoapi-k8s/
    ```

2. List out the eoapi chart versions
    
   ```python
   $ helm search repo eoapi --versions
   NAME            CHART VERSION   APP VERSION     DESCRIPTION                                       
   eoapi/eoapi     0.2.14          0.3.1           Create a full Earth Observation API with Metada...
   eoapi/eoapi     0.1.13          0.2.11          Create a full Earth Observation API with Metada...
   ```
3. Optionally override keys/values in the default `values.yaml` with a custom `config.yaml` like below:

   ```python
   $ cat config.yaml 
   vector:
     enable: false
   pgstacBootstrap:
     settings:
       envVars:
         LOAD_FIXTURES: "0"
         RUN_FOREVER: "1"
   ```
4. Then `helm install` with those `config.yaml` values:

   ```python
   $ helm install -n eoapi --create-namespace eoapi eoapi/eoapi --version 0.1.2 -f config.yaml
   ```

5. or check out this repo and `helm install` from this repo's `helm-chart/` folder:

    ```python
      ######################################################
      # create os environment variables for required secrets
      ######################################################
      $ export GITSHA=$(git rev-parse HEAD | cut -c1-10)
   
      $ cd ./helm-chart

      $ helm install \
          --namespace eoapi \
          --create-namespace \
          --set gitSha=$GITSHA \
          eoapi \
          ./eoapi
    ```
   
<a name="options"/>

## Configuration Options and Defaults
Read about [Default Configuration](./docs/configuration.md#default-configuration) and 
other [Configuration Options](./docs/configuration.md#additional-options) in the documentation
