# EOAPI Helm Chart

This Helm chart deploys the EOAPI (Earth Observation API) stack, which includes STAC API, raster tile services, vector tile services, and a multidimensional data service.

## Overview

The chart sets up:

- A PostgreSQL database with PostGIS and PgSTAC extensions
- STAC API service for metadata discovery and search
- Titiler for raster tile services
- TIPG for vector tile services
- Optional multidimensional data service

## Prerequisites

- Kubernetes 1.16+
- Helm 3.0+
- PV provisioner support in the underlying infrastructure
- CrunchyData Postgres Operator (for the PostgreSQL database)

## Installation

```bash
# Install Postgres Operator first
helm install --set disable_check_for_upgrades=true pgo oci://registry.developers.crunchydata.com/crunchydata/pgo

# Then install eoapi
helm install eoapi ./eoapi
```

## Configuration

The chart can be configured via `values.yaml`. See the chart's `values.yaml` file for all available options and detailed descriptions.

Key configuration sections:

```yaml
# Services to enable
apiServices:
  - raster
  - stac
  - vector
  # - multidim (disabled by default)

# Ingress configuration
ingress:
  enabled: true
  className: "nginx"
  # ...

# Database configuration
postgrescluster:
  enabled: true
  # ...
```

## PgSTAC Bootstrap Process

The chart includes a streamlined process for initializing and setting up the PgSTAC database.

### PgSTAC Bootstrap Overview

The setup process consists of two main jobs:

1. **pgstac-migrate job**: Runs the pypgstac migrate command to initialize the database schema, applies settings, and sets necessary permissions.
2. **pgstac-load-samples job**: (Optional) Loads sample STAC data only when sample loading is enabled.

### Improvements in PgSTAC Bootstrap

- Replaced custom Python script with pypgstac migrate command
- Moved SQL settings to a dedicated SQL file for better maintainability
- Separated sample data loading into an optional job
- Uses standard PostgreSQL environment variables
- Ensures the process remains idempotent for safe re-runs

### PgSTAC Directory Structure

The codebase has been reorganized to separate different types of files:

- `initdb-data/settings/`: Contains configuration settings like the PgSTAC settings SQL file
- `initdb-data/samples/`: Contains sample data files that are loaded only when sample loading is enabled

### PgSTAC Configuration

- Enable/disable the setup process through `pgstacBootstrap.enabled`
- Control sample data loading: 
  - New approach: `pgstacBootstrap.settings.loadSamples` (recommended)
  - Legacy approach: `pgstacBootstrap.settings.envVars.LOAD_FIXTURES` (deprecated)

Example configuration:

```yaml
pgstacBootstrap:
  enabled: true
  settings:
    # General configuration options
    loadSamples: true      # Set to false to disable sample data loading
    
    resources:
      requests:
        cpu: "512m"
        memory: "1024Mi"
      limits:
        cpu: "512m"
        memory: "1024Mi"
```

## Services

### STAC API

The STAC API service provides a standardized way to search and discover geospatial data.

### Raster Services (Titiler)

Provides dynamic tiling for raster data through the TiTiler implementation.

### Vector Services (TIPG)

Provides vector tile services for PostGIS data through the TIPG implementation.

### Multidimensional Services (Optional)

Provides services for multidimensional data (time series, etc.).

## Persistence

The chart uses PostgreSQL for data persistence. Make sure to configure appropriate storage for production use.

## Upgrading

When upgrading the chart, consider any changes to values.yaml and migrations that might need to be applied.

## Uninstallation

```bash
helm delete eoapi
```

Note that PVs may need to be manually deleted if you want to remove all data.
