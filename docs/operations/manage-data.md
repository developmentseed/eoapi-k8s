# Data management

eoAPI-k8s provides a basic data ingestion process that consist of manual operations on the components of the stack.

# Load data

You will have to have STAC records for the collection and items you wish to load (e.g., `collections.json` and `items.json`).
[This repo](https://github.com/vincentsarago/MAXAR_opendata_to_pgstac) contains a few script that may help you to generate sample input data.

## Preshipped bash script

Execute `make ingest` to load data into the eoAPI service - it expects `collections.json` and `items.json` in the current directory.

## Manual steps

In order to add raster data to eoAPI you can load STAC collections and items into the PostgreSQL database using pgSTAC and the tool `pypgstac`.

First, ensure your Kubernetes cluster is running and `kubectl` is configured to access and modify it.

In a second step, you'll have to upload the data into the pod running the raster eoAPI service. You can use the following commands to copy the data:

```bash
kubectl cp collections.json "$NAMESPACE/$EOAPI_POD_RASTER":/tmp/collections.json
kubectl cp items.json "$NAMESPACE/$EOAPI_POD_RASTER":/tmp/items.json
```
Then, bash into the pod or server running the raster eoAPI service, you can use the following commands to load the data:

```bash
#!/bin/bash
apt update -y && apt install python3 python3-pip -y && pip install pypgstac[psycopg]';
pypgstac pgready --dsn $PGADMIN_URI
pypgstac load collections /tmp/collections.json --dsn $PGADMIN_URI --method insert_ignore
pypgstac load items /tmp/items.json --dsn $PGADMIN_URI --method insert_ignore
```
