---
title: "Data Management"
description: "Loading and exporting STAC collections and items in a PgSTAC database"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "PgSTAC Documentation"
    url: "https://github.com/stac-utils/pgstac"
  - name: "STAC Specification"
    url: "https://stacspec.org/"
---

# Data management

eoAPI-k8s provides a basic data ingestion process that consist of manual operations on the components of the stack.

Data management is built from two layers:

- **`scripts/raw/`** — the actual load/export logic. Each script only needs `psql` (and, for
  ingest, `jq`) on `PATH` and a reachable Postgres DSN — no `kubectl`, no cluster, nothing
  Kubernetes-specific at all. Run these directly against any PgSTAC database: local, external,
  port-forwarded, whatever.
- **`eoapi-cli ingest` / `eoapi-cli export`** (`scripts/data-management.sh`) — a thin Kubernetes
  convenience wrapper around the scripts above. Pass an explicit DSN and it just passes straight
  through, no `kubectl` calls at all; omit it and it auto-discovers and port-forwards the
  *current* cluster's own database for you.

You will need STAC records for the collections and items you wish to load (e.g. `collections.json`
and `items.json`, NDJSON or a plain JSON document either way).
[This repo](https://github.com/vincentsarago/MAXAR_opendata_to_pgstac) contains a few scripts that
may help you generate sample input data.

# Load data

`scripts/raw/ingest.sh --dsn DSN [COLLECTIONS_FILE] [ITEMS_FILE]` loads STAC collections/items into
a PgSTAC database, using the same "insert, ignore duplicates" semantics as `pypgstac load --method
insert_ignore` — but talking to pgstac's own SQL functions (`pgstac.upsert_collection`, the
`pgstac.items_staging_ignore` staging table) directly instead of depending on `pypgstac`. Files
default to `./collections.json` / `./items.json`.

```bash
scripts/raw/ingest.sh --dsn "postgresql://user:pass@host:5432/postgis" collections.json items.json
```

`eoapi-cli ingest [COLLECTIONS_FILE] [ITEMS_FILE]` wraps this for the current cluster: with
`--target-dsn`, it passes straight through (no `kubectl` involved); without it, it auto-discovers
and port-forwards the cluster's own database, the same way `eoapi-cli export` does (see below).

# Export data

STAC collections and items can be exported from a PgSTAC database to `collections.ndjson` and
`items.ndjson`, loadable straight back in with `eoapi-cli ingest OUTPUT_DIR/collections.ndjson
OUTPUT_DIR/items.ndjson`. This is primarily meant for migrating data between PgSTAC instances:
export from an old instance, then ingest the result into a new one.

```bash
scripts/raw/export.sh --dsn "postgresql://user:pass@old-pgstac-host:5432/postgis" ./stac-export
```

Use `--collection <id>` (repeatable) to export only specific collections instead of the whole
catalog.

`eoapi-cli export [OUTPUT_DIR]` wraps this the same way as ingest: pass `--source-dsn` to export
from an external PgSTAC instance (e.g. the old one you're migrating away from) — this just passes
straight through to `scripts/raw/export.sh`, no `kubectl` calls happen at all:

```bash
eoapi-cli export --source-dsn "postgresql://user:pass@old-pgstac-host:5432/postgis" ./stac-export
```

## Auto-discovery (no --source-dsn / --target-dsn)

Without an explicit DSN, both `eoapi-cli` commands auto-discover and port-forward the *current*
cluster's own database (useful for testing/round-tripping against a dev deployment): they read the
`{release}-pguser-postgres` secret's `uri` key, find the CrunchyData PGO primary pod (via its
`postgres-operator.crunchydata.com/role=master` label — the `-primary` Service itself is headless
with no selector, so `kubectl port-forward` can't target it directly), port-forward to that pod,
and call the matching `scripts/raw/` script with the resulting local DSN. This only works when
`postgresql.type` is `postgrescluster` (the chart's default) — for external-database
configurations, pass `--source-dsn`/`--target-dsn` directly instead. Verified against a real k3d
deployment.

## How export hydration works

Items are stored dehydrated in PgSTAC (fields shared with the collection are stripped out to save
space), so a plain `SELECT * FROM items` would not produce valid, complete STAC Items. The script
calls PgSTAC's own `pgstac.content_hydrate(items)` SQL function to reassemble full items, and
streams query output straight to a file via psql's `\o` redirection (with unaligned, tuples-only
output — one JSON object per line, i.e. NDJSON) — all within a single psql session per invocation,
rather than one connection per query, since some port-forward setups only tolerate a small number
of sequential connections before the tunnel drops.

**Caveat:** `content_hydrate()`'s exact signature has changed across PgSTAC releases (and may
change again). The script verifies the function exists on the source database before exporting and
fails with a clear error otherwise. If you hit that error against an unusual/very old or very new
PgSTAC version, fall back to inspecting the source database directly (`\df pgstac.*hydrate*` in
`psql`) and adjust the export query manually — collections are stored whole and can always be
exported directly with `select content from pgstac.collections`.

Ingest has the same kind of version sensitivity in reverse: it relies on `pgstac.upsert_collection`
and the `pgstac.items_staging_ignore` staging table existing, and verifies both before loading.
`scripts/raw/ingest.sh` deliberately avoids `psql \copy` for the bulk item load — its default TEXT
format treats backslash as its own escape character, which can corrupt JSON strings that already
contain backslash sequences. Instead it streams one `insert into pgstac.items_staging_ignore
(content) values ('<escaped>'::jsonb);` statement per record through a single `psql -f -` session,
inside one transaction.
