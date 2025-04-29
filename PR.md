# Refactor Helm Chart to Service-Specific Templates

## Overview

This PR refactors our Helm chart structure from a loop-based approach to service-specific templates. The primary goal is to improve readability, maintainability, and flexibility of our Kubernetes resource definitions.

## Problem Statement

The previous approach of looping over API services to generate Kubernetes resources created several challenges:

1. **Poor Readability**: Templates contained complex nested conditionals and loops
2. **Difficult Maintenance**: Changes to template structure affected all services
3. **Limited Flexibility**: Assumed all services followed the same pattern
4. **Debugging Challenges**: Hard to trace issues to specific services
5. **Upgrade Complexity**: Difficult to update individual services independently

## Changes Made

1. **Service-Specific Directory Structure**:
   - Created dedicated directories for each service (`raster`, `stac`, `vector`, `multidim`)
   - Each service directory contains its own templates (`deployment.yaml`, `service.yaml`, `configmap.yaml`, `hpa.yaml`)

2. **Common Helper Functions**:
   - Created a minimal `_common.tpl` with focused helper functions:
     - `eoapi.mountServiceSecrets` - For mounting service secrets
     - `eoapi.commonEnvVars` - For common environment variables
     - `eoapi.pgstacInitContainers` - For init containers that wait for pgstac jobs

3. **Service-Specific Configuration**:
   - Added ability to control ingress per service:
     ```yaml
     stac:
       enabled: true
       ingress:
         enabled: false  # Disable ingress for STAC only
     ```
   - Supports use cases like stac-auth-proxy where STAC API needs internal-only access
   - Maintains backward compatibility with existing configurations

4. **Integration with Existing Helpers**:
   - Used existing `eoapi.postgresqlEnv` helper for database environment variables
   - Maintained compatibility with other system helpers

5. **Documentation**:
   - Added a comprehensive README.md in the services directory explaining the refactoring approach
   - Documented the new directory structure and helper functions

## Benefits

1. **Improved Readability**: Service configurations are explicit and clearly visible
2. **Better Maintainability**: Changes to one service don't affect others
3. **Enhanced Flexibility**: 
   - Each service can evolve independently
   - Can enable/disable features per service (like ingress)
4. **Easier Debugging**: Errors are isolated to specific service files
5. **Safer Changes**: Template modifications can be tested on individual services
6. **Reduced Cognitive Load**: Developers can understand one service at a time

## Example Use Cases

1. **STAC with Auth Proxy**:
   ```yaml
   # values.yaml
   stac:
     enabled: true
     ingress:
       enabled: false  # No external ingress for STAC
   ```
   This allows stac-auth-proxy to handle external access while STAC API remains internal.

2. **Mixed Access Patterns**:
   ```yaml
   stac:
     ingress:
       enabled: false  # Internal only
   raster:
     ingress:
       enabled: true   # External access
   ```
   Different services can have different access patterns.

## Testing

The refactored templates have been tested using:

1. `helm template` validation to ensure proper YAML generation
2. Installation testing in a development environment
3. Verification that all services deploy and function correctly
4. Running the updated test suite to ensure all tests pass
5. Comparison of the generated resources with the previous approach to ensure no functional changes

## Backward Compatibility

This refactoring maintains full backward compatibility with existing values files and deployments. No changes to values.yaml structure were required, and the chart can be upgraded in-place without disruption.

## Next Steps

Future improvements could include:

1. Further service-specific customizations (e.g., annotations, labels)
2. Enhanced documentation of service-specific options
3. Schema validation for service-specific values
4. Additional common helpers as patterns emerge

Closes #211
