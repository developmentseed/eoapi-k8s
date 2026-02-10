# PostgresCluster Helm Chart

A Helm chart wrapper for deploying PostgreSQL clusters using [CrunchyData's PostgreSQL Operator (PGO)](https://access.crunchydata.com/documentation/postgres-operator/).

## Purpose

This chart creates `PostgresCluster` custom resources that are managed by PGO. It serves as a configuration layer between eoAPI and the PostgreSQL operator, providing:

- **PostGIS support** for geospatial data
- **PgBouncer** connection pooling
- **Configurable backups** (S3, GCS, Azure, or volume-based)
- **eoAPI-specific defaults** for schema permissions and database setup

## Prerequisites

Install the PostgreSQL Operator first:

```bash
helm install --set disable_check_for_upgrades=true pgo \
  oci://registry.developers.crunchydata.com/crunchydata/pgo \
  --version 5.7.10
```

## Usage

This chart is typically used as a dependency of the main eoAPI chart:

```yaml
# In eoAPI's Chart.yaml
dependencies:
  - name: postgrescluster
    version: 5.7.10
    repository: "https://devseed.com/eoapi-k8s/"
    condition: postgrescluster.enabled
```

### Standalone Installation

```bash
helm install my-postgres ./charts/postgrescluster \
  --set postgresVersion=16 \
  --set postGISVersion=3.4
```

## Key Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresVersion` | PostgreSQL version | `16` |
| `postGISVersion` | PostGIS version | `3.4` |
| `pgBouncerReplicas` | Number of PgBouncer instances | `1` |
| `backupsEnabled` | Enable pgBackRest backups | `false` |
| `instances` | PostgreSQL instance configuration | See values.yaml |

### Instance Configuration

```yaml
instances:
  - name: postgres
    replicas: 2  # High availability with 2 replicas
    dataVolumeClaimSpec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

### Backup Configuration

```yaml
backupsEnabled: true
s3:
  bucket: "my-backups"
  endpoint: "s3.amazonaws.com"
  region: "us-east-1"
  key: "ACCESS_KEY_ID"
  keySecret: "SECRET_ACCESS_KEY"
```
