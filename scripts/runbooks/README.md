# Operational Runbooks

Standalone diagnostic scripts for running on client infrastructure.
Unlike the `eoapi-cli` commands, these require **no repo checkout** — they only need
`kubectl`, `curl`, and `python3` (and `hey`, which is auto-installed).

All output goes to both the terminal and a timestamped log file under `~/eoapi-loadtest-logs/`
(override with `LOG_DIR`).

## Scripts

### `loadtest.sh` — Load Test with HPA Validation

Runs a phased load test: baseline snapshot → HTTP load via `hey` → post-load snapshot → cooldown check.
Validates that HPAs scale up under load and back down after.

```bash
# Defaults (data-access namespace, 5m @ 50 concurrency)
bash loadtest.sh

# Custom
NS=data-access URL=https://stac.example.com/stac/collections \
  LOAD_DURATION=10m LOAD_CONCURRENCY=100 bash loadtest.sh
```

During the load phase, open a second terminal for live monitoring:

```bash
watch -n 5 'date -u +%H:%M:%S; echo; kubectl get hpa -n data-access; echo; kubectl top pods -n data-access 2>&1 | grep -iE "NAME|stac|auth-proxy"'
```

### `debug-collection.sh` — Collection Performance Debugging

Diagnoses slow or broken collections — especially large ones (millions of items) that
return 500s or timeouts on `/items`. Checks the API, database partitions, indexes,
query plans, connection pool, and pod logs.

```bash
# Default: debug sentinel-1-nrb
bash debug-collection.sh

# Any collection
bash debug-collection.sh sentinel-2-l2a

# Custom namespace / URL
NS=data-access STAC_URL=https://stac.example.com/stac \
  bash debug-collection.sh my-collection
```

## Environment Variables

### Common

| Variable | Default | Description |
|---|---|---|
| `NS` | `data-access` | Kubernetes namespace |
| `STAC_URL` | `https://stac-k8s.terrabyte.lrz.de/stac` | STAC API base URL |
| `RELEASE_NAME` | `eoapi` | Helm release name (for pod/deploy names) |
| `LOG_DIR` | `~/eoapi-loadtest-logs` | Directory for log files |

### Load test only

| Variable | Default | Description |
|---|---|---|
| `URL` | `$STAC_URL/collections` | Load test target URL |
| `LOAD_DURATION` | `5m` | Load test duration |
| `LOAD_CONCURRENCY` | `50` | Load test concurrency |

### Database overrides (debug-collection.sh)

The debug script auto-discovers the database by reading `PGHOST`, `PGUSER`, and
`PGDATABASE` from the STAC pod's environment. It handles cross-namespace databases
(e.g. a CNPG cluster in an `infra` namespace). If auto-discovery fails, override
manually:

| Variable | Default | Description |
|---|---|---|
| `DB_POD` | (auto-discovered) | Postgres pod name |
| `DB_NS` | (from PGHOST FQDN) | Namespace containing the DB pod |
| `DB_USER` | (from PGUSER) | Postgres user |
| `DB_NAME` | (from PGDATABASE) | Postgres database name |

Example with manual overrides:

```bash
DB_NS=infra DB_POD=default-1 DB_USER=eoapi DB_NAME=eoapi \
  bash debug-collection.sh sentinel-1-nrb
```

## Retrieving Logs

After running on a remote host:

```bash
scp user@host:~/eoapi-loadtest-logs/*.log ./
```
