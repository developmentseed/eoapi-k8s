# Testing Infrastructure

This directory contains Kubernetes resources for **testing purposes only**.

## ⚠️ WARNING

**DO NOT USE THESE COMPONENTS IN PRODUCTION ENVIRONMENTS**

These resources are designed exclusively for:
- Integration testing
- Local development
- CI/CD pipelines

## Components

### Mock OIDC Server

A mock OpenID Connect server for testing `stac-auth-proxy` authentication integration.

- **Enabled in**: `experimental.yaml` profile only
- **Purpose**: Provides JWT tokens for auth testing
- **Image**: `ghcr.io/alukach/mock-oidc-server`
- **Used by**: Integration tests in `tests/integration/test_stac_auth.py`

**Configuration**:
```yaml
testing:
  mockOidcServer:
    enabled: true  # Only set to true in test environments
```

## Security Notice

Mock OIDC server has NO security features and should NEVER be exposed to production traffic.
