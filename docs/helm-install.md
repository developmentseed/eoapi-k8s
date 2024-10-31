# Manual Helm Install

0. `eoapi-k8s` depends on the [Crunchydata Postgresql Operator](https://access.crunchydata.com/documentation/postgres-operator/latest/installation/helm). Install that first:

   ```bash
   $ helm install --set disable_check_for_upgrades=true pgo oci://registry.developers.crunchydata.com/crunchydata/pgo --version 5.5.2
   ```

1. Add the eoapi repo from https://devseed.com/eoapi-k8s/:

    ```bash
    $ helm repo add eoapi https://devseed.com/eoapi-k8s/
    ```

2. List out the eoapi chart versions

   ```bash
   $ helm search repo eoapi --versions
   NAME            CHART VERSION   APP VERSION     DESCRIPTION
   eoapi/eoapi     0.2.14          0.3.1           Create a full Earth Observation API with Metada...
   eoapi/eoapi     0.1.13          0.2.11          Create a full Earth Observation API with Metada...
   ```

3. Optionally override keys/values in the default `values.yaml` with a custom `config.yaml` like below:

   ```bash
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

   ```bash
   $ helm install -n eoapi --create-namespace eoapi eoapi/eoapi --version 0.1.2 -f config.yaml
   ```

5. or check out this repo and `helm install` from this repo's `helm-chart/` folder:

    ```bash
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
