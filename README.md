# k8s-eoapi

IAC for AWS/GCP and k8s helm chart

---

## Getting Started

If you don't have a k8s cluster set up on AWS or GCP then follow an IAC guide below that is relevant to you:

* [AWS EKS Cluster IAC Setup](./docs/aws-eks.md)

* [GCP GKE Cluster IAC Setup](./docs/gcp-gke.md)
 
## Helm Installation 

Once you have a k8s cluster set up you can `helm install` eoAPI as follows

1. `helm install` from this repo's `helm-chart/` folder:

    ```python
      ##########
      # first, create os environment variables for required secrets
      ##########
      $ export GITSHA=$(git rev-parse HEAD | cut -c1-10)
      $ export PGUSER=s00pers3cr3t
      $ export POSTGRES_USER=s00pers3cr3t
      $ export POSTGRES_PASSWORD=superuserfoobar
      $ export PGPASSWORD=foobar

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
    TBD
    ```


