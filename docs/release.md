---
title: "Release Workflow"
description: "Chart versioning, GitHub releases, and Helm repository publishing process"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Conventional Commits"
    url: "https://www.conventionalcommits.org/"
  - name: "Semantic Versioning"
    url: "https://semver.org/"
---

# Release Workflow

Releases are automated with [release-please](https://github.com/googleapis/release-please).

1. Use [Conventional Commits](https://www.conventionalcommits.org/) on commits merged to `main` (`feat:`, `fix:`, etc.). These drive the next semver bump and changelog.
2. release-please opens (or updates) a release PR that bumps the eoapi chart version and updates `CHANGELOG.md`.
3. Approve and merge that PR. That creates the GitHub release tag and triggers chart-releaser, which publishes updated Helm charts to the repo index.

Verify with:

```bash
helm repo update && helm search repo eoapi --versions
```

## Postgrescluster

When `charts/postgrescluster/Chart.yaml` version changes on `main`, a separate workflow packages and publishes that chart automatically. No release PR is required.
