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

## Chart dependencies

`charts/eoapi/Chart.lock` is committed so installs and CI resolve the same subchart versions. Exact versions stay pinned in `Chart.yaml`.

To bump a dependency:

1. Edit the version in `charts/eoapi/Chart.yaml`
2. Run `helm dependency update charts/eoapi` (regenerates `Chart.lock` and downloads charts)
3. Review and commit both `Chart.yaml` and `Chart.lock`

Day-to-day local/CI workflows use `helm dependency build` against the lockfile. HTTPS chart repos must be added first (`helm repo add`); OCI dependencies do not need that. Prefer Helm 3.18.x for dependency updates; CI and release workflows pin `v3.18.3`.

## Postgrescluster

When `charts/postgrescluster/Chart.yaml` version changes on `main`, a separate workflow packages and publishes that chart automatically. No release PR is required.
