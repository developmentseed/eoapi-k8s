---
title: "Release Workflow"
description: "Chart versioning, GitHub releases, and Helm repository publishing process"
external_links:
  - name: "eoapi-k8s Repository"
    url: "https://github.com/developmentseed/eoapi-k8s"
  - name: "Semantic Versioning"
    url: "https://semver.org/"
  - name: "Helm Chart Best Practices"
    url: "https://helm.sh/docs/chart_best_practices/"
---

# Release Workflow

1. PRs that include changes in the `charts/<eoapi> || <eoapi-support> || <postgrescluster>` charts are manually required to consider
whether their changes are major, minor or patch (in terms of semantic versioning) and bump the appropriate
chart `version: ` (which follows semver) and `appVersion: ` (which does not follow semver) for each affected chart

3. The releaser then merges the above PR

4. Then the releaser should go to the Github release UI/UX and kick off a new release by doing the following:

   1. click "Draft New Release"

   2. create a new tag increment based on the last one that matches the pattern `v<major>.<minor>.<patch>`. This does not have to match any of the chart versions you changed in the above PR. This repository is one-to-many with charts. So in terms of GH release we are saying, "we've release one of the three charts above" and the commit message will reflect that

   3. click the "Generate release notes"

   4. review the release notes and clean up and makes sure talk about which chart you released

   5. click the "Publish release"


5. This last step triggers the **release-please.yml** workflow (publish job), which runs chart-releaser and publishes any helm charts that had version bumps since the last release. The **postgrescluster** chart is released automatically when a new version is merged to main (see below); by release time it is already in the Helm repo, so eoapi can depend on it from the remote.

6. Verify the release: `helm repo update && helm search repo eoapi --versions`. If a new chart version does not appear, the index may be cached; try `helm repo update --force-update` or re-add the repo using the GitHub Pages URL: `helm repo add eoapi https://developmentseed.github.io/eoapi-k8s/`

## Postgrescluster (automatic on main)

When a new **postgrescluster** chart version is merged to main, the `release.yml` workflow (push trigger) packages the chart, creates a GitHub Release with tag `postgrescluster-<version>` (via chart-releaser and the same GitHub App as release-please, `DS_RELEASE_BOT_*`), and updates the Helm repo index—all in the same run. No manual release step is needed for postgrescluster. The "proper" release (step 4 above, tag `vX.Y.Z`) is for eoapi; do it after postgrescluster has been auto-released if eoapi depends on the new version.
