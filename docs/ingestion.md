
# Instructions for Loading Data into pgSTAC using Kubernetes and Helm

This guide outlines the steps necessary to configure and load data into a PostgreSQL STAC (pgSTAC) database within a Kubernetes environment using Helm. This guide is provided as a reference in the absence of a complete ingestion pipeline, which is best pr

## Prerequisites

- Ensure your Kubernetes cluster is running, and you have the necessary access to modify ConfigMaps and deploy Helm charts.
- The `eoAPI` Helm chart is installed and properly configured.
- STAC records for the collection and items you wish to load (e.g., `collection.json` and `items.json`).

## Step 1: Modify the `initdb-json-config-eoapi` ConfigMap

1. Edit the existing `initdb-json-config-eoapi` ConfigMap.  
2. Add the necessary collection and item files (these will be treated as separate entries by Kubernetes).

Here’s an example of how you could structure the ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: initdb-json-config-eoapi
data:
  collection.json: |
    { ... }  # Your collection JSON goes here.
  items.json: |
    { ... }  # Your items JSON goes here.
```

Make sure that your collection and items data are correctly formatted according to STAC specifications.

## Step 2: Configure the `pgstacBootstrap` Command

In your values file, ensure that `.Values.pgstacBootstrap.command` follows this format:

```bash
#!/bin/bash
bash /opt/initdb/apt-and-pip-install.sh
pypgstac pgready --dsn $PGADMIN_URI
pypgstac load collections /opt/initdb/json-data/collection.json --dsn $PGADMIN_URI --method insert_ignore
pypgstac load items /opt/initdb/json-data/items.json --dsn $PGADMIN_URI --method insert_ignore
exit 0
```

## Step 3: Deploy the Changes

Once the ConfigMap and the `pgstacBootstrap` command are correctly set up, run the following Helm command to upgrade your deployment:

```bash
helm upgrade <release-name> <chart-name> --values <values-file>
```

Replace `<release-name>`, `<chart-name>`, and `<values-file>` with your actual values.

After running this command, the `pgbootstrap` pod should start, execute the command script, and then exit gracefully once the data has been successfully loaded.

## Conclusion

Following these steps, the provided collections and items should be available through eoAPI. Ensure you monitor the logs of the `pgbootstrap` pod for any errors or confirmations of successful completion.
