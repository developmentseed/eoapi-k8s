---
title: "Data Management"
description: "Loading STAC collections and items into PostgreSQL using pypgstac"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "pypgstac Documentation"
    url: "https://github.com/stac-utils/pypgstac"
  - name: "STAC Specification"
    url: "https://stacspec.org/"
---

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

# Export data

Execute `eoapi-cli export [OUTPUT_DIR]` to export the STAC collections and items from a PgSTAC
database to `collections.ndjson` and `items.ndjson` in `OUTPUT_DIR` (defaults to `./stac-export`).
This is primarily meant for migrating data between PgSTAC instances: export from an old instance,
then load the result into a new one with `eoapi-cli ingest OUTPUT_DIR/collections.ndjson
OUTPUT_DIR/items.ndjson`.

By default, it exports from the target cluster's own database. Pass `--source-dsn` to export from
a different PgSTAC instance instead (e.g. the old one you're migrating away from), as long as it's
network-reachable from the cluster:

```bash
eoapi-cli export --source-dsn "postgresql://user:pass@old-pgstac-host:5432/postgis" ./stac-export
```

Use `--collection <id>` (repeatable) to export only specific collections instead of the whole
catalog.

## How it works

Items are stored dehydrated in PgSTAC (fields shared with the collection are stripped out to save
space), so a plain `SELECT * FROM items` would not produce valid, complete STAC Items. The script
calls PgSTAC's own `pgstac.content_hydrate(items)` SQL function to reassemble full items, and
streams the result straight out via `psql -tAc` (unaligned, tuples-only output — one JSON object
per line, i.e. NDJSON) over `kubectl exec`.

**Caveat:** `content_hydrate()`'s exact signature has changed across PgSTAC releases (and may
change again). The script verifies the function exists on the source database before exporting and
fails with a clear error otherwise. If you hit that error against an unusual/very old or very new
PgSTAC version, fall back to inspecting the source database directly (`\df pgstac.*hydrate*` in
`psql`) and adjust the export query manually — collections are stored whole and can always be
exported directly with `select content from pgstac.collections`.
