# PgSTAC Bootstrap

This directory contains Kubernetes resources for initializing and setting up the PgSTAC database.

## Overview

The setup process has been simplified to:

1. **pgstac-migrate job**: Runs the pypgstac migrate command to initialize the database schema, applies settings, and sets necessary permissions.
2. **pgstac-load-samples job**: (Optional) Loads sample STAC data only when `LOAD_FIXTURES` is enabled.

## Improvements

- Replaced custom Python script with pypgstac migrate command
- Moved SQL settings to a dedicated SQL file for better maintainability
- Separated sample data loading into an optional job
- Uses standard PostgreSQL environment variables instead of DSN
- Ensures the process remains idempotent for safe re-runs

## Files

- `job.yaml`: Contains the Kubernetes Job definitions
- `configmap.yaml`: Contains ConfigMaps with settings and SQL files 

## Directory Structure

The codebase has been reorganized to separate different types of files:

- `initdb-data/settings/`: Contains configuration settings like the PgSTAC settings SQL file
- `initdb-data/samples/`: Contains sample data files that are loaded only when sample loading is enabled

## Configuration

- Enable/disable the setup process through `pgstacBootstrap.enabled`
- Control sample data loading: 
  - New approach: `pgstacBootstrap.settings.loadSamples` (recommended)
  - Legacy approach: `pgstacBootstrap.settings.envVars.LOAD_FIXTURES` (deprecated)

## New Settings Structure

The configuration has been updated to use a more structured settings approach:

```yaml
pgstacBootstrap:
  enabled: true
  settings:
    # General configuration options
    loadSamples: true      # Set to false to disable sample data loading
    
    # Other settings remain the same
    resources:
      requests:
        cpu: "512m"
        memory: "1024Mi"
      limits:
        cpu: "512m"
        memory: "1024Mi"
```

The old `envVars` approach is still supported for backward compatibility but is deprecated.
