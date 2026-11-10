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

## Image scan

`.github/workflows/image-scan.yml` scans every image the chart can deploy with [Trivy](https://trivy.dev/): every Monday, on demand, and on the release-please PR. A red check means an image has a fixable HIGH or CRITICAL vulnerability. Fix it at the source (a release of that image, then a tag bump here) before releasing. Other pull requests only check the image list.

- **Image list.** The workflow renders the chart (every optional component on, plus the experimental and production profiles) and the database images PGO picks, then compares their repositories with `.github/image-scan-repos.txt`. A PR that adds or drops an image, including a new `*.enabled` component, updates that file.
- **Exceptions** last at most 30 days and say why:
  - images built in `developmentseed` or `stac-utils`: one entry per finding in `.trivyignore.yaml`, with `expired_at` and a factual `statement`;
  - a third-party image whose vendor has no fixed image yet: `report-only until YYYY-MM-DD: <reason>` on its line in `image-scan-repos.txt`. Its findings still print.
  - busybox has no package database, so Trivy cannot scan it; re-date its line each month.
- **"Are we affected by X?"** Each scan keeps the image's SBOM for 90 days. Download them with `gh run download <run-id> -R developmentseed/eoapi-k8s`, then `grep -il <package> sbom-*/sbom.cdx.json`, or run `trivy sbom` on each file to look for an advisory ID. The SBOMs describe the tags pinned at that commit.
- **Blind spots.** A green run does not mean "not affected". Trivy does not see runtimes installed from tarballs, bundled JavaScript, or binaries without package metadata. The scan fails an image whose SBOM has no packages, or whose Wolfi packages lost their source names; that loss is intermittent, so re-run the job.
- **Security tab.** Scheduled and manual runs also list the same findings under Security > Code scanning, one category per image (`image:<repository>`), labelled with Trivy's severity.

The release-PR check is not a required check yet. It becomes one once a release PR passes it.
