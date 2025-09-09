# Manual Helm Install

0. `eoapi-k8s` depends on the [Crunchydata Postgresql Operator](https://access.crunchydata.com/documentation/postgres-operator/latest/installation/helm). Install that first:

   ```bash
   # Check latest version at: https://github.com/CrunchyData/postgres-operator/releases
   $ helm install --set disable_check_for_upgrades=true pgo oci://registry.developers.crunchydata.com/crunchydata/pgo --version 5.7.0
   ```

1. Add the eoapi repo from https://devseed.com/eoapi-k8s/:

    ```bash
    $ helm repo add eoapi https://devseed.com/eoapi-k8s/
    ```

2. List out the eoapi chart versions

   ```bash
   $ helm search repo eoapi --versions
   # Use latest stable version from output above
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
   # Replace VERSION with latest from `helm search repo eoapi`
   $ export CHART_VERSION=$(helm search repo eoapi/eoapi --versions | head -2 | tail -1 | awk '{print $2}')
   $ helm install -n eoapi --create-namespace eoapi eoapi/eoapi --version $CHART_VERSION -f config.yaml
   ```

5. or check out this repo and `helm install` from this repo's `charts/` folder:

    ```bash
      ######################################################
      # create os environment variables for required secrets
      ######################################################
      $ export GITSHA=$(git rev-parse HEAD | cut -c1-10)

      $ cd ./charts

      $ helm install \
          --namespace eoapi \
          --create-namespace \
          --set gitSha=$GITSHA \
          eoapi \
          ./eoapi
    ```
